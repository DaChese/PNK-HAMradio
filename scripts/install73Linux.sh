#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 73Linux installer (km4ack/73Linux)
# - clones or updates the repo under $HOME/73Linux
# - makes sure 73.sh is executable
# - runs the installer
# -----------------------------------------------------------------------------

REPO="https://github.com/km4ack/73Linux.git"
INSTALL_DIR="$HOME/73Linux"

# If run as root, switch to pi
if [[ $EUID -eq 0 ]]; then
  echo "Detected root – installing as user 'pi'…"
  exec sudo -u pi bash "$0"
fi

echo "→ Installing/updating 73Linux in $INSTALL_DIR…"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  cd "$INSTALL_DIR"
  git pull --ff-only origin main
else
  git clone "$REPO" "$INSTALL_DIR"
fi

echo "→ Making 73.sh executable…"
chmod +x "$INSTALL_DIR/73.sh"

echo "→ Running 73Linux installer…"
bash "$INSTALL_DIR/73.sh"

echo "✅  73Linux install/update complete."
