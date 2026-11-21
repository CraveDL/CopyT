#!/usr/bin/env bash
# 打包安装包：dist/CopyT-<版本>-<架构>.dmg、.zip 和 SHA256SUMS.txt
# 用法: VERSION=0.1.1 ./scripts/package.sh
set -euo pipefail
cd "$(dirname "$0")/.."

export VERSION="${VERSION:-0.1.1}"
export ARCH="${ARCH:-arm64}"
APP="build/CopyT.app"
NAME="CopyT-${VERSION}-${ARCH}"

./scripts/build-app.sh

rm -rf dist
mkdir -p dist
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/CopyT.app"
ln -s /Applications "$STAGE/Applications"
cp Resources/INSTALL.txt "$STAGE/安装说明.txt"
cp LICENSE "$STAGE/LICENSE.txt"

# hdiutil 偶尔会报 "resource busy"，重试几次
for attempt in 1 2 3; do
  if hdiutil create -volname "CopyT ${VERSION}" -srcfolder "$STAGE" \
       -fs HFS+ -format UDZO -ov "dist/${NAME}.dmg"; then
    break
  fi
  [[ $attempt == 3 ]] && { echo "创建 DMG 失败"; exit 1; }
  sleep 3
done

ditto -c -k --keepParent "$APP" "dist/${NAME}.zip"
(cd dist && shasum -a 256 "${NAME}.dmg" "${NAME}.zip" > SHA256SUMS.txt)

echo "✅ 安装包已生成："
ls -lh dist
