#!/bin/bash
# 双击查看最近 40 行监控日志（不需要密码）
clear
if [ -x /usr/local/sbin/ecoguard ]; then
    /usr/local/sbin/ecoguard log 40
else
    echo "还没安装监控，请先双击「安装.command」。"
fi
echo
read -r -p "按回车键关闭窗口..." _
