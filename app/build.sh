#!/bin/bash
# =============================================================================
#  构建 EcosystemGuard 的两个 App 与 DMG
#
#    EcosystemGuard.app      —— 控制面板（普通 App，双击打开）
#    EcosystemGuardMenu.app  —— 菜单栏常驻，显示累计清理次数
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

PANEL_ID="com.github.keepupwithjason.ecosystemguard"
MENU_ID="com.github.keepupwithjason.ecosystemguard.menubar"

PANEL="$OUT/EcosystemGuard.app"
MENU="$OUT/EcosystemGuardMenu.app"

/bin/rm -rf "$OUT"
/bin/mkdir -p "$OUT"

# ---------------------------------------------------------------- 图标 --------
make_iconset() {
    local iconset="$1"
    local bundle="$2"
    /bin/mkdir -p "$iconset"
    for s in 16 32 128 256 512; do
        /usr/bin/sips -z "$s" "$s" "$HERE/icon.png" --out "$iconset/icon_${s}x${s}.png" >/dev/null
        /usr/bin/sips -z "$((s * 2))" "$((s * 2))" "$HERE/icon.png" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    /usr/bin/iconutil -c icns "$iconset" -o "$bundle/Contents/Resources/applet.icns"
}

echo "==> 1/7 编译控制面板 App"
/usr/bin/osacompile -o "$PANEL" "$HERE/EcosystemGuard.applescript"

echo "==> 2/7 编译状态栏 App（stay-open）"
/usr/bin/osacompile -s -o "$MENU" "$HERE/EcosystemGuardMenu.applescript"

echo "==> 3/7 拷贝资源"
/bin/mkdir -p "$PANEL/Contents/Resources/ui" "$PANEL/Contents/Resources/payload"
/bin/cp "$HERE/resources/summary.sh" "$PANEL/Contents/Resources/ui/summary.sh"

# 控制面板自带安装载荷，未克隆仓库也能一键安装
/bin/cp -R "$ROOT/install.sh" "$ROOT/scripts" "$ROOT/launchd" "$ROOT/config" \
    "$PANEL/Contents/Resources/payload/"

/bin/mkdir -p "$MENU/Contents/Resources/ui"
/bin/cp "$HERE/resources/menubar.sh" "$MENU/Contents/Resources/ui/menubar.sh"
/bin/cp "$HERE/resources/loginitem.plist.template" "$MENU/Contents/Resources/ui/loginitem.plist.template"

echo "==> 4/7 生成图标"
make_iconset "$OUT/AppIcon.iconset" "$PANEL"
/bin/cp "$PANEL/Contents/Resources/applet.icns" "$MENU/Contents/Resources/applet.icns"

echo "==> 5/7 写入 Info.plist"
P="$PANEL/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleName -string "EcosystemGuard" "$P"
/usr/bin/plutil -replace CFBundleDisplayName -string "EcosystemGuard" "$P"
/usr/bin/plutil -replace CFBundleIdentifier -string "$PANEL_ID" "$P"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$P"
/usr/bin/plutil -replace CFBundleVersion -string "$VERSION" "$P"
/usr/bin/plutil -replace LSMinimumSystemVersion -string "12.0" "$P"
/usr/bin/plutil -replace NSHumanReadableCopyright -string "MIT License © 2026 Jason" "$P"

M="$MENU/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleName -string "EcosystemGuardMenu" "$M"
/usr/bin/plutil -replace CFBundleDisplayName -string "EcosystemGuard 状态栏" "$M"
/usr/bin/plutil -replace CFBundleIdentifier -string "$MENU_ID" "$M"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$M"
/usr/bin/plutil -replace CFBundleVersion -string "$VERSION" "$M"
/usr/bin/plutil -replace LSMinimumSystemVersion -string "12.0" "$M"
/usr/bin/plutil -replace NSHumanReadableCopyright -string "MIT License © 2026 Jason" "$M"
# 状态栏 App 不占 Dock、不出现在 Cmd+Tab
/usr/bin/plutil -replace LSUIElement -bool true "$M"

echo "==> 6/7 签名（ad-hoc）"
/usr/bin/codesign --force --deep --sign - "$PANEL" 2>/dev/null
/usr/bin/codesign --force --deep --sign - "$MENU" 2>/dev/null

echo "==> 7/7 打包 DMG"
STAGE="$OUT/dmg"
/bin/mkdir -p "$STAGE"
/bin/cp -R "$PANEL" "$MENU" "$STAGE/"
/bin/ln -s /Applications "$STAGE/Applications"
/bin/cat >"$STAGE/使用说明.txt" <<EOF
EcosystemGuard $VERSION
========================================

两个 App，按需安装：

  EcosystemGuard.app       控制面板（状态、统计、启停、卸载）
  EcosystemGuardMenu.app   菜单栏常驻，显示累计清理次数

推荐步骤：

1. 把 EcosystemGuard.app 拖到右边的「应用程序」
2. 打开它，点「安装」，输入一次开机密码（这一步装的是后台监控服务）
3. 需要菜单栏显示次数：再把 EcosystemGuardMenu.app 拖到「应用程序」并打开
   首次打开会自动加入登录项（写 ~/Library/LaunchAgents），以后开机自动出现
   想关掉就在菜单里取消「开机自启」，关过之后不会再自动加回

监控服务本身已经是开机自启，不依赖任何 App 常驻。

项目主页：https://github.com/KeepUpWithJason/ecosystem-guard
EOF
/usr/bin/hdiutil create -volname "EcosystemGuard" -srcfolder "$STAGE" -ov -format UDZO \
    "$OUT/EcosystemGuard-$VERSION.dmg" >/dev/null

echo
echo "✅ 构建完成"
echo "   面板：$PANEL"
echo "   状态栏：$MENU"
echo "   镜像：$OUT/EcosystemGuard-$VERSION.dmg"
