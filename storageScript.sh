#!/usr/bin/env bash
set -e

# 1) Prompt for data directory
echo
echo "Where should the PNK store its data?"
echo "  [1] Local Pi storage (default): $HOME/pnk-data"
echo "  [2] External volume: specify a mount path (e.g. /mnt/usb/pnk-data)"
read -p "Enter 1 or 2: " choice

if [[ "$choice" == "2" ]]; then
  read -e -p "Enter mount point: " DATA_DIR
else
  DATA_DIR="$HOME/pnk-data"
fi

echo "Using data directory: $DATA_DIR"

# 2) Create data subfolders
mkdir -p "$DATA_DIR"/{dendrite/media,pnk-files,kolibri-content,unifi-data}

# 3) Copy dashboard into web root
sudo cp index.html /var/www/html/index.html

# 4) Generate Matrix server key
docker run --rm \
  -v "$DATA_DIR/dendrite":/etc/dendrite \
  matrixdotorg/dendrite-monolith:latest \
  generate-keys \
    --config /etc/dendrite/dendrite.yaml \
    --private-key /etc/dendrite/media/server.key

# 5) Launch all PNK services
chmod +x scripts/start.sh
./scripts/start.sh

echo "✅  PNK installed and running!"