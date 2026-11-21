#!/usr/bin/env bash
# 构建 CopyT.app（默认 Apple Silicon / arm64）
# 用法: ./scripts/build-app.sh            -> build/CopyT.app (arm64)
#       ARCH=universal ./scripts/build-app.sh -> arm64 + x86_64 通用包
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
ARCH="${ARCH:-arm64}"

if [[ "$ARCH" == "universal" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
else
  ARCH_FLAGS=(--arch "$ARCH")
fi

swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

APP="build/CopyT.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CopyT" "$APP/Contents/MacOS/CopyT"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
# 应用图标：把各尺寸 PNG 打包成 .icns（iconutil 为 macOS 自带）
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# 本地 ad-hoc 签名（无需开发者账号）
codesign --force --deep --sign - "$APP"

echo "✅ 已生成 $APP"
lipo -info "$APP/Contents/MacOS/CopyT" || true
