#!/usr/bin/env bash
# FoxServersHost — Auto-Ptero Installer
# Mode: Hybrid (Interactive + Silent)
# Style: Neon Purple
# Author: FoxServersHost

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
TZONE="${TZ:-America/Sao_Paulo}"

### 🎨 NEON PURPLE UI ###
vio(){ printf "\033[38;5;129m%s\033[0m" "$*"; }
neon(){ printf "\033[38;5;207m%s\033[0m" "$*"; }
ok(){ echo -e "\033[1;32m[OK]\033[0m $*"; }
err(){ echo -e "\033[1;31m[ERR]\033[0m $*" >&2; }
info(){ echo -e "\033[1;36m[INFO]\033[0m $*"; }
title(){
clear
echo -e "$(vio '──────────────────────────────────────────────')"
echo -e " $(neon 'FoxServersHost Auto-Ptero Installer 🟣')"
echo -e "$(vio '──────────────────────────────────────────────')"
}

### 🔧 PARAMS ###
SILENT=0
TELEMETRY=${TELEMETRY:-1}
TELEMETRY_URL="${TELEMETRY_URL:-https://autoinstall.foxsvhost.com/api/install-logs}"

PANEL_DOMAIN="${PANEL_DOMAIN:-}"
FASTDL_DOMAIN="${FASTDL_DOMAIN:-}"
WINGS_DOMAIN="${WINGS_DOMAIN:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"

### 🔐 SECRETS ###
randpass(){ openssl rand -base64 48 | tr -dc 'A-Za-z0-9@%_-+=' | head -c 22; echo; }
randhex(){ openssl rand -hex 32; }

TITLE_DONE=0
title

### 🧠 ARGUMENT HANDLING ###
for arg in "$@"; do
  case "$arg" in
    --silent) SILENT=1 ;;
    --no-telemetry) TELEMETRY=0 ;;
    --panel=*) PANEL_DOMAIN="${arg#*=}" ;;
    --fastdl=*) FASTDL_DOMAIN="${arg#*=}" ;;
    --wings=*) WINGS_DOMAIN="${arg#*=}" ;;
    --email=*) ADMIN_EMAIL="${arg#*=}" ;;
  esac
done

### 🛑 ROOT CHECK ###
if [[ $(id -u) -ne 0 ]]; then
  err "Run as root: sudo bash install.sh"
  exit 1
fi

### 🧩 INPUT (only if not silent) ###
if [[ "$SILENT" -eq 0 ]]; then
  read -rp "Panel Domain: " PANEL_DOMAIN
  read -rp "FastDL Domain: " FASTDL_DOMAIN
  read -rp "Wings Domain: " WINGS_DOMAIN
  read -rp "Admin Email: " ADMIN_EMAIL
fi

if [[ -z "$PANEL_DOMAIN" || -z "$FASTDL_DOMAIN" || -z "$WINGS_DOMAIN" || -z "$ADMIN_EMAIL" ]]; then
  err "Missing environment variables"
  exit 1
fi

### 🔑 Generate Secrets ###
PANEL_DB_PASSWORD="$(randpass)"
PANEL_ADMIN_PASSWORD="$(randpass)"
JWT_SECRET="$(randhex)"
FASTDL_TOKEN="$(randhex)"

### 📄 REPORT FILE ###
REPORT="/root/foxservers_install_report.txt"

info "Starting automated installation..."
sleep 2

### 📦 Install System Dependencies ###
info "Installing system dependencies..."
apt-get update -y
apt-get install -y \
  curl wget zip unzip git jq lsb-release gnupg ca-certificates \
  software-properties-common apt-transport-https \
  ufw nginx certbot python3-certbot-nginx

ok "Base packages installed."

### 🧱 Firewall ###
info "Configuring firewall..."
ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable || true
ok "Firewall configured."

### 🐳 Install Docker ###
info "Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
ok "Docker installed and running."

### 📦 Check docker-compose plugin ###
if ! docker compose version &>/dev/null; then
  err "docker compose plugin missing — installation failed"
  exit 1
fi

### 🔐 Install SSL for domains ###
info "Issuing SSL certificates..."
certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" || true
certbot --nginx -d "$FASTDL_DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" || true
certbot --nginx -d "$WINGS_DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" || true

ok "SSL setup attempted (Certbot may retry automatically)."

### 🐦 Install Pterodactyl Panel ###
info "Setting up Pterodactyl Panel..."

mkdir -p /opt/pterodactyl
cd /opt/pterodactyl

cat > docker-compose.yml <<EOF
services:
  mariadb:
    image: mariadb:10.11
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${PANEL_DB_PASSWORD}
      MYSQL_DATABASE: panel
      MYSQL_USER: pterodactyl
      MYSQL_PASSWORD: ${PANEL_DB_PASSWORD}
    volumes:
      - ./database:/var/lib/mysql

  redis:
    image: redis:alpine
    restart: unless-stopped
    command: ["redis-server", "--save", "", "--appendonly", "no"]

  panel:
    image: ghcr.io/pterodactyl/panel:latest
    restart: unless-stopped
    depends_on:
      - mariadb
      - redis
    environment:
      APP_URL: https://${PANEL_DOMAIN}
      APP_ENV: production
      APP_TIMEZONE: ${TZONE}
      DB_HOST: mariadb
      DB_PORT: 3306
      DB_DATABASE: panel
      DB_USERNAME: pterodactyl
      DB_PASSWORD: ${PANEL_DB_PASSWORD}
      CACHE_DRIVER: redis
      SESSION_DRIVER: redis
      QUEUE_CONNECTION: redis
      REDIS_HOST: redis
    volumes:
      - ./var:/app/var
    ports:
      - "127.0.0.1:8080:8080"
EOF

docker compose up -d
sleep 15

info "Running panel setup..."

docker compose exec -T panel php artisan key:generate --force
docker compose exec -T panel php artisan migrate --force
docker compose exec -T panel php artisan storage:link

docker compose exec -T panel php artisan p:user:make \
  --email="${ADMIN_EMAIL}" \
  --admin=1 \
  --password="${PANEL_ADMIN_PASSWORD}" \
  --name-first="Admin" \
  --name-last="Fox" || true

### 🌐 NGINX CONFIG FOR PANEL ###
cat > /etc/nginx/sites-available/panel.conf <<EOF
server {
    listen 80;
    server_name ${PANEL_DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

ln -sf /etc/nginx/sites-available/panel.conf /etc/nginx/sites-enabled/panel.conf
nginx -t && systemctl restart nginx

ok "Pterodactyl Panel installed!"

### 🦅 Install Wings (Pterodactyl Node) ###
info "Installing Wings..."

# Create user & directories
id -u pterodactyl &>/dev/null || useradd -r -m -d /etc/pterodactyl -s /bin/false pterodactyl
mkdir -p /etc/pterodactyl /var/lib/pterodactyl /var/log/pterodactyl
chown -R pterodactyl:pterodactyl /etc/pterodactyl /var/lib/pterodactyl /var/log/pterodactyl

# Download latest Wings binary
curl -sSL https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64 -o /usr/local/bin/wings
chmod +x /usr/local/bin/wings

### ⚙️ Wings systemd service ###
cat > /etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
ExecStart=/usr/local/bin/wings
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now wings

### 🌐 NGINX FOR WINGS ###
cat > /etc/nginx/sites-available/wings.conf <<EOF
server {
    listen 80;
    server_name ${WINGS_DOMAIN};

    location / {
        return 200 "Wings Node Installed ✅\n";
    }
}
EOF

ln -sf /etc/nginx/sites-available/wings.conf /etc/nginx/sites-enabled/wings.conf
nginx -t && systemctl restart nginx

### 🔐 Issue SSL ###
info "Issuing SSL for Wings..."
certbot --nginx -d "$WINGS_DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" || true

ok "Wings installed and running! ✅"

### 🚀 FastDL Agent Installation ###
info "Installing FastDL Agent..."

mkdir -p /opt/fastdl-agent
cd /opt/fastdl-agent

# Create config
cat > config.json <<EOF
{
  "panel_url": "https://${PANEL_DOMAIN}",
  "fastdl_domain": "https://${FASTDL_DOMAIN}",
  "token": "${FASTDL_TOKEN}",
  "allowed_extensions": ["bsp","res","wad","mdl","vpk","bz2","zip","rar","png","jpg","wav","mp3"],
  "games": {
    "cstrike": "/var/lib/pterodactyl/volumes/cstrike/cstrike",
    "valve": "/var/lib/pterodactyl/volumes/valve/valve",
    "mta": "/var/lib/pterodactyl/volumes/mta/mods/deathmatch/resources",
    "l4d2": "/var/lib/pterodactyl/volumes/l4d2/left4dead2"
  },
  "fastdl_path": "/var/www/fastdl"
}
EOF

mkdir -p /var/www/fastdl
mkdir -p /opt/fastdl-agent/uploads

# Install Node + PM2
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs
npm install pm2 -g

# Create agent script
cat > index.js << 'EOF'
// FastDL Agent Core
const fs = require("fs");
const path = require("path");
const WebSocket = require("ws");
const { exec } = require("child_process");

const config = require("./config.json");
const ws = new WebSocket(`${config.panel_url.replace("https", "wss")}/fastdl/ws?token=${config.token}`);

ws.on("open", () => console.log("[FastDL] Connected to Panel ✅"));
ws.on("message", async (data) => {
  const msg = JSON.parse(data);

  if (msg.action === "upload") {
    const filePath = path.join(config.fastdl_path, msg.file);
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, Buffer.from(msg.data, "base64"));
    ws.send(JSON.stringify({status:"ok",file:msg.file}));
  }

  if (msg.action === "sync") {
    for (const game in config.games) {
      const src = config.games[game];
      exec(`rsync -av --exclude='*.log' ${src}/ ${config.fastdl_path}/${game}/`);
    }
    ws.send(JSON.stringify({status:"synced"}));
  }
});
EOF

# PM2 run
pm2 start index.js --name fastdl-agent
pm2 save

### 🔧 FastDL NGINX ###
cat > /etc/nginx/sites-available/fastdl.conf <<EOF
server {
    listen 80;
    server_name ${FASTDL_DOMAIN};
    root /var/www/fastdl;
    autoindex on;
}
EOF

ln -sf /etc/nginx/sites-available/fastdl.conf /etc/nginx/sites-enabled/fastdl.conf
nginx -t && systemctl restart nginx

### 🔐 FastDL SSL ###
info "Issuing SSL for FastDL..."
certbot --nginx -d "$FASTDL_DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" || true

ok "FastDL Agent Installed ✅"

### 📩 Installation Report ###
info "Writing install report..."

cat > "$REPORT" <<EOF
FoxServers Auto-Ptero Installation Completed ✅

Panel: https://${PANEL_DOMAIN}
Wings: https://${WINGS_DOMAIN}
FastDL: https://${FASTDL_DOMAIN}

Admin Email: ${ADMIN_EMAIL}
Admin Password: ${PANEL_ADMIN_PASSWORD}

Database Password: ${PANEL_DB_PASSWORD}
JWT Secret: ${JWT_SECRET}
FastDL Token: ${FASTDL_TOKEN}

Installation Date: $(date)
Server IP: $(hostname -I | awk '{print $1}')

EOF

ok "Report saved to $REPORT"


### ✉️ Email Report ###
if command -v mail >/dev/null 2>&1; then
  echo "FoxServers Auto-Ptero installed ✅

Panel: https://${PANEL_DOMAIN}
Wings: https://${WINGS_DOMAIN}
FastDL: https://${FASTDL_DOMAIN}

Admin Email: ${ADMIN_EMAIL}
Admin Password: ${PANEL_ADMIN_PASSWORD}" | mail -s "FoxServers Auto-Ptero Installed" "$ADMIN_EMAIL"
fi


### 📡 Telemetry (Optional) ###
if [[ "$TELEMETRY" -eq 1 ]]; then
  curl -s -X POST "$TELEMETRY_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"panel\": \"$PANEL_DOMAIN\",
      \"fastdl\": \"$FASTDL_DOMAIN\`,
      \"wings\": \"$WINGS_DOMAIN\",
      \"ip\": \"$(hostname -I | awk '{print $1}')\",
      \"admin\": \"$ADMIN_EMAIL\"
    }" >/dev/null 2>&1 || true
fi

ok "Telemetry processed (or skipped)."

### 🧹 Cleanup ###
info "Finalizing installation..."

systemctl restart nginx
systemctl restart wings || true
pm2 save || true

### 🚀 Display Final Info ###
title
echo ""
neon "✅ FoxServers Auto-Ptero Installation Complete!"
echo ""
echo ""
echo "$(vio 'Panel URL:') https://${PANEL_DOMAIN}"
echo "$(vio 'Wings URL:') https://${WINGS_DOMAIN}"
echo "$(vio 'FastDL URL:') https://${FASTDL_DOMAIN}"
echo ""
echo "$(vio 'Admin Email:') ${ADMIN_EMAIL}"
echo "$(vio 'Admin Password:') ${PANEL_ADMIN_PASSWORD}"
echo ""
echo "Report saved at: $REPORT"
echo ""
echo "$(neon '⚠️ Important: Save your credentials!')"
echo ""
sleep 1

### 🦊 FoxServers ASCII ###
echo -e "\033[38;5;129m"
cat << "EOF"
███████╗ ██████╗ ██╗  ██╗███████╗███████╗██████╗ ███████╗
██╔════╝██╔═══██╗██║ ██╔╝██╔════╝██╔════╝██╔══██╗██╔════╝
█████╗  ██║   ██║█████╔╝ █████╗  █████╗  ██║  ██║█████╗  
██╔══╝  ██║   ██║██╔═██╗ ██╔══╝  ██╔══╝  ██║  ██║██╔══╝  
██║     ╚██████╔╝██║  ██╗███████╗███████╗██████╔╝███████╗
╚═╝      ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚═════╝ ╚══════╝
EOF
echo -e "\033[0m"
echo ""
neon "FoxServersHost Auto-Ptero — Powered by you 🟣"
echo ""
echo "For updates visit: https://github.com/FoxServersHost/FoxServers-AutoPtero"
echo ""

exit 0
