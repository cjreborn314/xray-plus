#!/bin/sh
# 给 6in4 / SIT 隧道夹紧 TCP MSS，减轻 PMTUD 黑洞导致的卡顿。
# 原生 IPv6（例如多数欧洲 VPS）一般不需要。

set -eu
IFACE="${1:-ipv6net}"
MSS="${2:-1360}"

command -v ip6tables >/dev/null 2>&1 || exit 0
ip link show "$IFACE" >/dev/null 2>&1 || exit 0

ip6tables -t mangle -C OUTPUT -o "$IFACE" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$MSS" 2>/dev/null \
  || ip6tables -t mangle -A OUTPUT -o "$IFACE" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$MSS"
ip6tables -t mangle -C INPUT -i "$IFACE" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$MSS" 2>/dev/null \
  || ip6tables -t mangle -A INPUT -i "$IFACE" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$MSS"
