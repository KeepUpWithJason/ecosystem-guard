#!/bin/bash
# =============================================================================
#  EcosystemGuard 安装脚本
#
#  用法：./install.sh        （不要加 sudo，脚本会自己弹窗提权）
#
#  为什么不需要 sudo：install.sh 会先把整个仓库复制到 /tmp，再以管理员身份
#  执行副本。这样既避开了“桌面/文稿”目录的隐私保护（root 读不到），
#  也避免直接用 sudo 出现 TCC 权限错误。
# =============================================================================

set -u

SRC="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="/Library/Application Support/EcosystemGuard"
LABEL="com.local.ecosystemguard"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
SUDOERS="/etc/sudoers.d/ecoguard"
LOG="/var/log/ecosystemguard.log"
LAUNCHCTL="/bin/launchctl"

# ---------------------------- 非 root：提权后重跑 ---------------------------
if [ "$(id -u)" -ne 0 ]; then
    STAGE="$(/usr/bin/mktemp -d /tmp/ecosystem-guard.XXXXXX)" || { echo "无法创建临时目录"; exit 1; }
    if ! /bin/cp -R "$SRC"/. "$STAGE"/ 2>/dev/null; then
        echo "复制安装文件失败，请把项目移到「用户目录」或「下载」后重试。"
        exit 1
    fi
    /bin/chmod -R go+rX "$STAGE" 2>/dev/null

    /usr/bin/osascript - "$STAGE" <<'APPLESCRIPT'
on run argv
  set d to item 1 of argv
  do shell script "cd " & quoted form of d & " && /bin/bash ./install.sh" with administrator privileges
end run
APPLESCRIPT
    rc=$?
    /bin/rm -rf "$STAGE"
    exit $rc
fi

# ---------------------------- root：真正安装 --------------------------------
echo "==> 检查安装文件"
for f in scripts/monitor.sh scripts/ecoguard config/config.conf.example launchd/com.local.ecosystemguard.plist; do
    [ -f "$SRC/$f" ] || { echo "错误：缺少文件 $f"; exit 1; }
done
/usr/bin/plutil -lint "$SRC/launchd/com.local.ecosystemguard.plist" >/dev/null \
    || { echo "错误：plist 格式不正确"; exit 1; }

# 当前登录的图形界面用户（用于配置免密控制）
CONSOLE_USER="$(/usr/bin/stat -f %Su /dev/console 2>/dev/null)"
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ] || ! printf '%s' "$CONSOLE_USER" | /usr/bin/grep -Eq '^[A-Za-z0-9._-]+$'; then
    CONSOLE_USER="$(/usr/bin/id -un)"
fi

echo "==> 安装文件到 $BASE_DIR"
/bin/mkdir -p "$BASE_DIR"
/usr/bin/install -o root -g wheel -m 755 "$SRC/scripts/monitor.sh" "$BASE_DIR/monitor.sh"
/bin/mkdir -p /usr/local/sbin
/usr/bin/install -o root -g wheel -m 755 "$SRC/scripts/ecoguard" "/usr/local/sbin/ecoguard"

# 配置文件只在首次安装时写入，之后升级不会覆盖你改过的参数
if [ -f "$BASE_DIR/config.conf" ]; then
    echo "==> 保留已有的 config.conf"
else
    /usr/bin/install -o root -g wheel -m 644 "$SRC/config/config.conf.example" "$BASE_DIR/config.conf"
fi

# 把历史日志里的清理记录迁移到统计文件（只做一次，之后由 monitor.sh 自己追加）
STATS="$BASE_DIR/kills.log"
if [ ! -f "$STATS" ]; then
    echo "==> 迁移历史清理记录"
    {
        echo "# 由 install.sh 于 $(date '+%Y-%m-%d %H:%M:%S') 从历史日志迁移"
        for f in "$LOG.1" "$LOG"; do
            [ -f "$f" ] || continue
            /usr/bin/awk '/触发清理：/ {
                split($3, p, "："); name = p[2]
                pid = $5; gsub(/[()]/, "", pid)
                cpu = $7; sub(/%.*/, "", cpu)
                printf "%s %s\t%s\t%s\t%s\n", $1, $2, name, pid, cpu
            }' "$f"
        done
    } >"$STATS"
    /usr/bin/chown root:wheel "$STATS" 2>/dev/null || true
    /usr/bin/chmod 644 "$STATS"
    echo "    已迁移 $(/usr/bin/grep -vc '^#' "$STATS" 2>/dev/null || echo 0) 条记录"
fi

echo "==> 注册开机自启服务"
/usr/bin/install -o root -g wheel -m 644 "$SRC/launchd/com.local.ecosystemguard.plist" "$PLIST"

echo "==> 配置免密开关（仅限 ecoguard 控制脚本，其他命令仍需密码）"
if [ -d /etc/sudoers.d ]; then
    /bin/rm -f "$SUDOERS"
    /bin/cat >"$SUDOERS" <<EOF
# EcosystemGuard：允许 $CONSOLE_USER 免密启停监控（只放开这一个脚本）
$CONSOLE_USER ALL=(root) NOPASSWD: /usr/local/sbin/ecoguard start, /usr/local/sbin/ecoguard stop, /usr/local/sbin/ecoguard restart, /usr/local/sbin/ecoguard status, /usr/local/sbin/ecoguard log
EOF
    /bin/chmod 440 "$SUDOERS"
    /bin/chown root:wheel "$SUDOERS" 2>/dev/null || true
    if ! /usr/sbin/visudo -cf "$SUDOERS" >/dev/null 2>&1; then
        echo "    ⚠️  sudoers 校验失败，已回滚（双击控制文件时会改为弹窗要密码）"
        /bin/rm -f "$SUDOERS"
    fi
fi

echo "==> 启动监控"
# launchd 的 bootout 是异步的（约 5 秒清理期）。清理完成前 bootstrap 会被忽略，
# 之后服务反而会被彻底移除，所以必须等确认卸载完成再重新加载。
"$LAUNCHCTL" bootout "system/$LABEL" 2>/dev/null || true
wait_i=0
while "$LAUNCHCTL" print "system/$LABEL" >/dev/null 2>&1 && [ "$wait_i" -lt 30 ]; do
    sleep 0.5
    wait_i=$((wait_i + 1))
done

"$LAUNCHCTL" enable "system/$LABEL" 2>/dev/null || true
"$LAUNCHCTL" bootstrap system "$PLIST" 2>/dev/null || true
"$LAUNCHCTL" kickstart -k "system/$LABEL" 2>/dev/null || true

# 等进程真正跑起来（job 被加载但进程没启动不算成功）
started=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    if "$LAUNCHCTL" print "system/$LABEL" 2>/dev/null | /usr/bin/grep -q "state = running"; then
        started=1
        break
    fi
done

if [ "$started" -eq 1 ]; then
    echo "✅ 安装完成，监控已在后台运行。"
else
    echo "⚠️  服务注册了但没能启动，请把下面的日志发给开发者："
    [ -f "$LOG" ] && /usr/bin/tail -n 20 "$LOG"
    [ -f /var/log/ecosystemguard.out ] && /usr/bin/tail -n 20 /var/log/ecosystemguard.out
    exit 1
fi

echo
echo "---- 启动日志 ----"
[ -f "$LOG" ] && /usr/bin/tail -n 12 "$LOG"
echo "------------------"
