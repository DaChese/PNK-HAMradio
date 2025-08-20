#!/usr/bin/env bash
set -euo pipefail

# === Defaults (override via flags) ===
API_USER="pnklogs"
API_DIR="/opt/pnk-logs-api"
API_PORT="6061"
SYSTEMD_NAME="pnk-logs-api"
MAX_LINES="200"
# CORS: "*" allows any origin; set to "" to disable; or comma-separated origins.
CORS_ALLOWED="*"

# Unit map: dashboard key -> systemd unit (comma-separated list of key:unit)
# By default we wire HackChat. Add your others later or pass --units "etherpad:etherpad,filebrowser:filebrowser"
UNITS_DEFAULT="hackchat-websocket:hackchat"

NGINX_SITE=""     # e.g. /etc/nginx/sites-available/hackchat (must already exist)
OVERWRITE_CONFIG="false"

usage() {
  cat <<USAGE
Usage:
  sudo $0 --install [--port N] [--units key:unit,...] [--cors "*"|origin1,origin2] [--nginx-site PATH] [--overwrite-config]
  sudo $0 --update  [same flags as above]
  sudo $0 --uninstall

Options:
  --port N               API port (default: ${API_PORT})
  --units LIST           Comma-separated key:unit map (default: ${UNITS_DEFAULT})
  --cors LIST            "*" or comma-separated allowed origins (default: ${CORS_ALLOWED})
  --max-lines N          Default max lines returned (default: ${MAX_LINES})
  --nginx-site PATH      Patch this Nginx site file to proxy /logs/ -> 127.0.0.1:\$PORT
  --overwrite-config     Overwrite existing config.json (otherwise preserved)
  --dir PATH             Install dir (default: ${API_DIR})
  --user NAME            Service user (default: ${API_USER})

Examples:
  sudo $0 --install --nginx-site /etc/nginx/sites-available/hackchat
  sudo $0 --install --units "hackchat-websocket:hackchat,etherpad:etherpad" --cors "https://pnk.local"
  sudo $0 --update --units "hackchat-websocket:hackchat"
  sudo $0 --uninstall
USAGE
}

ACTION=""
UNITS="$UNITS_DEFAULT"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install|--update|--uninstall) ACTION="${1#--}"; shift;;
    --port) API_PORT="$2"; shift 2;;
    --units) UNITS="$2"; shift 2;;
    --cors) CORS_ALLOWED="$2"; shift 2;;
    --max-lines) MAX_LINES="$2"; shift 2;;
    --nginx-site) NGINX_SITE="$2"; shift 2;;
    --overwrite-config) OVERWRITE_CONFIG="true"; shift;;
    --dir) API_DIR="$2"; shift 2;;
    --user) API_USER="$2"; shift 2;;
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
  # Install Node 20 LTS (fallback to repo node if needed)
  if curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; then
    apt-get install -y nodejs
  else
    apt-get install -y nodejs npm || true
  fi
  command -v node >/dev/null 2>&1 || { echo "Node install failed"; exit 1; }
}

ensure_user() {
  id -u "$API_USER" >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin -d "$API_DIR" "$API_USER"
  # grant read access to journald
  getent group systemd-journal >/dev/null 2>&1 || groupadd -r systemd-journal
  usermod -a -G systemd-journal "$API_USER" || true
}

parse_units_json() {
  # Convert "a:b,c:d" into JSON object string {"a":"b","c":"d"}
  local input="$1"
  local IFS=',' out="{" first=1
  for pair in $input; do
    key="${pair%%:*}"; val="${pair#*:}"
    [[ -z "$key" || -z "$val" ]] && continue
    [[ $first -eq 0 ]] && out+=","
    out+="\"$key\":\"$val\""
    first=0
  done
  out+="}"
  echo "$out"
}

write_server_js() {
  mkdir -p "$API_DIR"
  cat > "${API_DIR}/server.js" <<'JS'
#!/usr/bin/env node
const http = require('http');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const url = require('url');

const CONFIG_PATH = path.join(__dirname, 'config.json');
if (!fs.existsSync(CONFIG_PATH)) {
  console.error('Missing config.json');
  process.exit(1);
}
let cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));

function setCORS(req, res) {
  const allow = cfg.corsAllowedOrigins || [];
  if (!allow.length) return;
  const origin = req.headers.origin;
  if (allow.includes('*')) {
    res.setHeader('Access-Control-Allow-Origin', '*');
  } else if (origin && allow.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

const server = http.createServer((req, res) => {
  const u = url.parse(req.url, true);

  if (req.method === 'OPTIONS') {
    setCORS(req, res);
    res.statusCode = 204;
    return res.end();
  }

  if (u.pathname === '/healthz') {
    setCORS(req, res);
    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    return res.end('ok');
  }

  if (u.pathname && u.pathname.startsWith('/logs/')) {
    const parts = u.pathname.split('/');
    const key = decodeURIComponent(parts[2] || '');
    const unit = (cfg.unitMap || {})[key];
    if (!unit) {
      setCORS(req, res);
      res.statusCode = 404;
      res.setHeader('Content-Type', 'text/plain; charset=utf-8');
      return res.end(`Unknown service key: ${key}`);
    }
    const maxL = Math.max(1, Math.min(5000, parseInt(cfg.maxLines || '200', 10)));
    const lines = Math.max(1, Math.min(maxL, parseInt(u.query.lines || cfg.maxLines || '200', 10)));

    const args = ['-u', unit, '-n', String(lines), '--no-pager', '--output', 'short-iso'];
    const jc = spawn('journalctl', args);
    let out = '', err = '';
    jc.stdout.on('data', d => out += d.toString());
    jc.stderr.on('data', d => err += d.toString());
    jc.on('close', code => {
      setCORS(req, res);
      res.statusCode = code === 0 ? 200 : 500;
      res.setHeader('Content-Type', 'text/plain; charset=utf-8');
      res.end(code === 0 ? (out || '(no logs)') : (err || `journalctl exited ${code}`));
    });
    return;
  }

  setCORS(req, res);
  res.statusCode = 404;
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.end('Not found');
});

server.listen(cfg.port, '127.0.0.1', () => {
  console.log(`PNK Logs API listening on 127.0.0.1:${cfg.port}`);
});
JS
  chmod +x "${API_DIR}/server.js"
}

write_config_json() {
  local units_json; units_json="$(parse_units_json "$UNITS")"
  local cors_json="[]"
  if [[ -n "$CORS_ALLOWED" ]]; then
    if [[ "$CORS_ALLOWED" == "*" ]]; then
      cors_json='["*"]'
    else
      # split by comma
      IFS=',' read -r -a arr <<< "$CORS_ALLOWED"
      cors_json="[\"${arr[*]// /\",\"}\"]"
    fi
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
  "unitMap": ${units_json}
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
# Access to journals through supplemental group
SupplementaryGroups=systemd-journal
# Hardening
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

patch_nginx_site() {
  local site="$1"
  [[ -z "$site" ]] && return 0
  [[ -f "$site" ]] || { echo "Nginx site not found: $site (skipping)"; return 0; }

  local begin="# BEGIN PNK LOGS API"
  local end="# END PNK LOGS API"

  # Strip previous block (if any)
  awk -v b="$begin" -v e="$end" '
    BEGIN{skip=0}
    index($0,b){skip=1}
    !skip{print}
    index($0,e){skip=0}
  ' "$site" > "${site}.tmp"

  # Insert our block before the last closing brace "}"
  awk -v b="$begin" -v e="$end" -v port="$API_PORT" '
    BEGIN{last=0}
    { lines[++n]=$0 }
    END{
      last=n
      # Find last line containing only "}" (end of server block)
      idx=0
      for(i=n;i>=1;i--){
        if (match(lines[i],/^[ \t]*}[ \t]*$/)) { idx=i; break }
      }
      if (idx==0) { idx=n } # fallback append
      for(i=1;i<idx;i++) print lines[i]
      print "  " b
      print "  location /logs/ {"
      print "    proxy_pass http://127.0.0.1:" port "/;"
      print "    proxy_http_version 1.1;"
      print "    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
      print "  }"
      print "  " e
      for(i=idx;i<=n;i++) print lines[i]
    }
  ' "${site}.tmp" > "${site}.new"

  mv "${site}.new" "$site"
  rm -f "${site}.tmp"
  ln -sf "$site" "/etc/nginx/sites-enabled/$(basename "$site")"
  nginx -t && systemctl reload nginx
  echo "Patched Nginx site: $site (location /logs/ -> 127.0.0.1:${API_PORT})"
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
  [[ -n "$NGINX_SITE" ]] && patch_nginx_site "$NGINX_SITE"
  echo "✅ Logs API installed. Service: ${SYSTEMD_NAME} (127.0.0.1:${API_PORT})"
}

do_update() {
  systemctl stop "${SYSTEMD_NAME}.service" 2>/dev/null || true
  write_server_js
  write_config_json
  systemctl start "${SYSTEMD_NAME}.service"
  [[ -n "$NGINX_SITE" ]] && patch_nginx_site "$NGINX_SITE"
  echo "✅ Logs API updated & restarted."
}

do_uninstall() {
  systemctl disable --now "${SYSTEMD_NAME}.service" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SYSTEMD_NAME}.service"
  systemctl daemon-reload
  rm -rf "$API_DIR"
  echo "✅ Logs API uninstalled."
  [[ -n "$NGINX_SITE" ]] && echo "Note: Nginx site was not modified. You can remove the /logs/ block manually if desired."
}

case "$ACTION" in
  install)   do_install ;;
  update)    do_update ;;
  uninstall) do_uninstall ;;
esac
