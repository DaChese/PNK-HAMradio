#!/usr/bin/env bash
set -euo pipefail

# =======================
#  PNK Logs API Installer
# =======================

API_USER="pnklogs"
API_DIR="/opt/pnk-logs-api"
API_PORT="6061"
SYSTEMD_NAME="pnk-logs-api"
MAX_LINES="200"
CORS_ALLOWED=""              # "" = disabled; "*" = any; or comma-separated origins
UNITS_DEFAULT="hackchat-websocket:hackchat"
ENABLE_HTTP_DEFAULTS="true"  # add default HTTP checks for Etherpad/FileBrowser/Kolibri/UniFi
ENABLE_LIGHTTPD="true"       # patch Lighttpd with /logs/ and /status
NGINX_SITE=""                # optional: /etc/nginx/sites-available/your-site (if you use nginx instead of lighttpd)
OVERWRITE_CONFIG="false"

usage() {
  cat <<USAGE
Usage:
  sudo $0 --install [options]
  sudo $0 --update  [options]
  sudo $0 --uninstall

Options:
  --dir PATH              Install dir (default: ${API_DIR})
  --user NAME             Service user (default: ${API_USER})
  --port N                API port (default: ${API_PORT})
  --units LIST            Comma-separated key:unit map (default: ${UNITS_DEFAULT})
  --cors LIST             "*" or comma-separated allowed origins (default: disabled)
  --max-lines N           Max lines per /logs request (default: ${MAX_LINES})
  --no-http-defaults      Do not preseed Etherpad/FileBrowser/Kolibri/UniFi HTTP checks
  --no-lighttpd           Skip Lighttpd patching
  --nginx-site PATH       Also patch this nginx site with /logs/ and /status proxy
  --overwrite-config      Regenerate config.json even if it exists

Examples:
  sudo $0 --install
  sudo $0 --install --units "hackchat-websocket:hackchat,etherpad:etherpad"
  sudo $0 --update --cors "*"
  sudo $0 --uninstall
USAGE
}

ACTION=""
UNITS="$UNITS_DEFAULT"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install|--update|--uninstall) ACTION="${1#--}"; shift;;
    --dir) API_DIR="$2"; shift 2;;
    --user) API_USER="$2"; shift 2;;
    --port) API_PORT="$2"; shift 2;;
    --units) UNITS="$2"; shift 2;;
    --cors) CORS_ALLOWED="$2"; shift 2;;
    --max-lines) MAX_LINES="$2"; shift 2;;
    --no-http-defaults) ENABLE_HTTP_DEFAULTS="false"; shift;;
    --no-lighttpd) ENABLE_LIGHTTPD="false"; shift;;
    --nginx-site) NGINX_SITE="$2"; shift 2;;
    --overwrite-config) OVERWRITE_CONFIG="true"; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done
[[ -z "${ACTION:-}" ]] && { usage; exit 1; }
[[ $EUID -ne 0 ]] && { echo "Please run as root (sudo)."; exit 1; }

ensure_tools() {
  apt-get update -y
  apt-get install -y ca-certificates curl git
}

ensure_node() {
  if command -v node >/dev/null 2>&1; then
    local major; major="$(node -v | sed 's/^v//;s/\..*//;q')"
    if [[ "$major" -ge 16 ]]; then return 0; fi
  fi
  if curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; then
    apt-get install -y nodejs
  else
    apt-get install -y nodejs npm || true
  fi
  command -v node >/dev/null 2>&1 || { echo "Node install failed"; exit 1; }
}

ensure_user() {
  id -u "$API_USER" >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin -d "$API_DIR" "$API_USER"
  getent group systemd-journal >/dev/null 2>&1 || groupadd -r systemd-journal
  usermod -a -G systemd-journal "$API_USER" || true
}

parse_units_json() {
  local input="$1" IFS=',' out="{" first=1
  for pair in $input; do
    key="${pair%%:*}"; val="${pair#*:}"
    [[ -z "$key" || -z "$val" ]] && continue
    [[ $first -eq 0 ]] && out+=","
    out+="\"$key\":\"$val\""; first=0
  done
  out+="}"
  echo "$out"
}

write_server_js() {
  mkdir -p "$API_DIR"
  cat > "${API_DIR}/server.js" <<'JS'
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
const HTTP_CHECKS = cfg.httpChecks || {};   // { key: { url, insecure, timeoutMs } }
const TCP_CHECKS  = cfg.tcpChecks  || {};   // { key: { host, port, timeoutMs } }
const CORS = (cfg.corsAllowedOrigins || []);

function setCORS(req, res) {
  if (!CORS.length) return;
  const origin = req.headers.origin;
  if (CORS.includes('*')) {
    res.setHeader('Access-Control-Allow-Origin', '*');
  } else if (origin && CORS.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}
function ok(res, body, type='application/json') {
  res.statusCode = 200; res.setHeader('Content-Type', type+'; charset=utf-8'); res.end(body);
}
function bad(res, code, msg) {
  res.statusCode = code; res.setHeader('Content-Type', 'text/plain; charset=utf-8'); res.end(msg);
}

function sysdStatus(unit) {
  return new Promise((resolve) => {
    const p = spawn('systemctl', ['show', unit, '--no-page', '-p','ActiveState','-p','SubState','-p','MainPID']);
    let out=''; p.stdout.on('data', d=> out+=d.toString());
    p.on('close', ()=> {
      const m = Object.fromEntries(out.trim().split('\n').map(l=>l.split('=')));
      resolve({ active: m.ActiveState || 'unknown', sub: m.SubState || 'unknown', pid: m.MainPID || '0' });
    });
  });
}
function httpProbe(target, insecure=false, timeoutMs=3000) {
  return new Promise((resolve) => {
    try {
      const u = new URL(target);
      const lib = u.protocol === 'https:' ? https : http;
      const opts = { method: 'GET', timeout: timeoutMs };
      if (u.protocol === 'https:' && insecure) opts.rejectUnauthorized = false;
      const req = lib.request(u, (r)=> { resolve({ ok: (r.statusCode>=200 && r.statusCode<400), code: r.statusCode }); r.resume(); });
      req.on('timeout', ()=> { req.destroy(new Error('timeout')); });
      req.on('error', ()=> resolve({ ok:false, code:0 }));
      req.end();
    } catch { resolve({ ok:false, code:0 }); }
  });
}
function tcpProbe(host, port, timeoutMs=1500) {
  return new Promise((resolve)=>{
    const s = net.createConnection({ host, port });
    const t = setTimeout(()=>{ s.destroy(); resolve(false); }, timeoutMs);
    s.on('connect', ()=> { clearTimeout(t); s.end(); resolve(true); });
    s.on('error', ()=> { clearTimeout(t); resolve(false); });
  });
}
function journal(unit, lines) {
  return new Promise((resolve, reject) => {
    const n = Math.max(1, Math.min(MAX_LINES, parseInt(lines,10)||MAX_LINES));
    const args = ['-u', unit, '-n', String(n), '--no-pager', '--output', 'short-iso'];
    const jc = spawn('journalctl', args);
    let out = '', err=''; jc.stdout.on('data', d=> out+=d.toString()); jc.stderr.on('data', d=> err+=d.toString());
    jc.on('close', c=> c===0 ? resolve(out || '(no logs)') : reject(err || `journalctl exited ${c}`));
  });
}
function sseLogs(req, res, unit, since) {
  const args = ['-u', unit, '-f', '--output', 'short-iso'];
  if (since) args.push('--since', since);
  const jc = spawn('journalctl', args);
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive'
  });
  res.write(':ok\n\n');
  const send = (line)=> res.write(`data: ${line.replace(/\r?\n/g,'')}\n\n`);
  jc.stdout.on('data', d => d.toString().split('\n').filter(Boolean).forEach(send));
  jc.stderr.on('data', d => d.toString().split('\n').filter(Boolean).forEach(l=> res.write(`event: err\ndata: ${l}\n\n`)));
  req.on('close', ()=> { try{jc.kill('SIGTERM');}catch{}; });
}
async function allStatus() {
  const keys = Object.keys(UNIT_MAP);
  const items = await Promise.all(keys.map(async (k)=>{
    const unit = UNIT_MAP[k];
    const sys = await sysdStatus(unit);
    let http=null, tcp=null;
    if (HTTP_CHECKS[k]) {
      const { url, insecure=false, timeoutMs=3000 } = HTTP_CHECKS[k];
      http = await httpProbe(url, insecure, timeoutMs);
    }
    if (TCP_CHECKS[k]) {
      const { host='127.0.0.1', port, timeoutMs=1500 } = TCP_CHECKS[k];
      tcp = await tcpProbe(host, port, timeoutMs);
    }
    return [k, { unit, systemd: sys, http, tcp }];
  }));
  return Object.fromEntries(items);
}

const srv = http.createServer(async (req, res) => {
  const u = url.parse(req.url, true);
  if (req.method === 'OPTIONS') { setCORS(req,res); res.statusCode=204; return res.end(); }
  if (u.pathname === '/healthz') { setCORS(req,res); return ok(res, 'ok', 'text/plain'); }
  if (u.pathname === '/units')   { setCORS(req,res); return ok(res, JSON.stringify({ units: UNIT_MAP }, null, 2)); }
  if (u.pathname === '/status')  {
    try { const data = await allStatus(); setCORS(req,res); return ok(res, JSON.stringify({ ts: Date.now(), services: data }, null, 2)); }
    catch(e){ setCORS(req,res); return bad(res, 500, String(e)); }
  }
  if (u.pathname && u.pathname.startsWith('/logs/')) {
    const parts = u.pathname.split('/');
    const key = decodeURIComponent(parts[2] || '');
    const unit = UNIT_MAP[key];
    if (!unit) { setCORS(req,res); return bad(res, 404, `Unknown service key: ${key}`); }
    if (parts[3] === 'stream') {
      setCORS(req,res);
      const since = u.query.since || null;  // e.g., '1h' or '2025-08-20 10:00:00'
      return sseLogs(req, res, unit, since);
    }
    try { const body = await journal(unit, u.query.lines || MAX_LINES); setCORS(req,res); return ok(res, body, 'text/plain'); }
    catch(e){ setCORS(req,res); return bad(res, 500, String(e)); }
  }
  setCORS(req,res); return bad(res, 404, 'Not found');
});
srv.listen(PORT, '127.0.0.1', () => console.log(`PNK Logs API on 127.0.0.1:${PORT}`));
JS
  chmod +x "${API_DIR}/server.js"
}

write_config_json() {
  local units_json; units_json="$(parse_units_json "$UNITS")"

  # CORS array
  local cors_json="[]"
  if [[ -n "$CORS_ALLOWED" ]]; then
    if [[ "$CORS_ALLOWED" == "*" ]]; then cors_json='["*"]'
    else IFS=',' read -r -a arr <<< "$CORS_ALLOWED"; cors_json="[\"${arr[*]// /\",\"}\"]"
    fi
  fi

  # Default HTTP/TCP checks (safe to keep; dashboard uses same host)
  local http_checks=''
  if [[ "$ENABLE_HTTP_DEFAULTS" == "true" ]]; then
read -r -d '' http_checks <<JSON
,
  "httpChecks": {
    "etherpad":       { "url": "http://127.0.0.1:9001/", "timeoutMs": 3000 },
    "filebrowser":    { "url": "http://127.0.0.1:8081/", "timeoutMs": 3000 },
    "kolibri":        { "url": "http://127.0.0.1:8082/", "timeoutMs": 5000 },
    "unifi-controller": { "url": "https://127.0.0.1:8443/", "insecure": true, "timeoutMs": 5000 }
  },
  "tcpChecks": {
    "hackchat-websocket": { "host": "127.0.0.1", "port": 6060, "timeoutMs": 1500 }
  }
JSON
  fi

  if [[ -f "${API_DIR}/config.json" && "$OVERWRITE_CONFIG" != "true" ]]; then
    echo "Preserving existing ${API_DIR}/config.json (use --overwrite-config to regenerate)."
    return
  fi

  cat > "${API_DIR}/config.json" <<JSON
{
  "port": ${API_PORT},
  "maxLines": ${MAX_LINES},
  "corsAllowedOrigins": ${cors_json},
  "unitMap": ${units_json}${http_checks:-}
}
JSON
  chown "${API_USER}:${API_USER}" "${API_DIR}/config.json" || true
}

write_systemd_unit() {
  cat > "/etc/systemd/system/${SYSTEMD_NAME}.service" <<UNIT
[Unit]
Description=PNK Logs API (journald proxy)
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=${API_DIR}
ExecStart=/usr/bin/node ${API_DIR}/server.js
Restart=on-failure
User=${API_USER}
Group=${API_USER}
SupplementaryGroups=systemd-journal
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
}

enable_start() {
  chown -R "${API_USER}:${API_USER}" "${API_DIR}"
  systemctl enable --now "${SYSTEMD_NAME}.service"
}

patch_lighttpd() {
  [[ "$ENABLE_LIGHTTPD" != "true" ]] && return 0
  if ! command -v lighttpd >/dev/null 2>&1; then
    echo "lighttpd not found; skipping Lighttpd patch."
    return 0
  fi
  # Ensure proxy module
  lighttpd-enable-mod proxy >/dev/null 2>&1 || true

  local conf="/etc/lighttpd/conf-available/99-pnk-proxy.conf"
  [[ -f "$conf" ]] || touch "$conf"

  # Add /logs/ and /status blocks if missing
  grep -q '^\\$HTTP\\["url"\\] =~ "\\^/logs/"' "$conf" || cat >> "$conf" <<'CONF'
# PNK Logs API proxy
$HTTP["url"] =~ "^/logs/" {
  proxy.server = ( "" => ( ( "host" => "127.0.0.1", "port" => 6061 ) ) )
}
CONF

  grep -q '^\\$HTTP\\["url"\\] =~ "\\^/status\\$"' "$conf" || cat >> "$conf" <<'CONF'
# PNK Status API proxy
$HTTP["url"] =~ "^/status$" {
  proxy.server = ( "" => ( ( "host" => "127.0.0.1", "port" => 6061 ) ) )
}
CONF

  ln -sf "$conf" "/etc/lighttpd/conf-enabled/99-pnk-proxy.conf"
  lighttpd -tt -f /etc/lighttpd/lighttpd.conf
  systemctl reload lighttpd
  echo "Lighttpd patched: /logs/ and /status now proxied to 127.0.0.1:${API_PORT}"
}

patch_nginx() {
  local site="$NGINX_SITE"
  [[ -n "$site" ]] || return 0
  [[ -f "$site" ]] || { echo "Nginx site not found: $site (skipping)"; return 0; }

  local begin="# BEGIN PNK LOGS API"
  local end="# END PNK LOGS API"
  awk -v b="$begin" -v e="$end" '
    BEGIN{skip=0}
    index($0,b){skip=1}
    !skip{print}
    index($0,e){skip=0}
  ' "$site" > "${site}.tmp"

  awk -v b="$begin" -v e="$end" -v port="$API_PORT" '
    { lines[++n]=$0 }
    END{
      idx=0
      for(i=n;i>=1;i--) if (match(lines[i],/^[ \t]*}[ \t]*$/)) { idx=i; break }
      if (idx==0) idx=n
      for(i=1;i<idx;i++) print lines[i]
      print "  " b
      print "  location /logs/ { proxy_pass http://127.0.0.1:" port "/; proxy_http_version 1.1; }"
      print "  location = /status { proxy_pass http://127.0.0.1:" port "/status; proxy_http_version 1.1; }"
      print "  " e
      for(i=idx;i<=n;i++) print lines[i]
    }
  ' "${site}.tmp" > "${site}.new"

  mv "${site}.new" "$site"
  rm -f "${site}.tmp"
  ln -sf "$site" "/etc/nginx/sites-enabled/$(basename "$site")"
  nginx -t && systemctl reload nginx
  echo "Patched Nginx site: $site (proxied /logs/ and /status)"
}

do_install() {
  ensure_tools
  ensure_node
  ensure_user
  mkdir -p "$API_DIR"
  write_server_js
  write_config_json
  write_systemd_unit
  enable_start
  patch_lighttpd
  patch_nginx
  echo "✅ Logs API installed. Service: ${SYSTEMD_NAME} (127.0.0.1:${API_PORT})"
}

do_update() {
  systemctl stop "${SYSTEMD_NAME}.service" 2>/dev/null || true
  write_server_js
  write_config_json
  systemctl start "${SYSTEMD_NAME}.service"
  patch_lighttpd
  patch_nginx
  echo "✅ Logs API updated & restarted."
}

do_uninstall() {
  systemctl disable --now "${SYSTEMD_NAME}.service" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SYSTEMD_NAME}.service"
  systemctl daemon-reload
  rm -rf "$API_DIR"
  echo "✅ Logs API uninstalled."
  echo "Note: Web server proxies (/logs, /status) remain; remove from Lighttpd/Nginx if desired."
}

case "$ACTION" in
  install)   do_install ;;
  update)    do_update ;;
  uninstall) do_uninstall ;;
esac