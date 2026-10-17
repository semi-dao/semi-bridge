#!/bin/bash
# copy_litert_dylibs.sh
# flutter_gemma_embeddings 的 build hook 在 macOS 上刻意跳過 companion dylibs
# 的 Native Assets bundling（issue #247），預期由 Podfile post_install 處理。
# 但桌面 Flutter 不走 Podfile，所以手動複製。
#
# 每次 flutter build macos 後執行。

set -e

APP_BUNDLE="<HOME>/Developer/bridge_app/build/macos/Build/Products/Release/bridge_app.app"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
CACHE_DIR="$HOME/Library/Caches/flutter_gemma/native/macos_arm64"

if [ ! -d "$CACHE_DIR" ]; then
  echo "ERROR: flutter_gemma native cache not found at $CACHE_DIR"
  echo "Run 'flutter build macos' first to trigger the download."
  exit 1
fi

if [ ! -d "$FRAMEWORKS_DIR" ]; then
  echo "ERROR: App bundle Frameworks not found at $FRAMEWORKS_DIR"
  echo "Run 'flutter build macos' first."
  exit 1
fi

echo "Copying LiteRT companion dylibs to app bundle..."

# Copy the companion dylibs that LiteRtLm.framework depends on
for dylib in libGemmaModelConstraintProvider.dylib libLiteRtMetalAccelerator.dylib libStreamProxy.dylib; do
  if [ -f "$CACHE_DIR/$dylib" ]; then
    cp "$CACHE_DIR/$dylib" "$FRAMEWORKS_DIR/"
    echo "  ✓ $dylib"
  fi
done

echo "Done. LiteRT embedding model will load correctly."
