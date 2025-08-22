#!/usr/bin/env bash
set -euo pipefail

###############################################################################
#  PNK-HAMradio installer/updater (Pi OS 64-bit / Debian Bookworm)
#  - Docker stack (Etherpad/FileBrowser/Kolibri/UniFi)
#  - HackChat bare-metal + Lighttpd /chat-ws proxy
#  - Dashboard patch (status panel + fixed links)
#  - Optional: --logs-api (adds /status + /logs/* via Lighttpd)
#  - Optional: --sdrpp (SDR++ server, built as non-root) + systemd
#  - Optional: --openwebrx (browser SDR waterfall) proxied at /radio
#  - Flags: --patch-dashboard-only (HTML only), --no-docker (skip Docker)
###############################################################################

REPO="https://github.com/DaChese/PNK-HAMradio.git"
INSTALL_DIR="${INSTALL_DIR:-/home/pi/PNK-HAMradio}"
WWW_INDEX="/var/www/html/index.html"

# HackChat
HC_DIR="/opt/hackchat"
HC_PORT="6060"
HC_UNIT="hackchat"

# Logs API (optional)
LOGSAPI_DIR="/opt/pnk-logs-api"
LOGSAPI_PORT="6061"
LOGSAPI_UNIT="pnk-logs-api"

# SDR++ (optional)
SDRPP_UNIT="sdrpp-server"
SDRPP_PORT="5259"

# OpenWebRX (optional)
OPENWEBRX_UNIT=""
OPENWEBRX_PORT="8073"

PI_USER="${PI_USER:-${SUDO_USER:-pi}}"

ACTION=""
WITH_LOGS_API="false"
WITH_SDRPP="false"
WITH_OPENWEBRX="false"
PATCH_DASH_ONLY="false"
SKIP_DOCKER="false"

usage() {
  cat <<USAGE
Usage:
  sudo $0 --install [--logs-api] [--sdrpp] [--openwebrx] [--no-docker] [--patch-dashboard-only]
  sudo $0 --update  [--logs-api] [--sdrpp] [--openwebrx] [--no-docker] [--patch-dashboard-only]
  sudo $0 --uninstall

Flags:
  --logs-api              Install/refresh the PNK Logs API (status + logs + live tail)
  --sdrpp                 Install SDR++ server mode (headless) on port ${SDRPP_PORT}
  --openwebrx             Install OpenWebRX (browser SDR UI) and proxy at /radio
  --no-docker             Skip Docker install and docker compose actions
  --patch-dashboard-only  Only patch /var/www/html/index.html (no services touched)

Env overrides:
  INSTALL_DIR=/home/pi/PNK-HAMradio   PI_USER=pi
USAGE
}

# -------------------- Arg parsing --------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install|--update|--uninstall) ACTION="${1#--}"; shift;;
    --logs-api) WITH_LOGS_API="true"; shift;;
    --sdrpp) WITH_SDRPP="true"; shift;;
    --openwebrx) WITH_OPENWEBRX="true"; shift;;
    --no-docker) SKIP_DOCKER="true"; shift;;
    --patch-dashboard-only) PATCH_DASH_ONLY="true"; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

[[ -n "${ACTION:-}" ]] || { usage; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Please run as root: sudo $0 ..."; exit 1; }

log(){ echo -e "\n==> $*\n"; }

ensure_pkgs() {
  log "Installing system packages…"
  apt update
  apt install -y git curl lighttpd python3-pip ca-certificates
}

ensure_node() {
  if ! command -v node >/dev/null 2>&1; then
    log "Installing Node.js 20 LTS…"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt install -y nodejs
  fi
}

ensure_docker() {
  [[ "$SKIP_DOCKER" == "true" ]] && { log "Skipping Docker (--no-docker)."; return 0; }
  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker…"
    curl -fsSL https://get.docker.com | sh
  fi
  systemctl enable --now docker
  id -u "$PI_USER" >/dev/null 2>&1 || useradd -m "$PI_USER"
  usermod -aG docker "$PI_USER" || true
}

clone_or_update_repo() {
  log "Clone/update PNK-HAMradio repo…"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    git -C "$INSTALL_DIR" pull --ff-only origin main
  else
    rm -rf "$INSTALL_DIR"
    sudo -u "$PI_USER" git clone "$REPO" "$INSTALL_DIR"
  fi
  chown -R "$PI_USER:docker" "$INSTALL_DIR"
  chmod -R a+rwX "$INSTALL_DIR/matrix-pnk/etherpad/var" || true
  chmod -R a+rwX "$INSTALL_DIR/matrix-pnk/filebrowser"   || true
}

patch_dashboard_once() {
  log "Deploy/patch dashboard…"
  systemctl enable --now lighttpd

  # Only copy repo index during normal install/update flows (not in --patch-dashboard-only)
  if [[ "$PATCH_DASH_ONLY" != "true" && -f "$INSTALL_DIR/index.html" ]]; then
    [[ -f "$WWW_INDEX" && ! -f "${WWW_INDEX}.bak" ]] && cp "$WWW_INDEX" "${WWW_INDEX}.bak"
    cp "$INSTALL_DIR/index.html" "$WWW_INDEX"
  fi

  # Inject status panel + link fixer only if not present
  if ! grep -q "PNK PATCH v2: Status via /status" "$WWW_INDEX" 2>/dev/null; then
    # Build the HTML/JS blob safely (no shell interpretation)
    add_html="$(cat <<'HTML'
<!-- ===== PNK PATCH v2: Status via /status + HackChat link ===== -->
<section class="goals" style="margin:2rem 0">
  <h2>🩺 Service Status</h2>
  <div id="svc-status" class="goals-list">
    <div><span id="st-etherpad">⏳</span><div>Etherpad</div></div>
    <div><span id="st-filebrowser">⏳</span><div>FileBrowser</div></div>
    <div><span id="st-kolibri">⏳</span><div>Kolibri</div></div>
    <div><span id="st-unifi">⏳</span><div>UniFi UI</div></div>
    <div><span id="st-hackchat">⏳</span><div>HackChat WS</div></div>
    <div><span id="st-sdrpp">⏳</span><div>SDR++</div></div>
    <div><span id="st-owrx">⏳</span><div>SDR WebRX</div></div>
    <div><span id="st-logs">⏳</span><div>Logs API</div></div>
  </div>
</section>

<script>
(function(){
  const host = location.hostname;
  const proto = location.protocol;
  const isTLS = proto === "https:";
  const wsProto = isTLS ? "wss" : "ws";

  // We proxy HackChat at /chat-ws (configured in Lighttpd)
  const HC_WS = `${wsProto}://${host}/chat-ws`;

  // Rewrite tile links (new tab)
  const links = {
    svc1_link: `${proto}//${host}:9001`,      // Etherpad
    svc2_link: `${proto}//${host}:8081`,      // FileBrowser
    svc3_link: `${proto}//${host}:8082`,      // Kolibri
    svc4_link: `https://${host}:8443`,        // UniFi UI
    svc5_link: `https://hack.chat/?pnk&ws=${encodeURIComponent(HC_WS)}`,
    svc6_link: `/radio`                       // OpenWebRX via proxy
  };

  Object.entries(links).forEach(([k, href]) => {
    const el = document.querySelector(`a[data-key="${k}"]`);
    if (el) { el.href = href; el.target = "_blank"; el.rel = "noopener"; }
  });

  // Status via /status (proxied to Logs API if installed)
  const mark = (id, ok) => { const el = document.getElementById(id); if (el) el.textContent = ok ? "✅" : "❌"; };
  async function refresh() {
    try {
      const r = await fetch("/status");
      if (!r.ok) throw new Error();
      const data = await r.json(); const s = data.services || {};
      const okOr = (a,b) => (a === "active") || !!b; // accept HTTP/TCP success OR active systemd
      mark("st-etherpad",    okOr(s["etherpad"]?.systemd?.active,         s["etherpad"]?.http?.ok));
      mark("st-filebrowser", okOr(s["filebrowser"]?.systemd?.active,      s["filebrowser"]?.http?.ok));
      mark("st-kolibri",     okOr(s["kolibri"]?.systemd?.active,          s["kolibri"]?.http?.ok));
      mark("st-unifi",       okOr(s["unifi-controller"]?.systemd?.active, s["unifi-controller"]?.http?.ok));
      mark("st-hackchat",    okOr(s["hackchat-websocket"]?.systemd?.active, s["hackchat-websocket"]?.tcp));
      mark("st-sdrpp",       okOr(s["sdrpp"]?.systemd?.active,              s["sdrpp"]?.tcp));
      mark("st-owrx",        okOr(s["openwebrx"]?.systemd?.active,          s["openwebrx"]?.http?.ok));
      mark("st-logs", true);
    } catch {
      ["st-etherpad","st-filebrowser","st-kolibri","st-unifi","st-hackchat","st-sdrpp","st-owrx","st-logs"].forEach(id=>mark(id,false));
    }
  }
  refresh(); setInterval(refresh, 10000);
})();
</script>
<!-- ===== /PNK PATCH v2 ===== -->
HTML
)"

    # the injection just before </body>
    awk -v add="$add_html" '
      BEGIN { done=0 }
      /<\/body>/ && !done { sub(/<\/body>/, add "\n</body>"); done=1 }
      { print }
    ' "$WWW_INDEX" > /tmp/index.html.patched

    mv /tmp/index.html.patched "$WWW_INDEX"
  fi
}


setup_lighttpd_proxy() {
  log "Lighttpd: enable proxy + wstunnel and proxy /chat-ws & /radio…"
  lighttpd-enable-mod proxy >/dev/null 2>&1 || true
  lighttpd-enable-mod wstunnel >/dev/null 2>&1 || true

  local conf="/etc/lighttpd/conf-available/99-pnk-proxy.conf"
  touch "$conf"

  # /chat-ws for HackChat
  if ! grep -q '^\$HTTP\["url"\] =~ "\^/chat-ws"' "$conf"; then
    cat >> "$conf" <<'CONF'
# PNK HackChat WebSocket
$HTTP["url"] =~ "^/chat-ws" {
  wstunnel.server = ( "" => ( ( "host" => "127.0.0.1", "port" => 6060 ) ) )
}
CONF
  fi

  # /radio for OpenWebRX
  if ! grep -q '^\$HTTP\["url"\] =~ "\^/radio"' "$conf"; then
    cat >> "$conf" <<'CONF'
# PNK OpenWebRX proxy
$HTTP["url"] =~ "^/radio" {
  proxy.server = ( "" => ( ( "host" => "127.0.0.1", "port" => 8073 ) ) )
}
CONF
  fi

  ln -sf "$conf" "/etc/lighttpd/conf-enabled/99-pnk-proxy.conf"
  lighttpd -tt -f /etc/lighttpd/lighttpd.conf
  systemctl reload lighttpd
}

install_hackchat() {
  log "Install/Update HackChat (bare-metal)…"
  mkdir -p "$HC_DIR"
  if [[ ! -d "$HC_DIR/.git" ]]; then
    git clone https://github.com/hack-chat/main.git "$HC_DIR"
  fi
  git -C "$HC_DIR" fetch --all
  git -C "$HC_DIR" reset --hard origin/master

  # deps
  if ! npm -C "$HC_DIR" ci --omit=dev; then
    npm -C "$HC_DIR" install --omit=dev
  fi

  # systemd unit
  cat > "/etc/systemd/system/${HC_UNIT}.service" <<UNIT
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
  systemctl enable --now "${HC_UNIT}.service"
}

install_sdrpp_server() {
  log "Installing SDR++ (server mode)…"

  # 1) Root: build/runtime deps + USB groups
  apt-get update
  apt-get install -y \
    git cmake build-essential pkg-config \
    libfftw3-dev libusb-1.0-0-dev librtlsdr-dev \
    libglfw3-dev libvolk2-dev
  usermod -aG plugdev "${PI_USER}" || true

  # Optional: prevent DVB kernel driver from grabbing RTL-SDR dongles
  if ! grep -q 'dvb_usb_rtl28xxu' /etc/modprobe.d/blacklist-rtl.conf 2>/dev/null; then
    cat >/etc/modprobe.d/blacklist-rtl.conf <<'EOF'
blacklist dvb_usb_rtl28xxu
blacklist rtl2832
blacklist rtl2830
EOF
  fi

  # 2) Non-root: clone & build SDR++ in the user's home
  sudo -u "${PI_USER}" -H bash -lc '
    set -e
    mkdir -p "$HOME/src"
    cd "$HOME/src"
    if [ ! -d SDRPlusPlus ]; then
      git clone --recursive https://github.com/AlexandreRouma/SDRPlusPlus.git
    fi
    cd SDRPlusPlus
    git pull --ff-only || true
    git submodule update --init --recursive
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j"$(nproc)"
  '

  # 3) Root: install built binaries to /usr/local
  cmake --install "/home/${PI_USER}/src/SDRPlusPlus/build"

  # 4) systemd unit
  cat >/etc/systemd/system/${SDRPP_UNIT}.service <<UNIT
[Unit]
Description=SDR++ Server (headless)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${PI_USER}
Group=${PI_USER}
ExecStart=/usr/local/bin/sdrpp --server --addr 0.0.0.0 --port ${SDRPP_PORT}
Restart=on-failure
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable --now ${SDRPP_UNIT}.service

  log "SDR++ installed. Service: ${SDRPP_UNIT} on port ${SDRPP_PORT}"
}

# --- APT unjam helper for ham package conflicts (wsjtx/js8call/hpsdrconnector) ---
apt_unjam_ham() {
  dpkg --configure -a || true
  apt-get -y -f install || true

  for p in wsjtx wsjtx-data js8call hpsdrconnector; do
    if dpkg -l 2>/dev/null | awk '{print $2}' | grep -qx "$p"; then
      apt-get -y purge "$p" || true
    fi
  done

  rm -f /usr/share/pixmaps/wsjtx_icon.png 2>/dev/null || true

  apt-get -y -f install || true
  apt-get -y autoremove || true
  apt-get clean || true
  apt-get update
}

install_openwebrx() {
  log "Installing OpenWebRX (browser SDR)…"

  # Preflight: clear any dpkg/apt conflicts from ham packages
  apt_unjam_ham

  apt-get update
  local FALLBACK=0

  # Try native packages first (some distros have them; Pi OS often does not)
  if apt-cache policy openwebrx 2>/dev/null | grep -q 'Candidate:'; then
    if apt-get install -y openwebrx rtl-sdr sox csdr; then
      OPENWEBRX_UNIT="openwebrx"
    else
      echo "Native openwebrx package failed; falling back to OpenWebRX+ installer…"
      FALLBACK=1
    fi
  else
    FALLBACK=1
  fi

  if [[ "$FALLBACK" -eq 1 ]]; then
    # Make sure base deps are present
    apt-get install -y git python3 python3-pip rtl-sdr sox

    # Use maintained OpenWebRX+ installer (works well on Raspberry Pi)
    local tmp="/tmp/openwebrx-install.sh"
    curl -fsSL https://raw.githubusercontent.com/luarvique/luarvique.github.io/master/openwebrx-install.sh -o "$tmp"
    bash "$tmp" <<'EOF'
y
EOF
    OPENWEBRX_UNIT="openwebrx"
  fi

  # Enable & start service
  systemctl daemon-reload
  systemctl enable --now "${OPENWEBRX_UNIT}"

  # USB access for RTL-SDR user
  usermod -aG plugdev "${PI_USER}" || true

  # Ensure Lighttpd proxy exists (/radio -> 127.0.0.1:8073)
  setup_lighttpd_proxy

  log "OpenWebRX running. Visit: http://<pi-ip>/radio"
}

install_logs_api() {
  [[ "$WITH_LOGS_API" == "true" ]] || return 0
  log "Installing/Updating PNK Logs API…"
  mkdir -p "$LOGSAPI_DIR"

  # server.js
  cat > "${LOGSAPI_DIR}/server.js" <<'JS'
#!/usr/bin/env node
const http = require('http');
const https = require('https');
const net = require('net');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const url = require('url');

const CONFIG_PATH = path.join(__dirname, 'config.json');
if (!fs.existsSync(CONFIG_PATH)) { console.error('Missing config.json'); process.exit(1); }
let cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
const PORT = cfg.port || 6061;
const MAX_LINES = Math.max(1, Math.min(5000, parseInt(cfg.maxLines || '200', 10)));
const UNIT_MAP = cfg.unitMap || {};
const HTTP_CHECKS = cfg.httpChecks || {};
const TCP_CHECKS  = cfg.tcpChecks  || {};
const CORS = (cfg.corsAllowedOrigins || []);

function setCORS(req, res){
  if (!CORS.length) return;
  const origin = req.headers.origin;
  if (CORS.includes('*')) res.setHeader('Access-Control-Allow-Origin', '*');
  else if (origin && CORS.includes(origin)) { res.setHeader('Access-Control-Allow-Origin', origin); res.setHeader('Vary','Origin'); }
  res.setHeader('Access-Control-Allow-Methods','GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers','Content-Type');
}
function ok(res, body, type='application/json'){ res.statusCode=200; res.setHeader('Content-Type', type+'; charset=utf-8'); res.end(body); }
function bad(res, code, msg){ res.statusCode=code; res.setHeader('Content-Type','text/plain; charset=utf-8'); res.end(msg); }

function sysdStatus(unit){
  return new Promise((resolve)=>{
    const p = spawn('systemctl', ['show', unit, '--no-page','-p','ActiveState','-p','SubState','-p','MainPID']);
    let out=''; p.stdout.on('data',d=>out+=d.toString());
    p.on('close',()=>{ const m=Object.fromEntries(out.trim().split('\n').map(l=>l.split('='))); resolve({active:m.ActiveState||'unknown',sub:m.SubState||'unknown',pid:m.MainPID||'0'}); });
  });
}
function httpProbe(target,insecure=false,timeoutMs=3000){
  return new Promise((resolve)=>{
    try{
      const u=new URL(target); const lib=u.protocol==='https:'?https:http; const opts={method:'GET',timeout:timeoutMs};
      if(u.protocol==='https:'&&insecure) opts.rejectUnauthorized=false;
      const req=lib.request(u,(r)=>{ resolve({ok:(r.statusCode>=200&&r.statusCode<400),code:r.statusCode}); r.resume(); });
      req.on('timeout',()=>{ req.destroy(new Error('timeout')); });
      req.on('error',()=>resolve({ok:false,code:0}));
      req.end();
    }catch{ resolve({ok:false,code:0}); }
  });
}
function tcpProbe(host,port,timeoutMs=1500){
  return new Promise((resolve)=>{
    const s=net.createConnection({host,port});
    const t=setTimeout(()=>{ s.destroy(); resolve(false); },timeoutMs);
    s.on('connect',()=>{ clearTimeout(t); s.end(); resolve(true); });
    s.on('error',()=>{ clearTimeout(t); resolve(false); });
  });
}
function journal(unit,lines){
  return new Promise((resolve,reject)=>{
    const n=Math.max(1,Math.min(5000,parseInt(lines,10)||200));
    const args=['-u',unit,'-n',String(n),'--no-pager','--output','short-iso'];
    const jc=spawn('journalctl',args);
    let out='',err=''; jc.stdout.on('data',d=>out+=d.toString()); jc.stderr.on('data',d=>err+=d.toString());
    jc.on('close',c=> c===0?resolve(out||'(no logs)'):reject(err||`journalctl exited ${c}`));
  });
}
function sseLogs(req,res,unit,since){
  const args=['-u',unit,'-f','--output','short-iso']; if(since) args.push('--since',since);
  const jc=spawn('journalctl',args);
  res.writeHead(200,{'Content-Type':'text/event-stream; charset=utf-8','Cache-Control':'no-cache','Connection':'keep-alive'});
  res.write(':ok\n\n');
  const send=line=>res.write(`data: ${line.replace(/\r?\n/g,'')}\n\n`);
  jc.stdout.on('data',d=>d.toString().split('\n').filter(Boolean).forEach(send));
  jc.stderr.on('data',d=>d.toString().split('\n').filter(Boolean).forEach(l=>res.write(`event: err\ndata: ${l}\n\n`)));
  req.on('close',()=>{ try{jc.kill('SIGTERM');}catch{}; });
}
async function allStatus(){
  const keys=Object.keys(UNIT_MAP);
  const items=await Promise.all(keys.map(async k=>{
    const unit=UNIT_MAP[k];
    const sys=await sysdStatus(unit);
    let http=null,tcp=null;
    if(HTTP_CHECKS[k]){ const {url,insecure=false,timeoutMs=3000}=HTTP_CHECKS[k]; http=await httpProbe(url,insecure,timeoutMs); }
    if(TCP_CHECKS[k]){ const {host='127.0.0.1',port,timeoutMs=1500}=TCP_CHECKS[k]; tcp=await tcpProbe(host,port,timeoutMs); }
    return [k,{unit,systemd:sys,http,tcp}];
  }));
  return Object.fromEntries(items);
}

const srv=http.createServer(async (req,res)=>{
  const u=url.parse(req.url,true);
  if(req.method==='OPTIONS'){ setCORS(req,res); res.statusCode=204; return res.end(); }
  if(u.pathname==='/healthz'){ setCORS(req,res); return ok(res,'ok','text/plain'); }
  if(u.pathname==='/units'){ setCORS(req,res); return ok(res,JSON.stringify({units:UNIT_MAP},null,2)); }
  if(u.pathname==='/status'){
    try{ const data=await allStatus(); setCORS(req,res); return ok(res,JSON.stringify({ts:Date.now(),services:data},null,2)); }
    catch(e){ setCORS(req,res); return bad(res,500,String(e)); }
  }
  if(u.pathname && u.pathname.startsWith('/logs/')){
    const parts=u.pathname.split('/'); const key=decodeURIComponent(parts[2]||''); const unit=UNIT_MAP[key];
    if(!unit){ setCORS(req,res); return bad(res,404,`Unknown service key: ${key}`); }
    if(parts[3]==='stream'){ setCORS(req,res); const since=u.query.since||null; return sseLogs(req,res,unit,since); }
    try{ const body=await journal(unit,u.query.lines||200); setCORS(req,res); return ok(res,body,'text/plain'); }
    catch(e){ setCORS(req,res); return bad(res,500,String(e)); }
  }
  setCORS(req,res); return bad(res,404,'Not found');
});
srv.listen(cfg.port||6061,'127.0.0.1',()=>console.log(`PNK Logs API on 127.0.0.1:${cfg.port||6061}`));
JS
  chmod +x "${LOGSAPI_DIR}/server.js"

  # Build optional inserts for SDR++ and OpenWebRX
  local extra_unit=''
  local extra_tcp=''
  if [[ "$WITH_SDRPP" == "true" ]]; then
    extra_unit=',\n    "sdrpp": "'"${SDRPP_UNIT}"'"'
    extra_tcp=',\n    "sdrpp": { "host": "127.0.0.1", "port": '"${SDRPP_PORT}"', "timeoutMs": 1500 }'
  fi

  local extra_unit2=''
  local extra_http=''
  if [[ "$WITH_OPENWEBRX" == "true" || -n "${OPENWEBRX_UNIT:-}" ]]; then
    [[ -z "${OPENWEBRX_UNIT:-}" ]] && OPENWEBRX_UNIT="openwebrx"
    extra_unit2=',\n    "openwebrx": "'"${OPENWEBRX_UNIT}"'"'
    extra_http=',\n    "openwebrx": { "url": "http://127.0.0.1:8073/", "timeoutMs": 5000 }'
  fi

  # config.json
  cat > "${LOGSAPI_DIR}/config.json" <<JSON
{
  "port": ${LOGSAPI_PORT},
  "maxLines": 200,
  "corsAllowedOrigins": [],
  "unitMap": {
    "hackchat-websocket": "hackchat",
    "etherpad": "etherpad",
    "filebrowser": "filebrowser",
    "kolibri": "kolibri",
    "unifi-controller": "unifi"${extra_unit}${extra_unit2}
  },
  "httpChecks": {
    "etherpad": { "url": "http://127.0.0.1:9001/", "timeoutMs": 3000 },
    "filebrowser": { "url": "http://127.0.0.1:8081/", "timeoutMs": 3000 },
    "kolibri": { "url": "http://127.0.0.1:8082/", "timeoutMs": 5000 },
    "unifi-controller": { "url": "https://127.0.0.1:8443/", "insecure": true, "timeoutMs": 5000 }${extra_http}
  },
  "tcpChecks": {
    "hackchat-websocket": { "host": "127.0.0.1", "port": 6060, "timeoutMs": 1500 }${extra_tcp}
  }
}
JSON

  # systemd for Logs API
  cat > "/etc/systemd/system/${LOGSAPI_UNIT}.service" <<UNIT
[Unit]
Description=PNK Logs API (journald proxy)
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=${LOGSAPI_DIR}
ExecStart=/usr/bin/node ${LOGSAPI_DIR}/server.js
Restart=on-failure
User=${PI_USER}
Group=${PI_USER}
SupplementaryGroups=systemd-journal
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

  chown -R "${PI_USER}:${PI_USER}" "$LOGSAPI_DIR"
  systemctl daemon-reload
  systemctl enable --now "${LOGSAPI_UNIT}.service"

  # Lighttpd proxy blocks for /logs and /status
  local conf="/etc/lighttpd/conf-available/99-pnk-proxy.conf"
  if ! grep -q '^\$HTTP\["url"\] =~ "\^/logs/"' "$conf"; then
    cat >> "$conf" <<'CONF'
# PNK Logs API proxy
$HTTP["url"] =~ "^/logs/" {
  proxy.server = ( "" => ( ( "host" => "127.0.0.1", "port" => 6061 ) ) )
}
CONF
  fi
  if ! grep -q '^\$HTTP\["url"\] =~ "\^/status\$"' "$conf"; then
    cat >> "$conf" <<'CONF'
# PNK Status API proxy
$HTTP["url"] =~ "^/status$" {
  proxy.server = ( "" => ( ( "host" => "127.0.0.1", "port" => 6061 ) ) )
}
CONF
  fi
  ln -sf "$conf" "/etc/lighttpd/conf-enabled/99-pnk-proxy.conf"
  lighttpd -tt -f /etc/lighttpd/lighttpd.conf
  systemctl reload lighttpd
}

start_compose_stack() {
  [[ "$SKIP_DOCKER" == "true" ]] && { log "Skipping compose stack (--no-docker)."; return 0; }
  log "Start/Update Docker services (detached)…"
  local compose_cmd="docker compose"
  $compose_cmd down --remove-orphans || true
  $compose_cmd pull
  $compose_cmd up -d --remove-orphans

  echo -e "\nContainers:"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# -------------------- MAIN ACTIONS --------------------
case "$ACTION" in
  install|update)
    # unjam before any apt installs
    apt_unjam_ham

    ensure_pkgs

    # If patch-only, just patch HTML and bail out early
    if [[ "$PATCH_DASH_ONLY" == "true" ]]; then
      log "Running in --patch-dashboard-only mode (no services will be changed)…"
      patch_dashboard_once
      echo "✅ Dashboard patched. Browse: http://<pi-ip>/"
      exit 0
    fi

    ensure_node
    ensure_docker
    clone_or_update_repo
    patch_dashboard_once
    setup_lighttpd_proxy
    install_hackchat
    [[ "$WITH_SDRPP" == "true" ]] && install_sdrpp_server
    [[ "$WITH_OPENWEBRX" == "true" ]] && install_openwebrx
    [[ "$WITH_LOGS_API" == "true" ]] && install_logs_api
    start_compose_stack
    echo -e "\n✅ Done! Open:  http://<pi-ip>/"
    echo "   HackChat WS: ws(s)://<pi-host>/chat-ws"
    [[ "$WITH_SDRPP" == "true" ]] && echo "   SDR++:       Connect via SDR++ client → ${SDRPP_PORT} (Source: \"SDR++ Server\")"
    [[ "$WITH_OPENWEBRX" == "true" ]] && echo "   OpenWebRX:   http://<pi-ip>/radio"
    [[ "$WITH_LOGS_API" == "true" ]] && echo "   Status JSON: http://<pi-ip>/status    Logs: http://<pi-ip>/logs/<service>"
    ;;
  uninstall)
    systemctl disable --now "$HC_UNIT" 2>/dev/null || true
    rm -f "/etc/systemd/system/${HC_UNIT}.service"
    rm -rf "$HC_DIR"

    if systemctl list-unit-files | grep -q "^${LOGSAPI_UNIT}\.service"; then
      systemctl disable --now "$LOGSAPI_UNIT" || true
      rm -f "/etc/systemd/system/${LOGSAPI_UNIT}.service"
      rm -rf "$LOGSAPI_DIR"
    fi

    if systemctl list-unit-files | grep -q "^${SDRPP_UNIT}\.service"; then
      systemctl disable --now "$SDRPP_UNIT" || true
      rm -f "/etc/systemd/system/${SDRPP_UNIT}.service"
    fi

    if systemctl list-unit-files | grep -q '^openwebrx' ; then
      systemctl disable --now openwebrx 2>/dev/null || true
    fi
    if systemctl list-unit-files | grep -q '^openwebrx-plus' ; then
      systemctl disable --now openwebrx-plus 2>/dev/null || true
    fi

    systemctl daemon-reload
    echo "Uninstalled HackChat and (if present) Logs API + SDR++ + OpenWebRX (proxies remain)."
    ;;
esac

