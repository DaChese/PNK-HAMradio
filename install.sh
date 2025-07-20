#!/usr/bin/env bash
set -euo pipefail

###############################################################################
#  PNK-HAMradio installer
#  - must be run as root (sudo)
#  - idempotent: rerun will update, not re-clone
###############################################################################

REPO="https://github.com/DaChese/PNK-HAMradio.git"
INSTALL_DIR="/opt/PNK-HAMradio"
DEND="${INSTALL_DIR}/matrix-pnk/dendrite"
WWW_INDEX="/var/www/html/index.html"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo ./install.sh"
  exit 1
fi

echo "1) Installing dependencies…"
read -p "Do you want to run 'apt update' and 'apt upgrade -y'? (y/N): " RUN_UPGRADE
if [[ "$RUN_UPGRADE" =~ ^[Yy]$ ]]; then
  apt update
  apt upgrade -y
fi
apt install -y git lighttpd python3-pip curl

echo "Adding Docker's official repository…"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
echo "3) Cloning/updating repo…"
if [ -n "$SUDO_USER" ]; then
  TARGET_HOME=$(eval echo "~$SUDO_USER")
else
  TARGET_HOME="/root"
fi

if [ ! -d "$TARGET_HOME/PNK-HAMradio" ]; then
  git clone https://github.com/DaChese/PNK-HAMradio.git "$TARGET_HOME/PNK-HAMradio"
fi
cd "$TARGET_HOME/PNK-HAMradio"
git pull

echo "3) Enabling & starting system services…"
systemctl enable --now docker lighttpd

echo "4) Cloning/updating PNK-HAMradio into $INSTALL_DIR…"
if [[ -d "$INSTALL_DIR/.git" ]]; then
  cd "$INSTALL_DIR"
  git pull --ff-only origin main
else
  rm -rf "$INSTALL_DIR"
  git clone "$REPO" "$INSTALL_DIR"
fi

echo "5) Generating Dendrite server key (if needed)…"
mkdir -p "$DEND"/media
if [[ ! -f "$DEND/media/server.key" ]]; then
  docker run --rm \
    --entrypoint /usr/bin/dendrite \
    -v "$DEND":/etc/dendrite:rw \
    matrixdotorg/dendrite-monolith:main \
    generate-keys \
      --config    /etc/dendrite/dendrite.yaml \
      --private-key /etc/dendrite/media/server.key
else
  echo "   ✔ server.key already exists—skipping"
fi

echo "6) Backing up & deploying dashboard…"
if [[ -f "$WWW_INDEX" ]]; then
  cp "$WWW_INDEX" "${WWW_INDEX}.bak.$(date +%Y%m%d%H%M)"
  echo "   ✔ backed up existing index.html"
fi
cp "$INSTALL_DIR/index.html" "$WWW_INDEX"

echo "7) Launching PNK services…"
chmod +x "$INSTALL_DIR/scripts/start.sh"
cd "$INSTALL_DIR" && ./scripts/start.sh

echo
echo "======== PNK Deployment Summary ========"
systemctl is-active --quiet docker  && echo "✔ docker running"        || echo "✖ docker not running"
systemctl is-active --quiet lighttpd && echo "✔ lighttpd running"     || echo "✖ lighttpd not running"
docker ps --filter "name=dendrite" --quiet | grep -q . && echo "✔ dendrite container" || echo "✖ dendrite container"


echo
echo "🎉  All done!  Browse your PNK dashboard at http://<your-pi-ip>/"
