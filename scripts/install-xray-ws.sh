#!/bin/bash
set -e

DOMAIN=$1

if [ -z "$DOMAIN" ]; then
    echo "用法:"
    echo "bash install-xray-ws.sh vpn.example.com"
    exit 1
fi

echo "=== 更新系统 ==="
apt update
apt install -y nginx curl wget unzip socat certbot python3-certbot-nginx

echo "=== 安装 Xray ==="
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" install

UUID=$(cat /proc/sys/kernel/random/uuid)
WS_PATH="/$(openssl rand -hex 8)"

echo
echo "UUID:"
echo "$UUID"
echo
echo "WS PATH:"
echo "$WS_PATH"

echo "=== 创建 Xray 配置 ==="
mkdir -p /usr/local/etc/xray

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10000,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "$WS_PATH"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

echo "=== 配置 nginx ==="
cat >/etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
nginx -t
systemctl restart nginx

echo "=== 申请证书 ==="
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN"

echo "=== 写入 HTTPS WS 配置 ==="
cat >/etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location $WS_PATH {
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_buffering off;
        proxy_request_buffering off;
        gzip off;
    }

    location / {
        root /var/www/html;
        index index.html;
    }
}

server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
EOF

nginx -t
systemctl reload nginx

echo "=== 启动 Xray ==="
systemctl enable xray
systemctl restart xray

echo
echo "=============================="
echo "安装完成"
echo
echo "域名: $DOMAIN"
echo "UUID: $UUID"
echo "WS路径: $WS_PATH"
echo
echo "客户端链接:"
echo "vless://$UUID@$DOMAIN:443?encryption=none&security=tls&type=ws&host=$DOMAIN&path=$WS_PATH#$DOMAIN"
echo "=============================="
