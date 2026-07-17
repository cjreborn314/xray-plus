# xray-plus

基于 Bash 的 Xray 一键安装与管理脚本，支持多种协议组合、Nginx 伪装站点、BBR 加速，以及 VLESS+WS+TLS 节点管理。

## 功能

- 安装多种协议：
  - VMESS / VMESS+mKCP / VMESS+TCP+TLS / VMESS+WS+TLS
  - VLESS+mKCP / VLESS+TCP+TLS / VLESS+WS+TLS / VLESS+TCP+XTLS
  - Trojan / Trojan+XTLS
- 自动安装与配置 Nginx（网站伪装）
- 可选安装 BBR
- 更新 / 卸载 / 启停 Xray
- 查看配置与日志
- VLESS+WS+TLS 节点管理（链接导出、UUID 重置、二维码、端口检查等）

## 系统要求

- 需要 **root** 权限
- 支持 `yum` 或 `apt` 的 Linux 发行版
- 依赖 `systemctl`
- TLS / XTLS 相关模式需要：
  1. 一个伪装域名
  2. 域名 DNS 已解析到当前服务器 IP

## 快速开始

```bash
# 下载脚本
curl -O https://raw.githubusercontent.com/cjreborn314/xray-plus/main/xray-plus.sh
chmod +x xray-plus.sh

# 以 root 运行（交互菜单）
sudo bash xray-plus.sh
```

或直接：

```bash
sudo bash xray-plus.sh menu
```

## 命令行参数

```bash
sudo bash xray-plus.sh [menu|update|uninstall|start|restart|stop|showInfo|showLog|node_manager]
```

| 参数 | 说明 |
|------|------|
| `menu` | 打开交互菜单（默认） |
| `update` | 更新 Xray |
| `uninstall` | 卸载 Xray |
| `start` / `restart` / `stop` | 启动 / 重启 / 停止 |
| `showInfo` | 查看配置信息 |
| `showLog` | 查看日志 |
| `node_manager` | 打开节点管理（当前主要支持 VLESS+WS+TLS） |

## 菜单概览

1. 安装 Xray-VMESS  
2. 安装 Xray-VMESS+mKCP  
3. 安装 Xray-VMESS+TCP+TLS  
4. 安装 Xray-VMESS+WS+TLS（推荐）  
5. 安装 Xray-VLESS+mKCP  
6. 安装 Xray-VLESS+TCP+TLS  
7. 安装 Xray-VLESS+WS+TLS（可过 CDN）  
8. 安装 Xray-VLESS+TCP+XTLS（推荐）  
9. 安装 Trojan（推荐）  
10. 安装 Trojan+XTLS（推荐）  
11. 更新 Xray  
12. 卸载 Xray  
13–15. 启动 / 重启 / 停止  
16–17. 查看配置 / 日志  
18. Xray 节点管理  
0. 退出  

## 相关路径

- Xray 配置：`/usr/local/etc/xray/config.json`
- Xray 程序：`/usr/local/bin/xray`
- Nginx 站点目录：`/etc/nginx/conf.d/`（宝塔环境为 `/www/server/panel/vhost/nginx/`）

## 注意事项

- 请仅在合法合规的前提下使用，遵守当地法律法规与服务条款。
- 伪装站点依赖脚本内置的反代源站；若无法打开伪装域名，可自行更换源站地址。
- 节点管理的自动链接导出、二维码目前主要面向 **VLESS + WS + TLS**。

## License

本仓库脚本按原作者标注与仓库约定使用。原脚本标注来源：hijk。
