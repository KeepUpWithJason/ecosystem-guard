#!/bin/bash
# 双击卸载：删除监控与开机自启，并恢复两个 Apple 系统服务
clear
echo "════════════════════════════════════════════"
echo "  卸载 CPU 监控"
echo "════════════════════════════════════════════"
echo

if [ ! -x /usr/local/sbin/ecoguard ]; then
    echo "没有安装过监控，无需卸载。"
else
    read -r -p "确认卸载？输入 y 回车继续：" ans
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
        if OUT=$(/usr/bin/sudo -n /usr/local/sbin/ecoguard uninstall 2>&1); then
            echo "$OUT"
        else
            echo "需要系统密码确认，请在弹出的窗口输入开机密码..."
            OUT=$(/usr/bin/osascript -e 'do shell script "/usr/local/sbin/ecoguard uninstall" with administrator privileges' 2>&1)
            echo "$OUT"
        fi
    else
        echo "已取消。"
    fi
fi

echo
echo "════════════════════════════════════════════"
read -r -p "按回车键关闭窗口..." _
