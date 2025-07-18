#!/usr/bin/env bash
set -eu

if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (using sudo)."
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
echo "5) Deploying dashboard…"
if [ -f /var/www/html/index.html ]; then
  cp /var/www/html/index.html /var/www/html/index.html.bak
  echo "   Existing dashboard backed up to /var/www/html/index.html.bak"
fi
cp index.html /var/www/html/index.html
else
  echo "   Server key already exists, skipping"
fi
echo "6) Launching PNK services…"
if [ -f scripts/start.sh ]; then
  chmod +x scripts/start.sh
  ./scripts/start.sh
else
  echo "Error: scripts/start.sh not found. Skipping PNK service launch."
fi

echo "6) Launching PNK services…"
echo ""
echo "===== Deployment Summary ====="
echo "Services started:"
systemctl is-active --quiet docker && echo " - Docker: running" || echo " - Docker: ERROR"
systemctl is-active --quiet lighttpd && echo " - Lighttpd: running" || echo " - Lighttpd: ERROR"
if [ -f scripts/start.sh ]; then
  echo " - PNK services: launched"
else
  echo " - PNK services: NOT launched (scripts/start.sh missing)"
fi
if [ -f "$DEND/media/server.key" ]; then
  echo " - Matrix Dendrite server key: present"
else
  echo " - Matrix Dendrite server key: ERROR (missing)"
fi
if [ -d "$HOME/73Linux" ]; then
  echo " - 73Linux: installed"
else
  echo " - 73Linux: NOT installed"
fi
echo ""
echo "PNK is live at http://localhost/"
echo "Check above for any errors."
./scripts/start.sh

echo "PNK is live at http://localhost/"

echo "7) Installing 73Linux…"
read -p "Do you want to install 73Linux? (y/N): " INSTALL_73LINUX
if [[ "$INSTALL_73LINUX" =~ ^[Yy]$ ]]; then
  if [ ! -d "$HOME/73Linux" ]; then 
echo "Install HamRadio Software from  git clone https://github.com/km4ack/73Linux.git $HOME/73Linux && bash $HOME/73Linux/73.sh"
else
    echo "Skipping 73Linux installation"
  fi

echo "Installation complete!"
echo "You can now access PNK at http://localhost/"