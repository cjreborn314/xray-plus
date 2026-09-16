#!/bin/bash
# 旧版 VLESS + WS + TLS 的 UUID 轮换脚本。
# Reality 节点请改用 scripts/xray.sh --update

CONFIG="/usr/local/etc/xray/config.json"
DOMAIN="${DOMAIN:-vpn.example.com}"
PORT="${PORT:-443}"
WS_PATH="${WS_PATH:-/YOUR_WS_PATH}"

echo "===== VLESS UUID 更新工具（WS） ====="

if [ ! -f "$CONFIG" ]; then
    echo "错误: 找不到 $CONFIG"
    exit 1
fi

BACKUP="${CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
cp "$CONFIG" "$BACKUP"
echo "已备份: $BACKUP"

NEW_UUID=$(uuidgen)
echo "新的 UUID: $NEW_UUID"

sed -i -E "s/(\"id\"[[:space:]]*:[[:space:]]*\")[^\"]+/\1$NEW_UUID/" "$CONFIG"

echo "正在检查 Xray 配置..."
if ! xray run -test -config "$CONFIG"; then
    echo "配置错误，恢复备份"
    cp "$BACKUP" "$CONFIG"
    exit 1
fi

systemctl restart xray
sleep 2
STATUS=$(systemctl is-active xray)
if [ "$STATUS" != "active" ]; then
    echo "Xray 启动失败"
    systemctl status xray --no-pager
    exit 1
fi

ENC_PATH=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$WS_PATH")
VLESS="vless://${NEW_UUID}@${DOMAIN}:${PORT}?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${ENC_PATH}&sni=${DOMAIN}#${DOMAIN}"

echo "Xray 状态: $STATUS"
echo "新的 VLESS 链接:"
echo "$VLESS"
