#!/bin/bash
# ==============================================================================
# Script: agy.sh
# Multi Agent Herdr - Tu dong phan bo moi truong co lap cho Antigravity tren macOS
# ==============================================================================

BASE_DIR="$HOME/.antigravity-accounts"
mkdir -p "$BASE_DIR"

# 1. Kiem tra neu chi la lenh tra cuu thong tin
for arg in "$@"; do
    if [[ "$arg" == "--version" || "$arg" == "-v" || "$arg" == "--help" || "$arg" == "-h" || "$arg" == "help" ]]; then
        exec agy "$@"
    fi
done

# 2. Xac dinh slot tai khoan
ALLOCATED=""
if [[ "$1" == "-a" || "$1" == "--account" ]]; then
    ALLOCATED="$2"
    shift 2
elif [[ -n "$AGY_ACCOUNT" ]]; then
    ALLOCATED="$AGY_ACCOUNT"
fi

if [[ -z "$ALLOCATED" ]]; then
    for i in $(seq 1 50); do
        SLOT_DIR="$BASE_DIR/acc$i"
        PID_FILE="$SLOT_DIR/session.pid"
        if [ ! -d "$SLOT_DIR" ]; then
            ALLOCATED="$i"
            break
        fi
        if [ -f "$PID_FILE" ]; then
            PREV_PID=$(cat "$PID_FILE" 2>/dev/null)
            if kill -0 "$PREV_PID" 2>/dev/null; then
                continue
            fi
        fi
        ALLOCATED="$i"
        break
    done
fi

ALLOCATED="${ALLOCATED:-1}"
SLOT_DIR="$BASE_DIR/acc$ALLOCATED"
mkdir -p "$SLOT_DIR/.gemini"
mkdir -p "$SLOT_DIR/Library/Application Support/Antigravity"

GLOBAL_GEMINI="$HOME/.gemini/GEMINI.md"
if [ -f "$GLOBAL_GEMINI" ]; then
    cp "$GLOBAL_GEMINI" "$SLOT_DIR/GEMINI.md" 2>/dev/null || true
    cp "$GLOBAL_GEMINI" "$SLOT_DIR/.gemini/GEMINI.md" 2>/dev/null || true
fi

echo "$$" > "$SLOT_DIR/session.pid"
trap 'rm -f "$SLOT_DIR/session.pid"' EXIT

export HOME="$SLOT_DIR"

TITLE="Antigravity $ALLOCATED"
printf "\033]0;%s\007" "$TITLE"

# Thu doi ten tab tren Herdr macOS neu co CLI
if command -v herdr-app >/dev/null 2>&1; then
    herdr-app do tab.rename --name "$TITLE" 2>/dev/null || true
fi

echo -e "\033[36m==========================================================\033[0m"
echo -e "\033[33m   MULTI AGENT HERDR - ANTIGRAVITY (TAI KHOAN $ALLOCATED)   \033[0m"
echo -e "\033[90m   Moi truong co lap: acc$ALLOCATED\033[0m"
echo -e "\033[36m==========================================================\033[0m"
echo ""

exec agy "$@"
