#!/usr/bin/env bash
set -euo pipefail

###############################################################################
#  PNK-HAMradio installer for Pi OS 64-bit Bullseye
###############################################################################

REPO="https://github.com/DaChese/PNK-HAMradio.git"
INSTALL_DIR="$HOME/PNK-HAMradio"
DEND="$INSTALL_DIR/matrix-pnk/dendrite"
WWW_INDEX="/var/www/html/index.html"
PI_USER="pi"
DENDRITE_IMAGE="matrixdotorg/dendrite-monolith:main"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

echo "1) Installing system packages…"
apt update
apt install -y git curl lighttpd python3-pip

echo "2) Installing Docker via get.docker.com…"
curl -fsSL https://get.docker.com | sh

echo "3) Enable services & add '$PI_USER' to docker group…"
systemctl enable --now docker lighttpd
usermod -aG docker $PI_USER

echo "4) Clone or update PNK-HAMradio…"
if [[ -d "$INSTALL_DIR/.git" ]]; then
  cd "$INSTALL_DIR"
  git pull --ff-only origin main
else
  rm -rf "$INSTALL_DIR"
  git clone "$REPO" "$INSTALL_DIR"
fi

  echo "   → Fix ownership of PNK data…"
  chown -R "$PI_USER:docker" "$INSTALL_DIR"

  echo "   → Fix permissions for Etherpad & FileBrowser data…"
  # from your project root (where matrix-pnk/ lives):
  chmod -R a+rwX "$INSTALL_DIR/matrix-pnk/etherpad/var"
  chmod -R a+rwX "$INSTALL_DIR/matrix-pnk/filebrowser"


echo "5) Generate Dendrite key if missing…"
mkdir -p "$DEND"/media
if [[ ! -f "$DEND"/media/server.key ]]; then
  docker run --rm \
    --entrypoint /usr/bin/dendrite \
    -v "$DEND":/etc/dendrite:rw \
    "$DENDRITE_IMAGE" \
      generate-keys \
      --config       /etc/dendrite/dendrite.yaml \
      --private-key  /etc/dendrite/media/server.key
else
  echo "   ✔ server.key already exists"
fi

echo "6) Deploy dashboard…"
[[ -f "$WWW_INDEX" ]] && cp "$WWW_INDEX"{,.bak}
cp "$INSTALL_DIR/index.html" "$WWW_INDEX"

echo "7) Start all PNK services…"
chmod +x "$INSTALL_DIR/scripts/start.sh"
cd "$INSTALL_DIR"
./scripts/start.sh

echo
echo "✅  Deployment complete!"
echo "Browse: http://<your-pi-ip>/"
echo "To manage PNK services, use: sudo systemctl start|stop|restart PNK-HAMradio"

