#!/bin/bash
# 供状态栏 App 每次刷新时调用，输出三行：
#   1) 今日清理次数（每天零点自然归零，历史累计不丢）
#   2) 监控状态：running / stopped
#   3) 菜单栏自启：1 / 0

STATS="/Library/Application Support/EcosystemGuard/kills.log"
AGENT_PLIST="$HOME/Library/LaunchAgents/com.github.keepupwithjason.ecosystemguard.menubar.plist"
TODAY="$(/bin/date '+%Y-%m-%d')"

/usr/bin/awk -F'\t' -v d="$TODAY" '!/^#/ && NF>=4 && substr($1,1,10)==d {c++} END{print c+0}' "$STATS" 2>/dev/null || echo 0

if /bin/launchctl print system/com.local.ecosystemguard >/dev/null 2>&1; then
    echo running
else
    echo stopped
fi

if [ -f "$AGENT_PLIST" ]; then
    echo 1
else
    echo 0
fi
