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
templates/config.json        # Reality + Vision 服务端配置模板
templates/99-network-optimize.conf
templates/nginx.conf
templates/nginx-site.conf    # Reality 占用 443 后，nginx 只听 80
templates/sshd-hardening.conf
templates/reality-dest-check.service
templates/reality-dest-check.timer
```

密钥、UUID、证书不会放进仓库。`templates/config.json` 里是占位符。

## 推荐部署：VLESS + Reality + Vision

Xray 直接监听 **443**。未通过校验的握手会转到伪装站 `dl.google.com`，看起来像在访问 Google。

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

客户端用 `xray x25519` 输出的 **Password (PublicKey)**，不要用私钥。

### 3. 内核与 nginx

```bash
cp templates/99-network-optimize.conf /etc/sysctl.d/
sysctl -p /etc/sysctl.d/99-network-optimize.conf

# Reality 占用 443 后，nginx 不要再听 443
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

放行 443/tcp。SSH 建议改非 22 端口后再关密码登录，见 `templates/sshd-hardening.conf`。

### 5. 查看 / 更新导入链接

把脚本放到服务器：

```bash
cp scripts/xray.sh /root/xray.sh
chmod 700 /root/xray.sh
ln -sfn /root/xray.sh /root/update-vless.sh
```

```bash
/root/xray.sh --show      # 只打印当前链接
/root/xray.sh --update    # 换新 UUID 并重启（旧链接立即失效）
```

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
- Nginx：`/etc/nginx/nginx.conf`、`/etc/nginx/conf.d/`

## License

`xray-plus.sh` 来源标注为 [hijk](https://hijk.art)。其余脚本按本仓库约定使用。
