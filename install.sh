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

echo "4) Generating Matrix key…"
mkdir -p matrix-pnk/dendrite/media
docker run --rm \
  -v "$(pwd)/matrix-pnk/dendrite:/etc/dendrite" \
  matrixdotorg/dendrite-monolith:latest \
    generate-keys \
      --config /etc/dendrite/dendrite.yaml \
      --private-key /etc/dendrite/media/server.key

echo "5) Deploying dashboard…"
sudo cp index.html /var/www/html/index.html

echo "6) Launching PNK services…"
chmod +x scripts/start.sh
./scripts/start.sh

echo "✅ PNK is live at http://localhost/"
