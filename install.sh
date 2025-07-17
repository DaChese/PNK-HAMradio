#!/usr/bin/env bash
set -e

echo "1) Installing dependencies…"
sudo apt update
sudo apt install -y git docker.io docker-compose-plugin lighttpd

echo "2) Starting services…"
sudo systemctl enable --now docker lighttpd

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
  echo "  🔑 Generating a fresh Matrix server key"
  docker run --rm \
    --entrypoint "/usr/bin/dendrite" \
    -v "$DEND":/etc/dendrite:rw \
    matrixdotorg/dendrite-monolith:latest \
    generate-keys \
      --config /etc/dendrite/dendrite.yaml \
      --private-key /etc/dendrite/media/server.key
else
  echo "  🔑 Server key already exists, skipping"
fi

echo "5) Deploying dashboard…"
sudo cp index.html /var/www/html/index.html

echo "6) Launching PNK services…"
chmod +x scripts/start.sh
./scripts/start.sh

echo "✅ PNK is live at http://localhost/"

echo "Ensure 73Linux - HamRadio Software is installed"
if [ ! -d /opt/73Linux ]; then
  echo "Cloning and installing ham-radio stack…"
  git clone https://github.com/km4ack/73Linux.git /opt/73Linux
  cd /opt/73Linux
  sudo bash 73.sh
fi
