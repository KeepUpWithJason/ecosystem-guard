#!/bin/bash
# =============================================================================
#  构建 EcosystemGuard.app 与 EcosystemGuard-<版本>.dmg
#
#  单一 App，两种用法：
#    双击打开  -> 控制面板（今日/累计、统计、日志、启停、卸载）
#    开机自启  -> 只进菜单栏，显示「E · N次」今日清理次数
#
#  依赖系统自带工具：osacompile / sips / iconutil / plutil / codesign / hdiutil
#  不需要 Xcode，也不需要额外安装任何东西。
#
#  用法：./app/build.sh
# =============================================================================

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
VERSION="1.0.0"
OUT="$HERE/build"
BUNDLE_ID="com.github.keepupwithjason.ecosystemguard"
APP="$OUT/EcosystemGuard.app"

/bin/rm -rf "$OUT"
/bin/mkdir -p "$OUT"

echo "==> 1/6 编译 App（stay-open，菜单栏 + 面板二合一）"
/usr/bin/osacompile -s -o "$APP" "$HERE/EcosystemGuard.applescript"

echo "==> 2/6 拷贝资源"
/bin/mkdir -p "$APP/Contents/Resources/ui" "$APP/Contents/Resources/payload"
/bin/cp "$HERE/resources/summary.sh" "$APP/Contents/Resources/ui/summary.sh"
/bin/cp "$HERE/resources/menubar.sh" "$APP/Contents/Resources/ui/menubar.sh"
/bin/cp "$HERE/resources/loginitem.plist.template" "$APP/Contents/Resources/ui/loginitem.plist.template"
/bin/cp "$HERE/resources/login-launch.sh" "$APP/Contents/Resources/ui/login-launch.sh"
/bin/chmod 755 "$APP/Contents/Resources/ui/"*.sh

# 自带安装载荷，未克隆仓库也能一键安装监控服务
/bin/cp -R "$ROOT/install.sh" "$ROOT/scripts" "$ROOT/launchd" "$ROOT/config" \
    "$APP/Contents/Resources/payload/"

echo "==> 3/6 生成图标"
ICONSET="$OUT/AppIcon.iconset"
/bin/mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    /usr/bin/sips -z "$s" "$s" "$HERE/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    /usr/bin/sips -z "$((s * 2))" "$((s * 2))" "$HERE/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/applet.icns"

echo "==> 4/6 写入 Info.plist"
P="$APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleName -string "EcosystemGuard" "$P"
/usr/bin/plutil -replace CFBundleDisplayName -string "EcosystemGuard" "$P"
/usr/bin/plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$P"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$P"
/usr/bin/plutil -replace CFBundleVersion -string "$VERSION" "$P"
/usr/bin/plutil -replace LSMinimumSystemVersion -string "12.0" "$P"
/usr/bin/plutil -replace NSHumanReadableCopyright -string "MIT License © 2026 Jason" "$P"
# 常驻菜单栏，不占 Dock、不进 Cmd+Tab
/usr/bin/plutil -replace LSUIElement -bool true "$P"

echo "==> 5/6 签名（ad-hoc）"
/usr/bin/codesign --force --deep --sign - "$APP" 2>/dev/null

echo "==> 6/6 打包 DMG"
STAGE="$OUT/dmg"
/bin/mkdir -p "$STAGE"
/bin/cp -R "$APP" "$STAGE/"
/bin/ln -s /Applications "$STAGE/Applications"
/bin/cat >"$STAGE/使用说明.txt" <<EOF
EcosystemGuard $VERSION
========================================

一个 App，两种用法：

  双击打开      -> 控制面板：今日/累计清理次数、统计、日志、启停、卸载
  开机自启      -> 只住在菜单栏，显示「E · N次」今日清理次数

安装步骤：

1. 把 EcosystemGuard.app 拖到右边的「应用程序」
2. 打开它，点「安装」，输入一次开机密码
   （这一步装的是后台监控服务，之后它自己随开机启动，不需要 App 常驻）
3. 首次打开会自动加入登录项，以后开机菜单栏就有 E · N次
   想关掉：点菜单栏图标 -> 取消「开机自启」

菜单栏菜单：今日清理次数 / 打开控制面板 / 停止或启动监控 / 开机自启 / 退出

项目主页：https://github.com/KeepUpWithJason/ecosystem-guard
EOF
/usr/bin/hdiutil create -volname "EcosystemGuard" -srcfolder "$STAGE" -ov -format UDZO \
    "$OUT/EcosystemGuard-$VERSION.dmg" >/dev/null

echo
echo "✅ 构建完成"
echo "   应用：$APP"
echo "   镜像：$OUT/EcosystemGuard-$VERSION.dmg"
