#!/bin/bash
# 给 App 弹窗用的紧凑状态摘要（输出到 stdout，由 AppleScript 显示）
# 注意：这个脚本以当前用户身份运行，不读受保护目录，也不做任何写入。

EG="/usr/local/sbin/ecoguard"
BASE="/Library/Application Support/EcosystemGuard"
STATS="$BASE/kills.log"
CONF="$BASE/config.conf"

state=$(/bin/launchctl print system/com.local.ecosystemguard 2>/dev/null | /usr/bin/awk '/state = /{print $3; exit}')
if [ "$state" = "running" ]; then
    echo "状态：✅ 正在运行"
elif [ -z "$state" ]; then
    echo "状态：⛔️ 已停止（服务未加载）"
else
    echo "状态：⏸ 已加载但未运行（$state）"
fi

total=$(/usr/bin/awk -F'\t' '!/^#/ && NF>=4 {c++} END{print c+0}' "$STATS" 2>/dev/null)
echo "累计清理：${total:-0} 次"

last=$(/usr/bin/awk -F'\t' '!/^#/ && NF>=4 {ts=$1; n=$2; cpu=$4}
    END {if (ts != "") printf "最近一次：%s  %s  CPU %s%%", substr(ts, 12, 8), n, cpu}' "$STATS" 2>/dev/null)
[ -n "$last" ] && echo "$last"

thr=25
[ -f "$CONF" ] && . "$CONF" 2>/dev/null
echo "触发条件：CPU ≥ ${thr}%，连续 3 次"

procs=$(/bin/ps -Ao pcpu=,comm= 2>/dev/null | /usr/bin/awk '
    { c = $2; sub(/.*\//, "", c)
      if (c == "ecosystemd" || c == "ecosystemanalyticsd") { if ($1 + 0 > p[c]) p[c] = $1 + 0 } }
    END { for (k in p) printf "%s\t%.1f\n", k, p[k] }' | /usr/bin/sort)
if [ -n "$procs" ]; then
    echo
    echo "当前占用："
    printf '%s\n' "$procs" | /usr/bin/awk -F'\t' '{ printf "  %-22s %5.1f%%\n", $1, $2 }'
else
    echo
    echo "当前占用：两个进程都未运行"
fi
