#!/bin/bash
# =============================================================================
#  构建 EcosystemGuard.app 与 EcosystemGuard-<版本>.dmg
#
#  依赖系统自带工具：osacompile / sips / iconutil / plutil / codesign / hdiutil
#  不需要 Xcode，也不需要额外安装任何东西。
#
#  用法：./app/build.sh
# =============================================================================

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
NAME="EcosystemGuard"
VERSION="1.0.0"
OUT="$HERE/build"
BUNDLE="$OUT/$NAME.app"

/bin/rm -rf "$OUT"
/bin/mkdir -p "$OUT"

echo "==> 1/6 编译 AppleScript"
/usr/bin/osacompile -o "$BUNDLE" "$HERE/$NAME.applescript"

echo "==> 2/6 拷贝资源（安装包 payload + 摘要脚本）"
/bin/mkdir -p "$BUNDLE/Contents/Resources/ui"
/bin/cp "$HERE/resources/summary.sh" "$BUNDLE/Contents/Resources/ui/summary.sh"
/bin/mkdir -p "$BUNDLE/Contents/Resources/payload"
/bin/cp -R "$ROOT/install.sh" "$ROOT/scripts" "$ROOT/launchd" "$ROOT/config" \
    "$BUNDLE/Contents/Resources/payload/"

echo "==> 3/6 生成图标"
ICONSET="$OUT/AppIcon.iconset"
/bin/mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    /usr/bin/sips -z "$s" "$s" "$HERE/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    /usr/bin/sips -z "$((s * 2))" "$((s * 2))" "$HERE/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/applet.icns"

echo "==> 4/6 写入 Info.plist"
P="$BUNDLE/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleName -string "$NAME" "$P"
/usr/bin/plutil -replace CFBundleDisplayName -string "$NAME" "$P"
/usr/bin/plutil -replace CFBundleIdentifier -string "com.github.keepupwithjason.ecosystemguard" "$P"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$P"
/usr/bin/plutil -replace CFBundleVersion -string "$VERSION" "$P"
/usr/bin/plutil -replace LSMinimumSystemVersion -string "12.0" "$P"
/usr/bin/plutil -replace NSHumanReadableCopyright -string "MIT License © 2026 Jason" "$P"

echo "==> 5/6 签名（ad-hoc）"
/usr/bin/codesign --force --deep --sign - "$BUNDLE" 2>/dev/null

echo "==> 6/6 打包 DMG"
STAGE="$OUT/dmg"
/bin/mkdir -p "$STAGE"
/bin/cp -R "$BUNDLE" "$STAGE/"
/bin/ln -s /Applications "$STAGE/Applications"
/bin/cat >"$STAGE/使用说明.txt" <<EOF
EcosystemGuard $VERSION
========================================

1. 把左边的 EcosystemGuard 拖到右边的「应用程序」文件夹
2. 打开它，点「安装」，输入一次开机密码
3. 之后监控会在后台常驻，并随开机自动启动，App 不需要一直开着

看累计清理次数：打开 App，或「更多操作 → 查看完整统计」
详细配置：/Library/Application Support/EcosystemGuard/config.conf

项目主页：https://github.com/KeepUpWithJason/ecosystem-guard
EOF
/usr/bin/hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO \
    "$OUT/$NAME-$VERSION.dmg" >/dev/null

echo
echo "✅ 构建完成"
echo "   应用：$BUNDLE"
echo "   镜像：$OUT/$NAME-$VERSION.dmg"
