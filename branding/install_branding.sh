#!/bin/bash
# ==============================================================================
# Script: install_branding.sh
# Mục đích: Đồng bộ giao diện thương hiệu Multi Agent cho Herdr trên macOS.
#           GIỮ NGUYÊN 100% CHỨC NĂNG VÀ MÀU SẮC GỐC CỦA HERDR.
#           CHỈ THAY ĐỔI DUY NHẤT: LOGO VÀ TÊN Ở GÓC TRÁI.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERDR_SOURCE="$SCRIPT_DIR/herdr-app"
CONFIG_DIR="$HOME/.config/herdr-app"

echo "=========================================================="
echo "   CAI DAT GIAO DIEN MULTI AGENT CHO HERDR TREN MACOS     "
echo "=========================================================="

if [ ! -d "$HERDR_SOURCE" ]; then
    echo "Khong tim thay thu muc nguon: $HERDR_SOURCE"
    exit 1
fi

LAYOUTS_DIR="$CONFIG_DIR/layouts"
MODS_DIR="$CONFIG_DIR/mods"
BACKUPS_DIR="$CONFIG_DIR/backups"

mkdir -p "$LAYOUTS_DIR" "$MODS_DIR" "$BACKUPS_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
CURRENT_BACKUP="$BACKUPS_DIR/branding_$TIMESTAMP"
HAS_BACKUP=false

for ITEM in "$LAYOUTS_DIR/nauagency.json" "$MODS_DIR/nauagency-brand" "$CONFIG_DIR/shared.json"; do
    if [ -e "$ITEM" ]; then
        if [ "$HAS_BACKUP" = false ]; then
            mkdir -p "$CURRENT_BACKUP/layouts" "$CURRENT_BACKUP/mods"
            HAS_BACKUP=true
        fi
        cp -R "$ITEM" "$CURRENT_BACKUP/" 2>/dev/null || true
    fi
done

echo "[+] Dang sao chep mod nauagency-brand va layout nauagency.json..."
cp -R "$HERDR_SOURCE/mods/nauagency-brand" "$MODS_DIR/"
cp "$HERDR_SOURCE/layouts/nauagency.json" "$LAYOUTS_DIR/nauagency.json"

# Thiết lập layout nauagency làm mặc định
SHARED_JSON="$CONFIG_DIR/shared.json"
if [ -f "$SHARED_JSON" ]; then
    node -e "
    const fs = require('fs');
    try {
        let d = JSON.parse(fs.readFileSync('$SHARED_JSON', 'utf8'));
        d.layout = 'nauagency';
        fs.writeFileSync('$SHARED_JSON', JSON.stringify(d));
    } catch(e) {}
    " 2>/dev/null || echo '{"layout":"nauagency"}' > "$SHARED_JSON"
else
    echo '{"layout":"nauagency"}' > "$SHARED_JSON"
fi

echo "[+] Da dat layout 'nauagency' lam mac dinh trong shared.json"

if pgrep -x "herdr-app" > /dev/null 2>&1; then
    herdr-app do layout.switch --name nauagency 2>/dev/null || true
fi

echo "=========================================================="
echo "   DA CAI DAT HOAN TAT BRANDING MULTI AGENT TREN MACOS!   "
echo "=========================================================="
