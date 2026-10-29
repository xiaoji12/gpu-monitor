#!/bin/bash
# GPU Monitor 构建脚本
# 用法：./build.sh          仅编译，生成 GPUMonitor.app 到 ~/Applications
#       ./build.sh --install 编译并配置开机自启（LaunchAgent）

set -e

cd "$(dirname "$0")"

APP_NAME="GPUMonitor"
APP="$HOME/Applications/$APP_NAME.app"
BUNDLE_ID="local.xiaoji.gpumonitor"

echo "==> 编译"
swiftc -O main.swift -o "$APP_NAME" -framework Cocoa -framework IOKit

echo "==> 打包 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>GPU Monitor</string>
    <key>CFBundleDisplayName</key><string>GPU 监控</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null || echo "   (ad-hoc 签名跳过，不影响本地运行)"

if [ "$1" = "--install" ]; then
    echo "==> 配置开机自启"
    LA="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$LA" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array><string>$APP/Contents/MacOS/$APP_NAME</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
PLIST
    echo "   已写入 $LA"
fi

echo "==> 启动"
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
sleep 1
open "$APP"

echo
echo "完成。菜单栏右上角应出现 GPU 使用率与温度。"
echo "卸载：pkill -f $APP_NAME.app; rm -rf $APP $HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
