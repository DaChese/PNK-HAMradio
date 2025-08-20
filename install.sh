#!/usr/bin/env bash
set -euo pipefail

###############################################################################
#  PNK-HAMradio installer/updater (Pi OS 64-bit)
#  - Keeps Docker stack for Etherpad/FileBrowser/Kolibri/UniFi
#  - Installs HackChat bare-metal with systemd
#  - Proxies HackChat WS via Lighttpd at /chat-ws
#  - Patches dashboard links + status panel (once, safely)
###############################################################################

REPO="https://github.com/DaChese/PNK-HAMradio.git"
INSTALL_DIR="${INSTALL_DIR:-/home/pi/PNK-HAMradio}"
WWW_INDEX="/var/www/html/index.html"
HC_DIR="/opt/hackchat"
HC_PORT="6060"
SYSTEMD_HC="hackchat"
PI_USER="${PI_USER:-${SUDO_USER:-pi}}"

need_root() { [[ $EUID -eq 0 ]] || { echo "Please run as root: sudo $0"; exit 1; }; }
msg() { echo -e "\n==> $*\n"; }

need_root

msg "1) Installing system packages…"
apt update
apt install -y git curl lighttpd python3-pip

if ! command -v node >/dev/null 2>&1; then
  msg "Installing Node.js 20 LTS…"
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
fi

msg "2) Installing Docker (for existing PNK services)…"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

msg "3) Enable services & add '${PI_USER}' to docker group…"
systemctl enable --now docker lighttpd
id -u "$PI_USER" >/dev/null 2>&1 || useradd -m "$PI_USER"
usermod -aG docker "$PI_USER"

msg "4) Clone or update PNK-HAMradio repo…"
if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" pull --ff-only origin main
else
  rm -rf "$INSTALL_DIR"
  sudo -u "$PI_USER" git clone "$REPO" "$INSTALL_DIR"
fi

echo "   → Fix ownership of PNK data…"
chown -R "$PI_USER:docker" "$INSTALL_DIR"

echo "   → Fix permissions for Etherpad & FileBrowser data…"
chmod -R a+rwX "$INSTALL_DIR/matrix-pnk/etherpad/var" || true
chmod -R a+rwX "$INSTALL_DIR/matrix-pnk/filebrowser" || true

msg "5) Deploy/patch dashboard…"
if [[ -f "$WWW_INDEX" && ! -f "${WWW_INDEX}.bak" ]]; then
  cp "$WWW_INDEX" "${WWW_INDEX}.bak"
fi
# Use repo index if present; else keep existing
if [[ -f "$INSTALL_DIR/index.html" ]]; then
  cp "$INSTALL_DIR/index.html" "$WWW_INDEX"
fi

# Append PNK patch once (adds status panel + corrected links)
if ! grep -q "PNK PATCH: Status panel" "$WWW_INDEX"; then
  awk -v add='
<!-- ===== PNK PATCH: Status panel + improved HackChat link ===== -->
<section class="goals" style="margin:2rem 0">
  <h2>🩺 Service Status</h2>
  <div id="svc-status" class="goals-list">
    <div><span id="st-etherpad">⏳</span><div>Etherpad</div></div>
    <div><span id="st-filebrowser">⏳</span><div>FileBrowser</div></div>
    <div><span id="st-kolibri">⏳</span><div>Kolibri</div></div>
    <div><span id="st-unifi">⏳</span><div>UniFi UI</div></div>
    <div><span id="st-hackchat">⏳</span><div>HackChat WS</div></div>
    <div><span id="st-logs">⏳</span><div>Logs API</div></div>
  </div>
</section>
<script>
(function(){
  const host = location.hostname;
  const http = location.protocol;
  const isTLS = (http === "https:");
  const wsProto = isTLS ? "wss" : "ws";

  // Using Lighttpd proxy at /chat-ws (set below)
  const HC_WS = `${wsProto}://${host}/chat-ws`;

  // Rewrite tiles (open in new tab)
  const links = {
    svc1_link: `${http}//${host}:9001`,        // Etherpad
    svc2_link: `${http)//${host}:8081`,        // FileBrowser
    svc3_link: `${http}//${host}:8082`,        // Kolibri
    svc4_link: `https://${host}:8443`,         // UniFi UI (UI is 8443, not 8080)
    svc5_link: `https://hack.chat/?pnk&ws=${encodeURIComponent(HC_WS)}`
  };
  Object.entries(links).forEach(([key, href]) => {
    const el = document.querySelector(`a[data-key="${key}"]`);
    if (el) { el.href = href; el.target = "_blank"; el.rel = "noopener"; }
  });

  // Status checks
  const endpoints = {
    etherpad:  `${http}//${host}:9001/`,
    filebrowser:`${http}//${host}:8081/`,
    kolibri:   `${http)//${host}:8082/`,
    unifi:     `https://${host}:8443/`,
    logs:      `${http}//${host}/logs/hackchat-websocket?lines=1`
  };
  const mark = (id, ok) => { const el = document.getElementById(id); if (el) el.textContent = ok ? "✅" : "❌"; };
  const ping = (url, id) => fetch(url, { method:"GET", mode:"no-cors" })
      .then(()=>mark(id,true)).catch(()=>mark(id,false));
  const pingImg = (url, id) => { const img=new Image(); img.onload=()=>mark(id,true); img.onerror=()=>mark(id,false); img.src=url; };

  ping(endpoints.etherpad, "st-etherpad");
  ping(endpoints.filebrowser, "st-filebrowser");
  ping(endpoints.kolibri, "st-kolibri");
  fetch(endpoints.unifi, { mode:"no-cors" }).then(()=>mark("st-unifi",true)).catch(()=>pingImg(endpoints.unifi,"st-unifi"));
  fetch(endpoints.logs).then(r=>mark("st-logs",r.ok)).catch(()=>mark("st-logs",false));

  try {
    const ws = new WebSocket(HC_WS);
    const t = setTimeout(()=>{ try{ws.close()}catch(e){}; mark("st-hackchat", false); }, 3000);
    ws.onopen = ()=>{ clearTimeout(t); mark("st-hackchat", true); ws.close(); };
    ws.onerror = ()=>{ clearTimeout(t); mark("st-hackchat", false); };
  } catch { mark("st-hackchat", false); }
})();
</script>
<!-- ===== /PNK PATCH ===== -->
' '
  BEGIN{done=0}
  /<\/body>/ && !done { gsub(/<\/body>/, add "\n</body>"); done=1 }
  { print }
' "$WWW_INDEX" > /tmp/index.html.patched
  mv /tmp/index.html.patched "$WWW_INDEX"
fi

msg "6) Install/Update HackChat (bare-metal)…"
mkdir -p "$HC_DIR"
if [[ ! -d "$HC_DIR/.git" ]]; then
  git clone https://github.com/hack-chat/main.git "$HC_DIR"
fi
git -C "$HC_DIR" fetch --all
git -C "$HC_DIR" reset --hard origin/master
# install deps (omit dev)
if ! npm -C "$HC_DIR" ci --omit=dev; then
  npm -C "$HC_DIR" install --omit=dev
fi

# Basic server config
cat > "$HC_DIR/.hcserver.json" <<JSON
{
  "host": "0.0.0.0",
  "port": ${HC_PORT},
  "msgRateLimit": 2,
  "msgRateWindow": 1000,
  "maxMessageLength": 2048
}
JSON

# Systemd unit
cat > /etc/systemd/system/${SYSTEMD_HC}.service <<UNIT
[Unit]
Description=HackChat WebSocket Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${HC_DIR}
User=${PI_USER}
Group=${PI_USER}
Environment=NODE_ENV=production
ExecStart=/usr/bin/node ${HC_DIR}/main.mjs
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

chown -R "${PI_USER}:${PI_USER}" "$HC_DIR"
systemctl daemon-reload
systemctl enable --now "${SYSTEMD_HC}.service"

msg "7) Lighttpd: enable WebSocket + proxy to HackChat…"
# Enable modules (idempotent)
lighttpd-enable-mod proxy >/dev/null 2>&1 || true
lighttpd-enable-mod wstunnel >/dev/null 2>&1 || true

# Proxy config file
CONF_AVAIL="/etc/lighttpd/conf-available/99-pnk-proxy.conf"
cat > "$CONF_AVAIL" <<'CONF'
# PNK: proxy endpoints
# WebSocket tunnel to HackChat
$HTTP["url"] =~ "^/chat-ws" {
  wstunnel.server = ( "" => ( ( "host" => "127.0.0.1", "port" => 6060 ) ) )
}

# (Optional) Logs API if installed at 127.0.0.1:6061
$HTTP["url"] =~ "^/logs/" {
  proxy.server = ( "" => ( ( "host" => "127.0.0.1", "port" => 6061 ) ) )
}
CONF

ln -sf "$CONF_AVAIL" "/etc/lighttpd/conf-enabled/99-pnk-proxy.conf"
lighttpd -tt -f /etc/lighttpd/lighttpd.conf
systemctl reload lighttpd

msg "8) Start/Update Docker-based PNK services…"
chmod +x "$INSTALL_DIR/scripts/start.sh" || true
su - "$PI_USER" -c "cd '$INSTALL_DIR' && ./scripts/start.sh" || true

msg "✅ Deployment complete!"
echo "Browse Dashboard:   http://<pi-ip>/"
echo "HackChat WS via:    ws(s)://<pi-host>/chat-ws  (proxied by Lighttpd)"
echo "HackChat service:   systemctl status ${SYSTEMD_HC}"
echo "Logs API (optional): proxied at /logs/ if you install it later"
