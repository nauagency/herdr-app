#!/bin/bash
set -e

echo "Setting up agy-1 to agy-6..."
ORIG_HOME="$HOME"

for i in {1..6}; do
  ACC_DIR="$ORIG_HOME/.antigravity-accounts/acc$i"
  mkdir -p "$ACC_DIR"
  [ -d "$ORIG_HOME/.ssh" ] && ln -sfn "$ORIG_HOME/.ssh" "$ACC_DIR/.ssh"
  [ -f "$ORIG_HOME/.gitconfig" ] && ln -sfn "$ORIG_HOME/.gitconfig" "$ACC_DIR/.gitconfig"
  
  WRAPPER="/opt/homebrew/bin/agy-$i"
  cat << SCRIPT > "$WRAPPER"
#!/bin/bash
export HOME="$ACC_DIR"
exec /opt/homebrew/bin/agy "\$@"
SCRIPT
  chmod +x "$WRAPPER"
  echo "Created command: agy-$i"
done

echo "Done! You can run agy-1 through agy-6."
