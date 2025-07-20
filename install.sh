#!/usr/bin/env bash
set -euo pipefail

###############################################################################
#  PNK-HAMradio installer for Pi OS 64-bit Bullseye
###############################################################################

REPO="https://github.com/DaChese/PNK-HAMradio.git"
INSTALL_DIR="/opt/pnk-hamradio"
DEND="$INSTALL_DIR/matrix-pnk/dendrite"
WWW_INDEX="/var/www/html/index.html"
PI_USER="pi"
DENDRITE_IMAGE="matrixdotorg/dendrite-monolith:v0.14.1"

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


###############################################################################
# 8) Install SDRTrunk (DSheirer/sdrtrunk)
###############################################################################

echo
echo "8) Installing SDRTrunk signal decoder…"

# 8.1 Ensure Java & Maven are present
apt update
apt install -y openjdk-11-jdk maven

# 8.2 Clone or pull the repo
SDR_DIR="/opt/sdrtrunk"
if [[ -d "$SDR_DIR/.git" ]]; then
  echo "   → Updating existing SDRTrunk…"
  cd "$SDR_DIR"
  git pull --ff-only origin main
else
  echo "   → Cloning SDRTrunk into $SDR_DIR…"
  rm -rf "$SDR_DIR"
  git clone https://github.com/DSheirer/sdrtrunk.git "$SDR_DIR"
fi

# 8.3 Build with Maven (skip tests for speed)
echo "   → Building SDRTrunk (this may take a few minutes)…"
cd "$SDR_DIR"
mvn clean package -DskipTests

# 8.4 (Optional) Install systemd service so SDRTrunk auto-starts
SERVICE_FILE="/etc/systemd/system/sdrtrunk.service"
if [[ ! -f "$SERVICE_FILE" ]]; then
  cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=SDRTrunk wideband trunking decoder
After=network.target

[Service]
User=pi
WorkingDirectory=$SDR_DIR
ExecStart=/usr/bin/java -jar $SDR_DIR/target/sdrtrunk.jar
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  echo "   → Enabling SDRTrunk systemd service…"
  systemctl daemon-reload
  systemctl enable sdrtrunk.service
  systemctl start  sdrtrunk.service
fi

echo "   ✔ SDRTrunk installed and running"


echo
echo "✅  Deployment complete!"
echo "Browse: http://<your-pi-ip>/"
echo "To manage PNK services, use: sudo systemctl start|stop|restart pnk-hamradio"

