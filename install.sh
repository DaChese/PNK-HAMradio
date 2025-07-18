#!/usr/bin/env bash
set -e

echo "1) Installing dependencies…"
apt update
apt upgrade -y
apt install -y git docker-ce docker-ce-cli containerd.io lighttpd python3-pip curl

echo "2) Starting services…"
systemctl enable --now docker lighttpd

echo "3) Cloning/updating repo…"
if [ ! -d "$HOME/PNK-HAMradio" ]; then
  git clone https://github.com/DaChese/PNK-HAMradio.git "$HOME/PNK-HAMradio"
fi
cd "$HOME/PNK-HAMradio"
git pull


echo "Checking for Dendrite server key…"
DEND=`pwd`/matrix-pnk/dendrite
mkdir -p "$DEND"/media

if [ ! -f "$DEND"/media/server.key ]; then
  echo "   Generating a fresh Matrix server key"
  docker run --rm \
    --entrypoint "/usr/bin/dendrite" \
    -v "$DEND":/etc/dendrite:rw \
    matrixdotorg/dendrite-monolith:main \
    generate-keys \
      --config /etc/dendrite/dendrite.yaml \
      --private-key /etc/dendrite/media/server.key
else
  echo "   Server key already exists, skipping"
fi

echo "5) Deploying dashboard…"
sudo cp index.html /var/www/html/index.html

echo "6) Launching PNK services…"
chmod +x scripts/start.sh
./scripts/start.sh

echo "PNK is live at http://localhost/"

echo "Cloning and installing 73Linux - HamRadio Software…"
if [ -d "$HOME/73Linux/.git" ]; then
  cd "$HOME/73Linux"
  git pull
else
  git clone --depth 1 --single-branch https://github.com/km4ack/73Linux.git "$HOME/73Linux"
fi

if [ -d "$HOME/73Linux" ]; then
  bash "$HOME/73Linux/73.sh"
else
  echo "Error: 73Linux directory does not exist. Install failed."
  exit 1
fi