# xray-plus

Xray 安装与运维脚本。当前推荐方案是 **VLESS + Reality + Vision**；仓库同时保留旧的一键安装脚本和 VLESS + WS + TLS 工具。

请仅在合法合规的前提下使用。

## 仓库结构

```text
xray-plus.sh                 # 旧版一键安装菜单（hijk，多种协议）
scripts/xray.sh              # Reality 节点：查看 / 轮换导入链接
scripts/reality-dest-check.sh # 伪装站健康检查与自动切换
scripts/install-xray-ws.sh   # 旧方案：安装 VLESS + WS + TLS
scripts/update-vless-uuid.sh # 旧方案：轮换 WS 节点 UUID
scripts/ipv6-mss-clamp.sh    # 可选：6in4 隧道 TCP MSS 夹紧
templates/config.json        # Reality + Vision 服务端配置模板（listen ::）
templates/99-network-optimize.conf
templates/nginx.conf
templates/nginx-site.conf    # Reality 占用 443 后，nginx 只听 80
templates/sshd-hardening.conf
templates/reality-dest-check.service
templates/reality-dest-check.timer
templates/ipv6-mss-clamp.service
```

密钥、UUID、证书不会放进仓库。`templates/config.json` 里是占位符。

## 推荐部署：VLESS + Reality + Vision

Xray 监听 **`::`:443**（IPv4 + IPv6 双栈）。未通过校验的握手会转到伪装站 `dl.google.com`，看起来像在访问 Google。不要把 Reality 的 SNI 改成自己的域名。

### 1. 安装 Xray

```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```

### 2. 生成密钥

```bash
xray uuid
xray x25519
openssl rand -hex 4
```

把 UUID、`PrivateKey`、shortId 填进 `templates/config.json`，复制到：

`/usr/local/etc/xray/config.json`

官方安装脚本默认以 `nobody` 运行 Xray，配置文件权限用 **644**，否则服务起不来。

客户端用 `xray x25519` 输出的 **Password (PublicKey)**，不要用私钥。换一台机器就重新生成一套，不要把旧机密钥原样拷过去。

### 3. 内核与 nginx

```bash
cp templates/99-network-optimize.conf /etc/sysctl.d/
sysctl -p /etc/sysctl.d/99-network-optimize.conf
```

只跑 Reality 时 **不必装 nginx**。以前 WS+TLS 才需要它；nginx 停掉后记得把 acme.sh 的 PreHook `systemctl stop nginx` 改成 `true`，避免证书续期把无关服务停掉。若仍保留 nginx，不要再听 443：

```bash
cp templates/nginx.conf /etc/nginx/nginx.conf
cp templates/nginx-site.conf /etc/nginx/conf.d/YOUR_DOMAIN.conf
nginx -t && systemctl reload nginx
```

### 4. 启动

```bash
xray run -test -config /usr/local/etc/xray/config.json
systemctl enable --now xray
systemctl restart xray
```

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # 或你的 SSH 端口
ufw allow 443/tcp
ufw enable
```

80 可以不开放。SSH 建议改非 22 端口；公钥可用后再关密码登录，见 `templates/sshd-hardening.conf`。需要同时留 root 密码时，把 `PasswordAuthentication` / `PermitRootLogin` 都设为 `yes`。

### 5. 查看 / 更新导入链接

把脚本放到服务器：

```bash
cp scripts/xray.sh /root/xray.sh
chmod 700 /root/xray.sh
ln -sfn /root/xray.sh /root/update-vless.sh
```

```bash
/root/xray.sh --show      # 打印 IPv4 链接；有全局 IPv6 时再打印一条备用
/root/xray.sh --update    # 换新 UUID 并重启（旧链接立即失效）
```

探测到的 IPv4 以当前公网为准，换 IP 后不用改脚本。IPv6 可用环境变量 `XRAY_ADDRESS_V6` 覆盖。

链接默认指纹是 **firefox**。V2rayU 上 **不要用 chrome**（会走 X25519MLKEM768，Reality 校验失败，日志里是 `EOF`）。

### 6. 伪装站健康检查

每 10 分钟检测当前 `dest` 是否还能 TLS1.3 + HTTP/2。连续失败则自动换成候选站点（Google / Microsoft / Samsung 等），并保留原来的 `serverNames`，**已导入的客户端 SNI 一般不用改**。

```bash
cp scripts/reality-dest-check.sh /usr/local/sbin/reality-dest-check.sh
chmod 700 /usr/local/sbin/reality-dest-check.sh
cp templates/reality-dest-check.service templates/reality-dest-check.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now reality-dest-check.timer
```

```bash
journalctl -u reality-dest-check -n 50 --no-pager
systemctl list-timers reality-dest-check.timer
```

## 客户端（V2rayU 5.x）

- 核心选 **Xray**，不要 Auto
- 安全：reality
- flow：`xtls-rprx-vision`
- 传输：tcp
- SNI / serverName：`dl.google.com`
- TLS 指纹：`firefox`
- SpiderX：`/`
- 关掉 Mux / 多路复用
- 关掉「允许不安全连接」
- 用 **系统代理 / PAC**，不要开 TUN（V2rayU 5 的 TUN 走 sing-box，Vision 容易失败）

导入示例（把占位符换成自己的值）：

```text
vless://YOUR_UUID@YOUR_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=dl.google.com&fp=firefox&pbk=YOUR_PUBLIC_KEY&sid=YOUR_SHORT_ID&spx=%2F&type=tcp#Reality-Vision
```

IPv6 地址必须加方括号：

```text
vless://YOUR_UUID@[YOUR_IPV6]:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=dl.google.com&fp=firefox&pbk=YOUR_PUBLIC_KEY&sid=YOUR_SHORT_ID&spx=%2F&type=tcp#Reality-Vision-IPv6
```

两条可以同时留在客户端里：IPv4 日常用，IPv6 在 IPv4 被墙时切换。客户端测到的 500–700ms 多半是穿过 Reality 访问探测网址的网页延迟，不是 ICMP ping。

## 实践备注

- **换机就换密钥。** 新 VPS 重新 `xray uuid` / `xray x25519` / `openssl rand -hex 4`。
- **自己的域名不会更隐匿。** Reality 的 SNI 继续用伪装站（如 `dl.google.com`）。域名最多方便换 IP 后改 DNS。
- **IPv4 被墙很常见。** 服务还在、国内直连 443 超时，就是 IP 被干扰。换 IP 或换一家 ASN，比改指纹有用。
- **优先原生 IPv6。** 多数欧洲 VPS 给的是真实 `/64`。把 IPv4 套进 SIT/6in4 隧道（MTU 1480）容易卡顿；若只能用这种隧道，装 MSS 夹紧：

```bash
cp scripts/ipv6-mss-clamp.sh /usr/local/sbin/ipv6-mss-clamp.sh
chmod 755 /usr/local/sbin/ipv6-mss-clamp.sh
cp templates/ipv6-mss-clamp.service /etc/systemd/system/
systemctl enable --now ipv6-mss-clamp.service
```

- **第二台机器当备份。** 不同国家、不同 ASN，比在同一家反复付费换 IP 稳。1 核 1–2GB 内存足够跑 Xray。
- **防火墙只放行 SSH 和 443。** Reality 不占用 80。

## 旧方案：VLESS + WS + TLS

需要自己的域名和证书，nginx 反代 WebSocket。官方已不推荐 WS。

```bash
sudo bash scripts/install-xray-ws.sh vpn.example.com
```

轮换 UUID：

```bash
DOMAIN=vpn.example.com WS_PATH=/your-path sudo bash scripts/update-vless-uuid.sh
```

## 旧版一键菜单

```bash
curl -O https://raw.githubusercontent.com/cjreborn314/xray-plus/main/xray-plus.sh
chmod +x xray-plus.sh
sudo bash xray-plus.sh
```

支持 VMESS / VLESS / Trojan 等多种组合，以及 Nginx 伪装站点。TLS 模式需要域名已解析到服务器。

| 参数 | 说明 |
|------|------|
| `menu` | 交互菜单（默认） |
| `update` | 更新 Xray |
| `uninstall` | 卸载 |
| `start` / `restart` / `stop` | 启停 |
| `showInfo` / `showLog` | 配置 / 日志 |
| `node_manager` | 节点管理（主要面向 WS） |

## 相关路径

- Xray 配置：`/usr/local/etc/xray/config.json`
- Xray 程序：`/usr/local/bin/xray`
- Reality 链接脚本：`/root/xray.sh`
- 伪装站检查：`/usr/local/sbin/reality-dest-check.sh`
- Nginx：`/etc/nginx/nginx.conf`、`/etc/nginx/conf.d/`

## License

`xray-plus.sh` 来源标注为 [hijk](https://hijk.art)。其余脚本按本仓库约定使用。
