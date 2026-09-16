#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
PORT_FALLBACK="443"
REMARK="${REMARK:-Reality-Vision}"

detect_address() {
    if [[ -n "${XRAY_ADDRESS:-}" ]]; then
        printf '%s\n' "$XRAY_ADDRESS"
        return
    fi
    curl -4 -fsS --max-time 5 https://ip.sb 2>/dev/null \
        || curl -4 -fsS --max-time 5 https://ifconfig.me 2>/dev/null \
        || hostname -I 2>/dev/null | awk '{print $1}'
}

usage() {
    cat <<'USAGE'
用法：
  /root/xray.sh --show
  /root/xray.sh -s
      只读取当前 Reality 配置并打印导入链接，不改配置，不重启。

  /root/xray.sh --update
      生成新 UUID，写入配置，测试并重启 Xray，然后打印新链接。

  /root/xray.sh --help
      显示帮助。

可用环境变量：
  XRAY_ADDRESS   导入链接里的服务器地址（默认自动探测公网 IPv4）
  REMARK         链接备注名（默认 Reality-Vision）
USAGE
}

die() {
    echo "错误：$*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || die "找不到文件：$1"
}

urlencode() {
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=\"\"))" "$1"
}

read_node_info() {
    require_file "$CONFIG"
    command -v python3 >/dev/null 2>&1 || die "未安装 python3"
    [[ -x "$XRAY_BIN" ]] || die "找不到可执行的 Xray：$XRAY_BIN"

    mapfile -t NODE_INFO < <(
        python3 - "$CONFIG" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

for inbound in data.get("inbounds", []):
    if inbound.get("protocol") != "vless":
        continue
    clients = inbound.get("settings", {}).get("clients", [])
    if not clients or not clients[0].get("id"):
        continue
    stream = inbound.get("streamSettings") or {}
    reality = stream.get("realitySettings") or {}
    names = reality.get("serverNames") or []
    shorts = reality.get("shortIds") or []
    print(clients[0].get("id", ""))
    print(clients[0].get("flow", ""))
    print(stream.get("network", "tcp"))
    print(stream.get("security", ""))
    print(inbound.get("port") or "")
    print(reality.get("privateKey") or "")
    print(names[0] if names else "")
    print(shorts[0] if shorts else "")
    sys.exit(0)
sys.exit(2)
PY
    ) || die "没有在配置中找到有效的 VLESS Reality 入站"

    UUID="${NODE_INFO[0]:-}"
    FLOW="${NODE_INFO[1]:-}"
    NETWORK="${NODE_INFO[2]:-tcp}"
    SECURITY="${NODE_INFO[3]:-}"
    XRAY_PORT="${NODE_INFO[4]:-$PORT_FALLBACK}"
    PRIVATE_KEY="${NODE_INFO[5]:-}"
    SNI="${NODE_INFO[6]:-}"
    SHORT_ID="${NODE_INFO[7]:-}"
    ADDRESS="$(detect_address)"

    [[ -n "$UUID" ]] || die "未读取到 UUID"
    [[ "$SECURITY" == "reality" ]] || die "当前安全层不是 reality，而是：${SECURITY:-空}"
    [[ -n "$PRIVATE_KEY" ]] || die "未读取到 Reality privateKey"
    [[ -n "$SNI" ]] || die "未读取到 serverNames/SNI"
    [[ -n "$ADDRESS" ]] || die "未探测到服务器地址，请设置 XRAY_ADDRESS"

    if [[ "$NETWORK" == "raw" ]]; then
        NETWORK="tcp"
    fi
    [[ -n "$FLOW" ]] || FLOW="xtls-rprx-vision"
    [[ -n "$XRAY_PORT" ]] || XRAY_PORT="$PORT_FALLBACK"

    PUBLIC_KEY="$("$XRAY_BIN" x25519 -i "$PRIVATE_KEY" | awk -F": " "/PublicKey/{print \$2; exit}")"
    [[ -n "$PUBLIC_KEY" ]] || die "无法从 privateKey 计算出 publicKey"
}

build_vless_link() {
    local encoded_sni encoded_name encoded_spx
    encoded_sni="$(urlencode "$SNI")"
    encoded_name="$(urlencode "$REMARK")"
    encoded_spx="$(urlencode "/")"
    VLESS_LINK="vless://${UUID}@${ADDRESS}:${XRAY_PORT}?encryption=none&flow=${FLOW}&security=reality&sni=${encoded_sni}&fp=firefox&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=${encoded_spx}&type=${NETWORK}#${encoded_name}"
}

show_link() {
    read_node_info
    build_vless_link

    cat <<EOF

当前 Reality 导入链接：

$VLESS_LINK

参数：
  地址        $ADDRESS
  端口        $XRAY_PORT
  UUID        $UUID
  flow        $FLOW
  传输        $NETWORK
  安全        reality
  SNI         $SNI
  fingerprint firefox
  publicKey   $PUBLIC_KEY
  shortId     $SHORT_ID
  spiderX     /

EOF
}

generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        die "无法生成 UUID，请安装 uuid-runtime"
    fi
}

replace_uuid() {
    local new_uuid="$1"
    local temp_file
    temp_file="$(mktemp "${CONFIG}.tmp.XXXXXX")"

    if ! python3 - "$CONFIG" "$temp_file" "$new_uuid" <<'PY'
import json
import os
import sys

src, dst, new_uuid = sys.argv[1:4]
with open(src, "r", encoding="utf-8") as f:
    data = json.load(f)

updated = False
for inbound in data.get("inbounds", []):
    if inbound.get("protocol") != "vless":
        continue
    clients = inbound.get("settings", {}).get("clients", [])
    if not clients:
        continue
    clients[0]["id"] = new_uuid
    if not clients[0].get("flow"):
        clients[0]["flow"] = "xtls-rprx-vision"
    updated = True
    break

if not updated:
    raise SystemExit("没有找到可更新的 VLESS 客户端")

with open(dst, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.chmod(dst, 0o600)
PY
    then
        rm -f "$temp_file"
        die "修改 UUID 失败"
    fi

    mv "$temp_file" "$CONFIG"
    chmod 600 "$CONFIG"
}

update_uuid() {
    require_file "$CONFIG"
    [[ -x "$XRAY_BIN" ]] || die "找不到可执行的 Xray：$XRAY_BIN"

    local backup new_uuid
    backup="${CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
    cp -a "$CONFIG" "$backup"
    chmod 600 "$backup"

    new_uuid="$(generate_uuid)"
    replace_uuid "$new_uuid"

    if ! "$XRAY_BIN" run -test -config "$CONFIG"; then
        cp -a "$backup" "$CONFIG"
        chmod 600 "$CONFIG"
        die "Xray 配置测试失败，已恢复原配置"
    fi

    if ! systemctl restart xray; then
        cp -a "$backup" "$CONFIG"
        chmod 600 "$CONFIG"
        systemctl restart xray || true
        die "Xray 重启失败，已恢复原配置"
    fi

    sleep 1
    if ! systemctl is-active --quiet xray; then
        cp -a "$backup" "$CONFIG"
        chmod 600 "$CONFIG"
        systemctl restart xray || true
        die "Xray 未保持运行状态，已恢复原配置"
    fi

    show_link
    echo "旧配置备份：$backup"
    echo
}

case "${1:-show}" in
    --show|-s|show)
        show_link
        ;;
    --update|-u|update)
        update_uuid
        ;;
    --help|-h|help)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
