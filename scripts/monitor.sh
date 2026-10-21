#!/bin/bash
# =============================================================================
#  EcosystemGuard —— 高 CPU 进程监控与自动清理
#
#  工作原理：
#    1. 每隔 INTERVAL 秒采样一次 /bin/ps，读取目标进程的 CPU 占用；
#    2. 连续 SUSTAIN 次超过 THRESHOLD 才判定为「真的失控」，避免瞬时抖动误杀；
#    3. 先发 SIGTERM 让进程自己退出，2 秒后仍在则补一发 SIGKILL；
#    4. 清理后进入 COOLDOWN 秒冷却期，并且每小时最多清理 MAX_KILLS_PER_HOUR 次，
#       防止「杀了又被系统拉起、再杀」的反复循环反而拖慢电脑。
#
#  运行身份：root（由 launchd 以 LaunchDaemon 方式常驻）
#  配置文件：/Library/Application Support/EcosystemGuard/config.conf
#  日志文件：/var/log/ecosystemguard.log
# =============================================================================

set -u

BASE_DIR="/Library/Application Support/EcosystemGuard"
# 以下三个变量可用环境变量覆盖，方便在不安装的情况下做测试
CONF="${ECOGUARD_CONF:-$BASE_DIR/config.conf}"
LOG="${ECOGUARD_LOG:-/var/log/ecosystemguard.log}"
STATE_DIR="${ECOGUARD_STATE:-/var/run/ecosystemguard}"
# 每次清理追加一行 TSV，独立于日志滚动，供 `ecoguard stats` 统计
STATS_FILE="${ECOGUARD_STATS:-$BASE_DIR/kills.log}"

PS_BIN="/bin/ps"
KILL_BIN="/bin/kill"
LAUNCHCTL_BIN="/bin/launchctl"

# ----------------------------- 默认配置（可被 config.conf 覆盖）--------------
TARGET_NAMES="ecosystemd ecosystemanalyticsd"
# 绝对不碰的进程：WindowServer 一旦被杀会直接黑屏 / 强制注销
DENY_NAMES="WindowServer kernel_task launchd loginwindow WindowManager Dock Finder SystemUIServer ControlCenter WindowServerHelper"
THRESHOLD=25          # CPU 百分比阈值
INTERVAL=10           # 采样间隔（秒）
SUSTAIN=3             # 连续多少次超阈值才动手
COOLDOWN=180          # 一次清理后的冷却时间（秒）
MAX_KILLS_PER_HOUR=12 # 每小时最多清理次数
MODE="kill"           # kill=只清理 / disable=尝试禁用系统服务 / both=两者都做
DISABLE_LABELS="com.apple.ecosystemd com.apple.ecosystemanalyticsd"
LOG_MAX_KB=512

# ----------------------------- 基础工具 --------------------------------------
log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true
}

in_list() {   # in_list <单词> <空格分隔的列表>
    case " $2 " in
        *" $1 "*) return 0 ;;
        *)        return 1 ;;
    esac
}

rotate_log() {
    [ -f "$LOG" ] || return 0
    local size_kb
    size_kb=$(( $(/usr/bin/stat -f %z "$LOG" 2>/dev/null || echo 0) / 1024 ))
    if [ "$size_kb" -gt "$LOG_MAX_KB" ]; then
        mv -f "$LOG" "$LOG.1" 2>/dev/null || true
    fi
}

float_ge() {  # float_ge <a> <b>  → a >= b 时返回 0
    /usr/bin/awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'
}

# ----------------------------- 配置加载 --------------------------------------
load_config() {
    if [ -f "$CONF" ]; then
        # shellcheck disable=SC1090
        . "$CONF" || log "警告：config.conf 解析失败，使用默认配置"
    else
        log "警告：未找到 $CONF，使用默认配置"
    fi
}

# ----------------------------- 系统服务禁用 --------------------------------
# 说明：这两个进程由 launchd 托管，被杀后会被立即重新拉起。
#       MODE=disable/both 时额外尝试让 launchd 不再拉起它们（需要 SIP 允许，
#       若系统拒绝会在日志里记录失败原因，监控仍继续按阈值清理）。
try_disable_services() {
    local label out
    for label in $DISABLE_LABELS; do
        if out=$("$LAUNCHCTL_BIN" disable "system/$label" 2>&1); then
            log "[disable] 已禁用 $label（重启后依然有效，可用 ecoguard restore 恢复）"
        else
            log "[disable] 无法禁用 $label：${out:-未知原因}（改用清理方式）"
        fi
        unload_service "$label"
    done
}

# 仅 disable 不够：已经加载在 launchd 里的 job 仍会被按需重新拉起，
# 必须 bootout 把它从 launchd 卸载，才不会“杀掉又回来”。
unload_service() {
    local label="$1" out
    "$LAUNCHCTL_BIN" print "system/$label" >/dev/null 2>&1 || return 0
    if out=$("$LAUNCHCTL_BIN" bootout "system/$label" 2>&1); then
        log "[unload] 已从 launchd 卸载 $label，不会再被自动拉起"
    else
        log "[unload] 无法卸载 $label：${out:-未知原因}（改为按阈值反复清理）"
    fi
}

# ----------------------------- 清理动作 --------------------------------------
kill_process() {
    local pid="$1" cpu="$2" name="$3" streak="$4"

    if [ "$MODE" = "disable" ]; then
        log "跳过清理：MODE=disable，仅依赖系统服务禁用 ｜ $name(pid $pid, ${cpu}%)"
        return 0
    fi
    if [ $(( now - last_kill )) -lt "$COOLDOWN" ]; then
        log "跳过清理：冷却中，还剩 $(( COOLDOWN - (now - last_kill) )) 秒 ｜ $name(pid $pid, ${cpu}%)"
        return 0
    fi
    if [ "$kills_this_hour" -ge "$MAX_KILLS_PER_HOUR" ]; then
        log "跳过清理：本小时已达上限 $MAX_KILLS_PER_HOUR 次 ｜ $name(pid $pid, ${cpu}%)"
        return 0
    fi

    log "触发清理：$name (pid $pid) CPU ${cpu}%，连续 ${streak} 次 ≥ ${THRESHOLD}% → 发送 SIGTERM"
    "$KILL_BIN" -TERM "$pid" 2>/dev/null || true
    sleep 2
    if "$KILL_BIN" -0 "$pid" 2>/dev/null; then
        "$KILL_BIN" -KILL "$pid" 2>/dev/null || true
        log "  └ pid $pid 未响应 SIGTERM，已升级为 SIGKILL"
    else
        log "  └ pid $pid 已退出"
    fi

    # 记一笔账：时间 <TAB> 进程名 <TAB> pid <TAB> CPU%。独立文件，不受日志滚动影响
    printf '%s\t%s\t%s\t%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$name" "$pid" "$cpu" >>"$STATS_FILE" 2>/dev/null || true

    last_kill=$now
    kills_this_hour=$(( kills_this_hour + 1 ))
    rm -f "$STATE_DIR/$pid.streak" 2>/dev/null || true

    # 顺手把对应的 launchd 服务卸载，否则几秒后又会被拉起（名字对不上时静默跳过）
    unload_service "com.apple.$name"
}

# ----------------------------- 单轮采样 --------------------------------------
sample_once() {
    local snap="$STATE_DIR/snapshot.txt"
    "$PS_BIN" -Ao pid=,pcpu=,comm= 2>/dev/null | /usr/bin/awk '
        {
            pid = $1; cpu = $2; cmd = ""
            for (i = 3; i <= NF; i++) cmd = cmd (i > 3 ? " " : "") $i
            n = split(cmd, parts, "/")
            printf "%s %s %s\n", pid, cpu, parts[n]
        }' >"$snap" 2>/dev/null

    local pid cpu base streak_file streak
    while read -r pid cpu base; do
        [ -n "${pid:-}" ] || continue

        # 1) 先排除受保护进程（防止配置写错导致误杀 WindowServer 之类）
        if in_list "$base" "$DENY_NAMES"; then
            continue
        fi
        # 2) 只关心目标进程
        in_list "$base" "$TARGET_NAMES" || continue
        # 3) 跳过自己
        [ "$pid" = "$$" ] && continue

        streak_file="$STATE_DIR/$pid.streak"
        if float_ge "$cpu" "$THRESHOLD"; then
            streak=$(cat "$streak_file" 2>/dev/null || echo 0)
            streak=$(( streak + 1 ))
            printf '%s\n' "$streak" >"$streak_file"
            if [ "$streak" -ge "$SUSTAIN" ]; then
                kill_process "$pid" "$cpu" "$base" "$streak"
            fi
        else
            if [ -f "$streak_file" ]; then
                rm -f "$streak_file"
                log "$base(pid $pid) CPU 已回落到 ${cpu}%，解除计数"
            fi
        fi
    done <"$snap"
}

# ----------------------------- 清理陈旧状态 ----------------------------------
clean_stale_state() {
    local f pid
    for f in "$STATE_DIR"/*.streak; do
        [ -f "$f" ] || continue
        pid=$(basename "$f" .streak)
        if ! "$KILL_BIN" -0 "$pid" 2>/dev/null; then
            rm -f "$f"
        fi
    done
}

# ----------------------------- 主流程 ----------------------------------------
main() {
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    rotate_log
    load_config

    log "================ EcosystemGuard 启动 (pid $$) ================"
    log "目标进程：$TARGET_NAMES"
    log "判定条件：CPU ≥ ${THRESHOLD}%，连续 ${SUSTAIN} 次（每 ${INTERVAL} 秒采样一次）"
    log "保护名单：$DENY_NAMES"
    log "冷却时间：${COOLDOWN} 秒；每小时上限：${MAX_KILLS_PER_HOUR} 次；模式：$MODE"

    trap 'log "================ 收到停止信号，监控退出 ================"; exit 0' TERM INT

    case "$MODE" in
        disable|both) try_disable_services ;;
    esac

    clean_stale_state

    local hour_start=$(( $(date +%s) / 3600 )) tick=0
    last_kill=0
    kills_this_hour=0
    now=$(date +%s)

    while :; do
        now=$(date +%s)

        # 每满一小时重置清理计数
        local cur_hour=$(( now / 3600 ))
        if [ "$cur_hour" -ne "$hour_start" ]; then
            hour_start=$cur_hour
            kills_this_hour=0
            log "新的统计周期，清理次数归零"
        fi

        tick=$(( tick + 1 ))
        if [ $(( tick % 60 )) -eq 0 ]; then
            rotate_log
            clean_stale_state
        fi

        sample_once
        sleep "$INTERVAL"
    done
}

main
