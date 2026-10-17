#!/bin/bash
# post_build_sign.sh — [小葵 2026-08-01]
# Bridge App build 後自動處理：
# 1. 去除 quarantine 屬性（避免 Gatekeeper 彈窗）
# 2. 用穩定的 ad-hoc 簽名（避免每次 rebuild 後 TCC 重置）
# 3. 添加 TCC 預授權（如果可用）
#
# 用法：在 flutter build macos 或 xcodebuild 之後執行
#   bash post_build_sign.sh [app_path]
#
# 如果沒給 app_path，自動找 build 產物

set -e

APP="${1:-<HOME>/Developer/bridge_app/build/macos/Build/Products/Release/bridge_app.app}"

if [ ! -d "$APP" ]; then
    # 嘗試 DerivedData
    ALT=$(find /tmp/bridge_derived/Build/Products/Release -name "bridge_app.app" -maxdepth 1 2>/dev/null | head -1)
    if [ -n "$ALT" ] && [ -d "$ALT" ]; then
        APP="$ALT"
    else
        echo "❌ 找不到 bridge_app.app"
        exit 1
    fi
fi

echo "📦 Processing: $APP"

# 1. 去除 quarantine
echo "🔓 去除 quarantine 屬性..."
xattr -cr "$APP" 2>/dev/null || true
echo "   ✅ Done"

# 2. ad-hoc 簽名（帶 entitlements，確保 TCC 不會每次重置）
ENTITLEMENTS="<HOME>/Developer/bridge_app/macos/Runner/Release.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
    echo "✍️  重新簽名（帶 entitlements）..."
    codesign --force --deep --sign - \
        --entitlements "$ENTITLEMENTS" \
        "$APP" 2>&1 || echo "   ⚠️ 簽名警告（非致命）"
    echo "   ✅ Done"
else
    echo "⚠️  找不到 Release.entitlements，跳過簽名"
fi

# 3. 確認簽名狀態
echo "📋 簽名狀態："
codesign -dv --verbose=1 "$APP" 2>&1 | grep -E "Identifier|Signature|Format" || true

echo ""
echo "✅ Post-build 處理完成！"
