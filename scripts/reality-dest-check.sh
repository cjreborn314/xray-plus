#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="${CONFIG:-/usr/local/etc/xray/config.json}"
XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
LOCK_FILE="/run/reality-dest-check.lock"
STATE_FILE="/var/lib/xray/reality-dest-check.state"
TIMEOUT_SECS="${TIMEOUT_SECS:-8}"
RETRIES="${RETRIES:-3}"
RETRY_SLEEP="${RETRY_SLEEP:-4}"

CANDIDATES=(
    dl.google.com
    www.microsoft.com
    www.samsung.com
    www.cisco.com
    www.intel.com
    www.amd.com
)

log() {
    logger -t reality-dest-check -- "$*"
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"
}

die() {
    log "错误：$*"
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

dest_ok() {
    local host="$1"
    local out
    out="$(
        timeout "$TIMEOUT_SECS" openssl s_client \
            -connect "${host}:443" \
            -servername "$host" \
            -alpn h2 \
            </dev/null 2>/dev/null || true
    )"
    grep -q "ALPN protocol: h2" <<<"$out"
}

current_dest_host() {
    python3 - "$CONFIG" <<'PY'
import json, sys
from pathlib import Path
c = json.loads(Path(sys.argv[1]).read_text())
rs = c["inbounds"][0]["streamSettings"]["realitySettings"]
dest = rs.get("dest") or rs.get("target") or ""
host = str(dest).split(":")[0]
print(host)
PY
}

apply_dest() {
    local host="$1"
    python3 - "$CONFIG" "$host" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
host = sys.argv[2]
c = json.loads(path.read_text())
rs = c["inbounds"][0]["streamSettings"]["realitySettings"]
value = f"{host}:443"
rs["dest"] = value
rs["target"] = value
names = list(rs.get("serverNames") or [])
if host not in names:
    names.append(host)
# Keep previously working names so existing client SNI still matches.
rs["serverNames"] = names
path.write_text(json.dumps(c, indent=2, ensure_ascii=False) + "\n")
print(",".join(names))
PY
}

mkdir -p /var/lib/xray
require_cmd python3
require_cmd openssl
require_cmd timeout
require_cmd logger
[[ -f "$CONFIG" ]] || die "找不到 $CONFIG"
[[ -x "$XRAY_BIN" ]] || die "找不到 $XRAY_BIN"

exec 9>"$LOCK_FILE"
flock -n 9 || {
    log "已有检查在运行，退出"
    exit 0
}

current="$(current_dest_host)"
[[ -n "$current" ]] || die "未能读取当前 dest"

ok=0
for ((i = 1; i <= RETRIES; i++)); do
    if dest_ok "$current"; then
        ok=1
        break
    fi
    log "当前伪装站不可用：$current （第 ${i}/${RETRIES} 次）"
    sleep "$RETRY_SLEEP"
done

if [[ "$ok" == "1" ]]; then
    echo "$current" >"$STATE_FILE"
    exit 0
fi

log "开始轮换伪装站，当前失败：$current"
new=""
for host in "${CANDIDATES[@]}"; do
    [[ "$host" == "$current" ]] && continue
    if dest_ok "$host"; then
        new="$host"
        break
    fi
    log "候选不可用：$host"
done

[[ -n "$new" ]] || die "所有候选伪装站均不可用，保持 $current"

backup="${CONFIG}.bak.dest.$(date +%Y%m%d_%H%M%S)"
cp -a "$CONFIG" "$backup"

names="$(apply_dest "$new")"
if ! "$XRAY_BIN" run -test -config "$CONFIG"; then
    cp -a "$backup" "$CONFIG"
    die "配置测试失败，已回滚到 $current"
fi

if ! systemctl restart xray; then
    cp -a "$backup" "$CONFIG"
    systemctl restart xray || true
    die "Xray 重启失败，已回滚到 $current"
fi

sleep 1
systemctl is-active --quiet xray || {
    cp -a "$backup" "$CONFIG"
    systemctl restart xray || true
    die "Xray 未保持运行，已回滚到 $current"
}

echo "$new" >"$STATE_FILE"
log "伪装站已切换 $current -> $new ；serverNames=$names ；客户端原 SNI 仍可用，建议稍后执行 /root/xray.sh --show 确认"
