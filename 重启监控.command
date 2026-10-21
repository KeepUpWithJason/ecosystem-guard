#!/bin/bash
# 双击重启监控（改完 config.conf 后使用）
clear
echo "════════════════════════════════════════════"
echo "  重启 CPU 监控"
echo "════════════════════════════════════════════"
echo

if [ ! -x /usr/local/sbin/ecoguard ]; then
    echo "还没安装监控，请先双击「安装.command」。"
elif OUT=$(/usr/bin/sudo -n /usr/local/sbin/ecoguard restart 2>&1); then
    echo "$OUT"
else
    echo "需要系统密码确认，请在弹出的窗口输入开机密码..."
    OUT=$(/usr/bin/osascript -e 'do shell script "/usr/local/sbin/ecoguard restart" with administrator privileges' 2>&1)
    echo "$OUT"
fi

echo
echo "════════════════════════════════════════════"
read -r -p "按回车键关闭窗口..." _
