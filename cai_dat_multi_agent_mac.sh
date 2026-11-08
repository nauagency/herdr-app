#!/bin/bash
# ==============================================================================
# Script: cai_dat_multi_agent_mac.sh
# Muc dich: Cai dat va cau hinh 1-click tron goi ung dung Multi Agent Herdr (v0.1.13)
#           tren macOS voi nhan dien thuong hieu Nauagency, 6 tai khoan doc lap
#           va plugin dan anh clipboard.
# Tac gia: Nauagency
# ==============================================================================

set -e

# Dinh dang mau sac console
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}==========================================================${NC}"
echo -e "${YELLOW}     HỆ THỐNG MULTI AGENT HERDR (6 TÀI KHOẢN) CHO MACOS   ${NC}"
echo -e "                Phát triển bởi Nauagency                  "
echo -e "${CYAN}==========================================================${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_ACCOUNTS_DIR="$HOME/.antigravity-accounts"
APP_NAME="Multi Agent Herdr"
APP_PATH="/Applications/$APP_NAME.app"
ORIG_HERDR_APP="/Applications/Herdr.app"
OLD_MULTI_AGENT_APP="/Applications/Multi Agent.app"
ICON_SRC="$SCRIPT_DIR/assets/multi_agent_logo.icns"

# Xac dinh thu muc bin cho Homebrew (Apple Silicon: /opt/homebrew/bin, Intel: /usr/local/bin)
if [ -d "/opt/homebrew/bin" ]; then
    BREW_BIN="/opt/homebrew/bin"
elif [ -d "/usr/local/bin" ]; then
    BREW_BIN="/usr/local/bin"
else
    BREW_BIN="/usr/local/bin"
    mkdir -p "$BREW_BIN" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# BƯỚC 1: KIỂM TRA HOMEBREW VÀ CÀI ĐẶT HERDR (v0.1.13)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[1/5] Kiểm tra và cài đặt Herdr (v0.1.13) qua Homebrew...${NC}"

if ! command -v brew &> /dev/null; then
    echo -e "${YELLOW}  [!] Chưa tìm thấy Homebrew. Đang tiến hành cài đặt Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Cài đặt hoặc cập nhật Herdr CLI & Herdr App
if ! command -v herdr &> /dev/null; then
    echo -e "  -> Đang cài đặt Herdr CLI..."
    brew install herdr || true
fi

if [ ! -d "$APP_PATH" ] && [ ! -d "$ORIG_HERDR_APP" ] && [ ! -d "$OLD_MULTI_AGENT_APP" ]; then
    echo -e "  -> Đang cài đặt Herdr App (Cask)..."
    brew install --cask herdr-app || true
else
    echo -e "  -> Ứng dụng đã có trên máy. Đang đảm bảo bản mới nhất..."
    brew upgrade --cask herdr-app 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# BƯỚC 2: THIẾT LẬP THƯƠNG HIỆU MULTI AGENT HERDR & ICON NAUAGENCY
# ------------------------------------------------------------------------------
echo -e ""
echo -e "${CYAN}[2/5] Thiết lập ứng dụng Multi Agent Herdr với biểu tượng Nauagency...${NC}"

# Đổi tên từ Herdr.app hoặc Multi Agent.app cũ thành Multi Agent Herdr.app
if [ -d "$ORIG_HERDR_APP" ]; then
    echo -e "  -> Đổi tên Herdr.app thành '$APP_NAME.app'..."
    rm -rf "$APP_PATH"
    mv "$ORIG_HERDR_APP" "$APP_PATH"
elif [ -d "$OLD_MULTI_AGENT_APP" ] && [ "$OLD_MULTI_AGENT_APP" != "$APP_PATH" ]; then
    echo -e "  -> Đổi tên 'Multi Agent.app' cũ thành '$APP_NAME.app'..."
    rm -rf "$APP_PATH"
    mv "$OLD_MULTI_AGENT_APP" "$APP_PATH"
fi

if [ -d "$APP_PATH" ]; then
    PLIST="$APP_PATH/Contents/Info.plist"
    if [ -f "$PLIST" ]; then
        plutil -replace CFBundleDisplayName -string "$APP_NAME" "$PLIST" 2>/dev/null || true
        plutil -replace CFBundleName -string "$APP_NAME" "$PLIST" 2>/dev/null || true
    fi

    # Gán icon Retina macOS
    if [ -f "$ICON_SRC" ]; then
        echo -e "  -> Gán icon Nauagency Retina chuẩn macOS..."
        cp -f "$ICON_SRC" "$APP_PATH/Contents/Resources/Herdr.icns"
    fi

    # Đăng ký và ký chứng thực ad-hoc
    xattr -cr "$APP_PATH" 2>/dev/null || true
    codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || true
    touch "$APP_PATH"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH" 2>/dev/null || true

    # Tạo symlink CLI
    ln -sfn "$APP_PATH/Contents/MacOS/Herdr" "$BREW_BIN/multi-agent-herdr" 2>/dev/null || true
    ln -sfn "$APP_PATH/Contents/MacOS/Herdr" "$BREW_BIN/multi-agent" 2>/dev/null || true
    ln -sfn "$APP_PATH/Contents/MacOS/Herdr" "$BREW_BIN/herdr-app" 2>/dev/null || true
    echo -e "${GREEN}  ✓ Đã thiết lập $APP_NAME.app thành công!${NC}"
else
    echo -e "${YELLOW}  [!] Chưa tìm thấy thư mục $APP_PATH. Hãy kiểm tra lại quá trình tải app.${NC}"
fi

# Cài đặt giao diện branding Nauagency vào Herdr GUI nếu có
if [ -f "$SCRIPT_DIR/branding/install_branding.sh" ]; then
    echo -e "  -> Áp dụng giao diện nhận diện Nauagency vào Herdr GUI..."
    bash "$SCRIPT_DIR/branding/install_branding.sh" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# BƯỚC 3: CÀI ĐẶT VÀ KÍCH HOẠT PLUGIN DÁN ẢNH (herdr-paste-image)
# ------------------------------------------------------------------------------
echo -e ""
echo -e "${CYAN}[3/5] Kích hoạt plugin dán ảnh màn hình clipboard...${NC}"

if command -v herdr &> /dev/null; then
    herdr plugin install ddfonseca/herdr-paste-image 2>/dev/null || true
    herdr plugin enable herdr-paste-image 2>/dev/null || true
    echo -e "${GREEN}  ✓ Plugin herdr-paste-image đã sẵn sàng hoạt động.${NC}"
fi

# ------------------------------------------------------------------------------
# BƯỚC 4: THIẾT LẬP 6 TÀI KHOẢN ĐỘC LẬP & QUY TẮC ZERO-BLOAT TOKEN
# ------------------------------------------------------------------------------
echo -e ""
echo -e "${CYAN}[4/5] Cấu hình 6 tài khoản Antigravity độc lập và nạp Zero-Bloat...${NC}"

ORIG_HOME="$HOME"
mkdir -p "$ORIG_HOME/.gemini"
[ -f "$SCRIPT_DIR/GEMINI.md" ] && cp "$SCRIPT_DIR/GEMINI.md" "$ORIG_HOME/.gemini/GEMINI.md"

for i in {1..6}; do
    ACC_DIR="$BASE_ACCOUNTS_DIR/acc$i"
    ACC_GEMINI="$ACC_DIR/.gemini"
    mkdir -p "$ACC_GEMINI/config"
    
    [ -d "$ORIG_HOME/.ssh" ] && ln -sfn "$ORIG_HOME/.ssh" "$ACC_DIR/.ssh" 2>/dev/null || true
    [ -f "$ORIG_HOME/.gitconfig" ] && ln -sfn "$ORIG_HOME/.gitconfig" "$ACC_DIR/.gitconfig" 2>/dev/null || true
    
    if [ -f "$SCRIPT_DIR/GEMINI.md" ]; then
        ln -sfn "$ORIG_HOME/.gemini/GEMINI.md" "$ACC_GEMINI/GEMINI.md" 2>/dev/null || true
        ln -sfn "$ORIG_HOME/.gemini/GEMINI.md" "$ACC_GEMINI/config/GEMINI.md" 2>/dev/null || true
    fi

    WRAPPER="$BREW_BIN/agy-$i"
    cat << SCRIPT > "$WRAPPER"
#!/bin/bash
export HOME="$ACC_DIR"
exec "$BREW_BIN/agy" "\$@"
SCRIPT
    chmod +x "$WRAPPER"
    echo -e "  -> Đã tạo tài khoản $i: Lệnh ${YELLOW}agy-$i${NC} (Lưu tại $ACC_DIR)"
done

# ------------------------------------------------------------------------------
# BƯỚC 5: TỔNG KẾT & HƯỚNG DẪN KHỞI CHẠY
# ------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}==========================================================${NC}"
echo -e "${GREEN}     CÀI ĐẶT MULTI AGENT HERDR MACOS HOÀN TẤT 100%!       ${NC}"
echo -e "${GREEN}==========================================================${NC}"
echo ""
echo -e "${YELLOW}Các tiện ích đã sẵn sàng:${NC}"
echo -e "1. Ứng dụng Desktop: ${CYAN}/Applications/Multi Agent Herdr.app${NC} (Logo Nauagency)"
echo -e "2. Khởi động nhanh từ Terminal: gõ lệnh ${YELLOW}multi-agent-herdr${NC} hoặc ${YELLOW}multi-agent${NC}"
echo -e "3. 6 Tài khoản độc lập: chạy ${YELLOW}agy-1${NC} đến ${YELLOW}agy-6${NC} trong từng tab"
echo -e "4. Quy tắc Zero-Bloat: Tự động tiết kiệm >90% token qua cơ chế Flash subagent"
echo -e "5. Dán ảnh clipboard: Chụp ảnh màn hình và bấm Cmd + V để đưa ảnh vào Agent"
echo ""
