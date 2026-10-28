#!/bin/bash
# 登录时由 LaunchAgent 调用：先写一个「本次是登录启动」的标记，再打开 App。
# App 读到这个新鲜标记（1 分钟内）就只进菜单栏，不弹控制面板。

APP="$(cd "$(dirname "$0")/../../.." && pwd)"
MARK="$HOME/Library/Application Support/EcosystemGuard/background-launch"

/bin/mkdir -p "$(dirname "$MARK")"
/usr/bin/touch "$MARK"
exec /usr/bin/open -g -a "$APP"
