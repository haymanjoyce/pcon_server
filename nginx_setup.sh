#!/usr/bin/env bash
# nginx_setup.sh — Install Nginx, configure doc_app, and obtain SSL certificate
# Usage: sudo bash ~/nginx_setup.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Must be run as root (use sudo)." >&2
    exit 1
fi

DOMAIN="pcon.pro"
DIST_DIR="/home/richard/projects/doc_app/frontend/dist"
BACKEND="http://127.0.0.1:8000"

echo "[1/5] Installing Nginx, certbot and apache2-utils..."
apt-get install -y nginx certbot python3-certbot-nginx apache2-utils

echo "[2/5] Creating Basic Auth credentials..."
echo ""
echo "Enter the username for Basic Auth:"
read -r BA_USER
htpasswd -c /etc/nginx/.htpasswd "$BA_USER"
chmod 640 /etc/nginx/.htpasswd
chown root:www-data /etc/nginx/.htpasswd
echo "    .htpasswd created for user '$BA_USER'."

echo "[3/5] Writing Nginx config..."
cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;

    root $DIST_DIR;
    index index.html;

    # Basic Auth
    auth_basic "doc_app";
    auth_basic_user_file /etc/nginx/.htpasswd;

    # WebSocket — must come before the general /api/ block
    location /api/chat/ws {
        proxy_pass $BACKEND/api/chat/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 3600s;
    }

    # REST API
    location /api/ {
        proxy_pass $BACKEND/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # React SPA — fall back to index.html for client-side routing
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
rm -f /etc/nginx/sites-enabled/default

echo "[4/5] Testing and reloading Nginx..."
nginx -t
systemctl reload nginx

echo "[5/5] Obtaining SSL certificate..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect

echo ""
echo "=== Done ==="
echo "Site live at https://$DOMAIN"
