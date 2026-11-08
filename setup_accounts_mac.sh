#!/bin/bash
set -e

echo "Setting up agy-1 to agy-6 with Zero-Bloat Rule..."
ORIG_HOME="$HOME"
mkdir -p "$ORIG_HOME/.gemini"
[ -f "GEMINI.md" ] && cp "GEMINI.md" "$ORIG_HOME/.gemini/GEMINI.md"

for i in {1..6}; do
  ACC_DIR="$ORIG_HOME/.antigravity-accounts/acc$i"
  ACC_GEMINI="$ACC_DIR/.gemini"
  mkdir -p "$ACC_GEMINI/config"
  
  [ -d "$ORIG_HOME/.ssh" ] && ln -sfn "$ORIG_HOME/.ssh" "$ACC_DIR/.ssh"
  [ -f "$ORIG_HOME/.gitconfig" ] && ln -sfn "$ORIG_HOME/.gitconfig" "$ACC_DIR/.gitconfig"
  [ -f "$ORIG_HOME/.gemini/GEMINI.md" ] && ln -sfn "$ORIG_HOME/.gemini/GEMINI.md" "$ACC_GEMINI/GEMINI.md"
  [ -f "$ORIG_HOME/.gemini/GEMINI.md" ] && ln -sfn "$ORIG_HOME/.gemini/GEMINI.md" "$ACC_GEMINI/config/GEMINI.md"

  WRAPPER="/opt/homebrew/bin/agy-$i"
  cat << SCRIPT > "$WRAPPER"
#!/bin/bash
export HOME="$ACC_DIR"
exec /opt/homebrew/bin/agy "\$@"
SCRIPT
  chmod +x "$WRAPPER"
  echo "Created command: agy-$i (with Zero-Bloat token rule)"
done

echo "Done! All 6 accounts now share the Zero-Bloat Token Saver rule."


