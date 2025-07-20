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

echo "1) Installing OS packages…"
apt update
apt install -y \
    git \
    curl \
    ca-certificates \
    gnupg \
    lsb-release \
    lighttpd \
    python3-pip

echo "2) Installing Docker & docker-compose plugin…"
# add Docker’s signing key & repo
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

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
# …you can add checks for each service container here…

echo
echo "🎉  All done!  Browse your PNK dashboard at http://<your-pi-ip>/"

