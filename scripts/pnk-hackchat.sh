#!/usr/bin/env bash
set -euo pipefail

# === Defaults (override with flags) ===
HC_USER="pnk"
HC_DIR="/opt/hackchat"
HC_BRANCH="master"
HC_HOST="0.0.0.0"
HC_PORT="6060"
WITH_NGINX="false"
SERVER_NAME="_"            # use "_" for any host, or set to domain
LOCATION_WS="/chat-ws"     # websocket mount (leave as /chat-ws)
SYSTEMD_NAME="hackchat"

usage() {
  cat <<USAGE
pnk-hackchat.sh --install|--update|--uninstall [options]

Options:
  --dir PATH            Install dir (default: $HC_DIR)
  --user NAME           Service user (default: $HC_USER)
  --branch BRANCH       Git branch/tag (default: $HC_BRANCH)
  --host IP             Bind address (default: $HC_HOST)
  --port N              Listen port (default: $HC_PORT)
  --nginx               Also configure Nginx reverse proxy
  --server-name NAME    Nginx server_name (default: $SERVER_NAME)
  --ws-path PATH        Nginx WS path (default: $LOCATION_WS)

Examples:
  sudo ./pnk-hackchat.sh --install --nginx --server-name pnk.local
  sudo ./pnk-hackchat.sh --update
  sudo ./pnk-hackchat.sh --uninstall
USAGE
}

ACTION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install|--update|--uninstall) ACTION="${1#--}"; shift;;
    --dir) HC_DIR="$2"; shift 2;;
    --user) HC_USER="$2"; shift 2;;
    --branch) HC_BRANCH="$2"; shift 2;;
    --host) HC_HOST="$2"; shift 2;;
    --port) HC_PORT="$2"; shift 2;;
    --nginx) WITH_NGINX="true"; shift;;
    --server-name) SERVER_NAME="$2"; shift 2;;
    --ws-path) LOCATION_WS="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

[[ -z "${ACTION:-}" ]] && { usage; exit 1; }

ensure_tools() {
  apt-get update -y
  apt-get install -y ca-certificates curl git
}

ensure_node() {
  if command -v node >/dev/null 2>&1; then
    local ver; ver="$(node -v | sed 's/^v//;s/\..*//;q')"
    if [[ "$ver" -ge 16 ]]; then
      return 0
    fi
  fi
  # Try NodeSource Node 20; fall back to repo nodejs if needed
  if curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; then
    apt-get install -y nodejs
  else
    apt-get install -y nodejs npm || true
  fi
  command -v node >/dev/null 2>&1 || { echo "Node install failed"; exit 1; }
}

ensure_user() {
  id -u "$HC_USER" >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin -d "$HC_DIR" "$HC_USER"
}

clone_or_update_repo() {
  mkdir -p "$HC_DIR"
  chown -R "$SUDO_USER:$SUDO_USER" "$HC_DIR" || true
  if [[ -d "$HC_DIR/.git" ]]; then
    pushd "$HC_DIR" >/dev/null
    git fetch --all
    git checkout "$HC_BRANCH"
    git reset --hard "origin/$HC_BRANCH"
    popd >/dev/null
  else
    git clone https://github.com/hack-chat/main.git "$HC_DIR"
    pushd "$HC_DIR" >/dev/null
    git checkout "$HC_BRANCH" || true
    popd >/dev/null
  fi
}

install_deps() {
  pushd "$HC_DIR" >/dev/null
  if npm ci --omit=dev; then
    :
  else
    npm install --omit=dev
  fi
  popd >/dev/null
}

write_config() {
  cat >"$HC_DIR/.hcserver.json" <<JSON
{
  "host": "${HC_HOST}",
  "port": ${HC_PORT},
  "msgRateLimit": 2,
  "msgRateWindow": 1000,
  "maxMessageLength": 2048
}
JSON
  chown "$HC_USER:$HC_USER" "$HC_DIR/.hcserver.json"
}

write_service() {
  cat >/etc/systemd/system/${SYSTEMD_NAME}.service <<UNIT
[Unit]
Description=HackChat WebSocket Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${HC_DIR}
User=${HC_USER}
Group=${HC_USER}
Environment=NODE_ENV=production
ExecStart=/usr/bin/node ${HC_DIR}/main.mjs
Restart=on-failure
RestartSec=3
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
  chown -R "$HC_USER:$HC_USER" "$HC_DIR"
  systemctl enable --now "${SYSTEMD_NAME}.service"
}

setup_nginx() {
  apt-get install -y nginx
  local site="/etc/nginx/sites-available/hackchat"
  cat >"$site" <<NGINX
server {
  listen 80;
  server_name ${SERVER_NAME};

  # WebSocket proxy to HackChat
  location ${LOCATION_WS} {
    proxy_pass http://127.0.0.1:${HC_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 86400;
  }

  # Optional landing redirect to your default room via the official client
  location = /chat {
    return 302 https://hack.chat/?pnk&ws=\$scheme://\$host${LOCATION_WS};
  }
}
NGINX
  ln -sf "$site" /etc/nginx/sites-enabled/hackchat
  nginx -t
  systemctl reload nginx
}

do_install() {
  ensure_tools
  ensure_node
  ensure_user
  clone_or_update_repo
  install_deps
  write_config
  write_service
  enable_start
  [[ "$WITH_NGINX" == "true" ]] && setup_nginx
  echo "✅ HackChat installed. Service: ${SYSTEMD_NAME}. Port: ${HC_PORT}"
  echo "   Test: journalctl -u ${SYSTEMD_NAME} -n 50 --no-pager"
}

do_update() {
  systemctl stop "${SYSTEMD_NAME}.service" || true
  clone_or_update_repo
  install_deps
  systemctl start "${SYSTEMD_NAME}.service"
  echo "✅ HackChat updated & restarted."
}

do_uninstall() {
  systemctl disable --now "${SYSTEMD_NAME}.service" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SYSTEMD_NAME}.service"
  systemctl daemon-reload
  # leave Nginx as-is; admin can remove the site if desired
  rm -rf "$HC_DIR"
  echo "✅ HackChat uninstalled (service & dir removed)."
}

case "$ACTION" in
  install)   do_install ;;
  update)    do_update ;;
  uninstall) do_uninstall ;;
esac
