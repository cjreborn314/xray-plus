#!/bin/bash
# xray一键安装脚本
# Author: hijk<https://hijk.art>


RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

# 以下网站是随机从Google上找到的无广告小说网站，不喜欢请改成其他网址，以http或https开头
# 搭建好后无法打开伪装域名，可能是反代小说网站挂了，请在网站留言，或者Github发issue，以便替换新的网站
SITES=(
http://www.zhuizishu.com/
http://xs.56dyc.com/
#http://www.xiaoshuosk.com/
#https://www.quledu.net/
http://www.ddxsku.com/
http://www.biqu6.com/
https://www.wenshulou.cc/
#http://www.auutea.com/
http://www.55shuba.com/
http://www.39shubao.com/
https://www.23xsw.cc/
#https://www.huanbige.com/
https://www.jueshitangmen.info/
https://www.zhetian.org/
http://www.bequgexs.com/
http://www.tjwl.com/
)

CONFIG_FILE="/usr/local/etc/xray/config.json"
OS=`hostnamectl | grep -i system | cut -d: -f2`

V6_PROXY=""
IP=`curl -sL -4 ip.sb`
if [[ "$?" != "0" ]]; then
    IP=`curl -sL -6 ip.sb`
    V6_PROXY="https://gh.hijk.art/"
fi

BT="false"
NGINX_CONF_PATH="/etc/nginx/conf.d/"
res=`which bt 2>/dev/null`
if [[ "$res" != "" ]]; then
    BT="true"
    NGINX_CONF_PATH="/www/server/panel/vhost/nginx/"
fi

VLESS="false"
TROJAN="false"
TLS="false"
WS="false"
XTLS="false"
KCP="false"

checkSystem() {
    result=$(id | awk '{print $1}')
    if [[ $result != "uid=0(root)" ]]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    res=`which yum 2>/dev/null`
    if [[ "$?" != "0" ]]; then
        res=`which apt 2>/dev/null`
        if [[ "$?" != "0" ]]; then
            colorEcho $RED " 不受支持的Linux系统"
            exit 1
        fi
        PMT="apt"
        CMD_INSTALL="apt install -y "
        CMD_REMOVE="apt remove -y "
        CMD_UPGRADE="apt update; apt upgrade -y; apt autoremove -y"
    else
        PMT="yum"
        CMD_INSTALL="yum install -y "
        CMD_REMOVE="yum remove -y "
        CMD_UPGRADE="yum update -y"
    fi
    res=`which systemctl 2>/dev/null`
    if [[ "$?" != "0" ]]; then
        colorEcho $RED " 系统版本过低，请升级到最新版本"
        exit 1
    fi
}

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

configNeedNginx() {
    local ws=`grep wsSettings $CONFIG_FILE`
    if [[ -z "$ws" ]]; then
        echo no
        return
    fi
    echo yes
}

needNginx() {
    if [[ "$WS" = "false" ]]; then
        echo no
        return
    fi
    echo yes
}

status() {
    if [[ ! -f /usr/local/bin/xray ]]; then
        echo 0
        return
    fi
    if [[ ! -f $CONFIG_FILE ]]; then
        echo 1
        return
    fi
    port=`grep port $CONFIG_FILE| head -n 1| cut -d: -f2| tr -d \",' '`
    res=`ss -nutlp| grep ${port} | grep -i xray`
    if [[ -z "$res" ]]; then
        echo 2
        return
    fi

    if [[ `configNeedNginx` != "yes" ]]; then
        echo 3
    else
        res=`ss -nutlp|grep -i nginx`
        if [[ -z "$res" ]]; then
            echo 4
        else
            echo 5
        fi
    fi
}

statusText() {
    res=`status`
    case $res in
        2)
            echo -e ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}
            ;;
        3)
            echo -e ${GREEN}已安装${PLAIN} ${GREEN}Xray正在运行${PLAIN}
            ;;
        4)
            echo -e ${GREEN}已安装${PLAIN} ${GREEN}Xray正在运行${PLAIN}, ${RED}Nginx未运行${PLAIN}
            ;;
        5)
            echo -e ${GREEN}已安装${PLAIN} ${GREEN}Xray正在运行, Nginx正在运行${PLAIN}
            ;;
        *)
            echo -e ${RED}未安装${PLAIN}
            ;;
    esac
}

normalizeVersion() {
    if [ -n "$1" ]; then
        case "$1" in
            v*)
                echo "$1"
            ;;
            http*)
                echo "v1.4.2"
            ;;
            *)
                echo "v$1"
            ;;
        esac
    else
        echo ""
    fi
}

# 1: new Xray. 0: no. 1: yes. 2: not installed. 3: check failed.
getVersion() {
    VER=`/usr/local/bin/xray version|head -n1 | awk '{print $2}'`
    RETVAL=$?
    CUR_VER="$(normalizeVersion "$(echo "$VER" | head -n 1 | cut -d " " -f2)")"
    TAG_URL="${V6_PROXY}https://api.github.com/repos/XTLS/Xray-core/releases/latest"
    NEW_VER="$(normalizeVersion "$(curl -s "${TAG_URL}" --connect-timeout 10| grep 'tag_name' | cut -d\" -f4)")"

    if [[ $? -ne 0 ]] || [[ $NEW_VER == "" ]]; then
        colorEcho $RED " 检查Xray版本信息失败，请检查网络"
        return 3
    elif [[ $RETVAL -ne 0 ]];then
        return 2
    elif [[ $NEW_VER != $CUR_VER ]];then
        return 1
    fi
    return 0
}

archAffix(){
    case "$(uname -m)" in
        i686|i386)
            echo '32'
        ;;
        x86_64|amd64)
            echo '64'
        ;;
        armv5tel)
            echo 'arm32-v5'
        ;;
        armv6l)
            echo 'arm32-v6'
        ;;
        armv7|armv7l)
            echo 'arm32-v7a'
        ;;
        armv8|aarch64)
            echo 'arm64-v8a'
        ;;
        mips64le)
            echo 'mips64le'
        ;;
        mips64)
            echo 'mips64'
        ;;
        mipsle)
            echo 'mips32le'
        ;;
        mips)
            echo 'mips32'
        ;;
        ppc64le)
            echo 'ppc64le'
        ;;
        ppc64)
            echo 'ppc64'
        ;;
        ppc64le)
            echo 'ppc64le'
        ;;
        riscv64)
            echo 'riscv64'
        ;;
        s390x)
            echo 's390x'
        ;;
        *)
            colorEcho $RED " 不支持的CPU架构！"
            exit 1
        ;;
    esac

	return 0
}

getData() {
    if [[ "$TLS" = "true" || "$XTLS" = "true" ]]; then
        echo ""
        echo " Xray一键脚本，运行之前请确认如下条件已经具备："
        colorEcho ${YELLOW} "  1. 一个伪装域名"
        colorEcho ${YELLOW} "  2. 伪装域名DNS解析指向当前服务器ip（${IP}）"
        colorEcho ${BLUE} "  3. 如果/root目录下有 xray.pem 和 xray.key 证书密钥文件，无需理会条件2"
        echo " "
        read -p " 确认满足按y，按其他退出脚本：" answer
        if [[ "${answer,,}" != "y" ]]; then
            exit 0
        fi

        echo ""
        while true
        do
            read -p " 请输入伪装域名：" DOMAIN
            if [[ -z "${DOMAIN}" ]]; then
                colorEcho ${RED} " 域名输入错误，请重新输入！"
            else
                break
            fi
        done
        DOMAIN=${DOMAIN,,}
        colorEcho ${BLUE}  " 伪装域名(host)：$DOMAIN"

        echo ""
        if [[ -f ~/xray.pem && -f ~/xray.key ]]; then
            colorEcho ${BLUE}  " 检测到自有证书，将使用其部署"
            CERT_FILE="/usr/local/etc/xray/${DOMAIN}.pem"
            KEY_FILE="/usr/local/etc/xray/${DOMAIN}.key"
        else
            resolve=$(getent ahosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u)
            if ! printf '%s\n' "$resolve" | grep -Fxq "$IP"; then
                colorEcho ${BLUE} " ${DOMAIN} DNS解析结果：${resolve:-未获取到地址}"
                colorEcho ${RED} " 域名未解析到当前服务器IP(${IP})!"
                exit 1
            fi
        fi
    fi

    echo ""
    if [[ "$(needNginx)" = "no" ]]; then
        if [[ "$TLS" = "true" ]]; then
            read -p " 请输入xray监听端口[强烈建议443，默认443]：" PORT
            [[ -z "${PORT}" ]] && PORT=443
        else
            read -p " 请输入xray监听端口[100-65535的一个数字]：" PORT
            [[ -z "${PORT}" ]] && PORT=`shuf -i200-65000 -n1`
            if [[ "${PORT:0:1}" = "0" ]]; then
                colorEcho ${RED}  " 端口不能以0开头"
                exit 1
            fi
        fi
        colorEcho ${BLUE}  " xray端口：$PORT"
    else
        read -p " 请输入Nginx监听端口[100-65535的一个数字，默认443]：" PORT
        [[ -z "${PORT}" ]] && PORT=443
        if [ "${PORT:0:1}" = "0" ]; then
            colorEcho ${BLUE}  " 端口不能以0开头"
            exit 1
        fi
        colorEcho ${BLUE}  " Nginx端口：$PORT"
        XPORT=`shuf -i10000-65000 -n1`
    fi

    if [[ "$KCP" = "true" ]]; then
        echo ""
        colorEcho $BLUE " 请选择伪装类型："
        echo "   1) 无"
        echo "   2) BT下载"
        echo "   3) 视频通话"
        echo "   4) 微信视频通话"
        echo "   5) dtls"
        echo "   6) wiregard"
        read -p "  请选择伪装类型[默认：无]：" answer
        case $answer in
            2)
                HEADER_TYPE="utp"
                ;;
            3)
                HEADER_TYPE="srtp"
                ;;
            4)
                HEADER_TYPE="wechat-video"
                ;;
            5)
                HEADER_TYPE="dtls"
                ;;
            6)
                HEADER_TYPE="wireguard"
                ;;
            *)
                HEADER_TYPE="none"
                ;;
        esac
        colorEcho $BLUE " 伪装类型：$HEADER_TYPE"
        SEED=`cat /proc/sys/kernel/random/uuid`
    fi

    if [[ "$TROJAN" = "true" ]]; then
        echo ""
        read -p " 请设置trojan密码（不输则随机生成）:" PASSWORD
        [[ -z "$PASSWORD" ]] && PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
        colorEcho $BLUE " trojan密码：$PASSWORD"
    fi

    if [[ "$XTLS" = "true" ]]; then
        echo ""
        colorEcho $BLUE " 请选择流控模式:" 
        echo -e "   1) xtls-rprx-direct [$RED推荐$PLAIN]"
        echo "   2) xtls-rprx-origin"
        read -p "  请选择流控模式[默认:direct]" answer
        [[ -z "$answer" ]] && answer=1
        case $answer in
            1)
                FLOW="xtls-rprx-direct"
                ;;
            2)
                FLOW="xtls-rprx-origin"
                ;;
            *)
                colorEcho $RED " 无效选项，使用默认的xtls-rprx-direct"
                FLOW="xtls-rprx-direct"
                ;;
        esac
        colorEcho $BLUE " 流控模式：$FLOW"
    fi

    if [[ "${WS}" = "true" ]]; then
        echo ""
        while true
        do
            read -p " 请输入伪装路径，以/开头(不懂请直接回车)：" WSPATH
            if [[ -z "${WSPATH}" ]]; then
                len=`shuf -i5-12 -n1`
                ws=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $len | head -n 1`
                WSPATH="/$ws"
                break
            elif [[ "${WSPATH:0:1}" != "/" ]]; then
                colorEcho ${RED}  " 伪装路径必须以/开头！"
            elif [[ "${WSPATH}" = "/" ]]; then
                colorEcho ${RED}   " 不能使用根路径！"
            else
                break
            fi
        done
        colorEcho ${BLUE}  " ws路径：$WSPATH"
    fi

    if [[ "$TLS" = "true" || "$XTLS" = "true" ]]; then
        echo ""
        colorEcho $BLUE " 请选择伪装站类型:"
        echo "   1) 静态网站(位于/usr/share/nginx/html)"
        echo "   2) 小说站(随机选择)"
        echo "   3) 美女站(https://imeizi.me)"
        echo "   4) 高清壁纸站(https://bing.imeizi.me)"
        echo "   5) 自定义反代站点(需以http或者https开头)"
        read -p "  请选择伪装网站类型[默认:高清壁纸站]" answer
        if [[ -z "$answer" ]]; then
            PROXY_URL="https://bing.imeizi.me"
        else
            case $answer in
            1)
                PROXY_URL=""
                ;;
            2)
                len=${#SITES[@]}
                ((len--))
                while true
                do
                    index=`shuf -i0-${len} -n1`
                    PROXY_URL=${SITES[$index]}
                    host=`echo ${PROXY_URL} | cut -d/ -f3`
                    ip=`curl -sL http://ip-api.com/json/${host}`
                    res=`echo -n ${ip} | grep ${host}`
                    if [[ "${res}" = "" ]]; then
                        echo "$ip $host" >> /etc/hosts
                        break
                    fi
                done
                ;;
            3)
                PROXY_URL="https://imeizi.me"
                ;;
            4)
                PROXY_URL="https://bing.imeizi.me"
                ;;
            5)
                read -p " 请输入反代站点(以http或者https开头)：" PROXY_URL
                if [[ -z "$PROXY_URL" ]]; then
                    colorEcho $RED " 请输入反代网站！"
                    exit 1
                elif [[ "${PROXY_URL:0:4}" != "http" ]]; then
                    colorEcho $RED " 反代网站必须以http或https开头！"
                    exit 1
                fi
                ;;
            *)
                colorEcho $RED " 请输入正确的选项！"
                exit 1
            esac
        fi
        REMOTE_HOST=`echo ${PROXY_URL} | cut -d/ -f3`
        colorEcho $BLUE " 伪装网站：$PROXY_URL"

        echo ""
        colorEcho $BLUE "  是否允许搜索引擎爬取网站？[默认：不允许]"
        echo "    y)允许，会有更多ip请求网站，但会消耗一些流量，vps流量充足情况下推荐使用"
        echo "    n)不允许，爬虫不会访问网站，访问ip比较单一，但能节省vps流量"
        read -p "  请选择：[y/n]" answer
        if [[ -z "$answer" ]]; then
            ALLOW_SPIDER="n"
        elif [[ "${answer,,}" = "y" ]]; then
            ALLOW_SPIDER="y"
        else
            ALLOW_SPIDER="n"
        fi
        colorEcho $BLUE " 允许搜索引擎：$ALLOW_SPIDER"
    fi

    echo ""
    read -p " 是否安装BBR(默认安装)?[y/n]:" NEED_BBR
    [[ -z "$NEED_BBR" ]] && NEED_BBR=y
    [[ "$NEED_BBR" = "Y" ]] && NEED_BBR=y
    colorEcho $BLUE " 安装BBR：$NEED_BBR"
}

installNginx() {
    echo ""
    colorEcho $BLUE " 安装nginx..."
    if [[ "$BT" = "false" ]]; then
        if [[ "$PMT" = "yum" ]]; then
            $CMD_INSTALL epel-release
            if [[ "$?" != "0" ]]; then
                echo '[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true' > /etc/yum.repos.d/nginx.repo
            fi
        fi
        $CMD_INSTALL nginx
        if [[ "$?" != "0" ]]; then
            colorEcho $RED " Nginx安装失败，请到 https://hijk.art 反馈"
            exit 1
        fi
        systemctl enable nginx
    else
        res=`which nginx 2>/dev/null`
        if [[ "$?" != "0" ]]; then
            colorEcho $RED " 您安装了宝塔，请在宝塔后台安装nginx后再运行本脚本"
            exit 1
        fi
    fi
}

startNginx() {
    if [[ "$BT" = "false" ]]; then
        systemctl start nginx
    else
        nginx -c /www/server/nginx/conf/nginx.conf
    fi
}

stopNginx() {
    if [[ "$BT" = "false" ]]; then
        systemctl stop nginx
    else
        res=`ps aux | grep -i nginx`
        if [[ "$res" != "" ]]; then
            nginx -s stop
        fi
    fi
}

getCert() {
    mkdir -p /usr/local/etc/xray
    if [[ -z ${CERT_FILE+x} ]]; then
        stopNginx
        systemctl stop xray
        res=`netstat -ntlp| grep -E ':80 |:443 '`
        if [[ "${res}" != "" ]]; then
            colorEcho ${RED}  " 其他进程占用了80或443端口，请先关闭再运行一键脚本"
            echo " 端口占用信息如下："
            echo ${res}
            exit 1
        fi

        $CMD_INSTALL socat openssl
        if [[ "$PMT" = "yum" ]]; then
            $CMD_INSTALL cronie
            systemctl start crond
            systemctl enable crond
        else
            $CMD_INSTALL cron
            systemctl start cron
            systemctl enable cron
        fi
        curl -sL https://get.acme.sh | sh -s email="${ACME_EMAIL:-admin@${DOMAIN}}"
        source ~/.bashrc
        ~/.acme.sh/acme.sh  --upgrade  --auto-upgrade
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [[ "$BT" = "false" ]]; then
            ~/.acme.sh/acme.sh   --issue -d $DOMAIN --keylength ec-256 --pre-hook "systemctl stop nginx" --post-hook "systemctl restart nginx"  --standalone
        else
            ~/.acme.sh/acme.sh   --issue -d $DOMAIN --keylength ec-256 --pre-hook "nginx -s stop || { echo -n ''; }" --post-hook "nginx -c /www/server/nginx/conf/nginx.conf || { echo -n ''; }"  --standalone
        fi
        [[ -f ~/.acme.sh/${DOMAIN}_ecc/ca.cer ]] || {
            colorEcho $RED " 获取证书失败，请复制上面的红色文字到 https://hijk.art 反馈"
            exit 1
        }
        CERT_FILE="/usr/local/etc/xray/${DOMAIN}.pem"
        KEY_FILE="/usr/local/etc/xray/${DOMAIN}.key"
        ~/.acme.sh/acme.sh  --install-cert -d $DOMAIN --ecc \
            --key-file       $KEY_FILE  \
            --fullchain-file $CERT_FILE \
            --reloadcmd     "service nginx force-reload"
        [[ -f $CERT_FILE && -f $KEY_FILE ]] || {
            colorEcho $RED " 获取证书失败，请到 https://hijk.art 反馈"
            exit 1
        }
        chmod 644 "$CERT_FILE"
        chmod 600 "$KEY_FILE"
    else
        cp ~/xray.pem /usr/local/etc/xray/${DOMAIN}.pem
        cp ~/xray.key /usr/local/etc/xray/${DOMAIN}.key
    fi
}

configNginx() {
    local nginx_http2_listen=""

    mkdir -p /usr/share/nginx/html;
    if [[ "$ALLOW_SPIDER" = "n" ]]; then
        echo 'User-Agent: *' > /usr/share/nginx/html/robots.txt
        echo 'Disallow: /' >> /usr/share/nginx/html/robots.txt
        ROBOT_CONFIG="    location = /robots.txt {}"
    else
        ROBOT_CONFIG=""
    fi

    if [[ "$BT" = "false" ]]; then
        if [[ ! -f /etc/nginx/nginx.conf.bak ]]; then
            mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
        fi
        res=`id nginx 2>/dev/null`
        if [[ "$?" != "0" ]]; then
            user="www-data"
        else
            user="nginx"
        fi
        cat > /etc/nginx/nginx.conf<<-EOF
user $user;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;
    server_tokens off;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;
    gzip                on;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    # See http://nginx.org/en/docs/ngx_core_module.html#include
    # for more information.
    include /etc/nginx/conf.d/*.conf;
}
EOF
    fi

    if [[ "$PROXY_URL" = "" ]]; then
        action="try_files \$uri \$uri/ =404;"
        if [[ ! -f /usr/share/nginx/html/index.html ]]; then
            cat > /usr/share/nginx/html/index.html <<-'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Welcome</title>
</head>
<body>
  <h1>Welcome</h1>
  <p>The website is running.</p>
</body>
</html>
EOF
            chmod 644 /usr/share/nginx/html/index.html
        fi
    else
        action="proxy_ssl_server_name on;
        proxy_pass $PROXY_URL;
        proxy_set_header Accept-Encoding '';
        sub_filter \"$REMOTE_HOST\" \"$DOMAIN\";
        sub_filter_once off;"
    fi

    if [[ "$TLS" = "true" || "$XTLS" = "true" ]]; then
        mkdir -p ${NGINX_CONF_PATH}
        # VMESS+WS+TLS
        # VLESS+WS+TLS
        if [[ "$WS" = "true" ]]; then
            nginx_http2_listen=$(nginx_http2_listen_config "$PORT") || return 1
            cat > ${NGINX_CONF_PATH}${DOMAIN}.conf<<-EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    return 301 https://\$server_name:${PORT}\$request_uri;
}

server {
${nginx_http2_listen}
    server_name ${DOMAIN};
    charset utf-8;

    # ssl配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;
    ssl_ecdh_curve X25519:secp256r1:secp384r1;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    ssl_certificate $CERT_FILE;
    ssl_certificate_key $KEY_FILE;

    root /usr/share/nginx/html;
    location / {
        $action
    }
    $ROBOT_CONFIG

    location ${WSPATH} {
      access_log off;
      proxy_redirect off;
      proxy_pass http://127.0.0.1:${XPORT};
      proxy_http_version 1.1;
      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
      proxy_buffering off;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
        else
            # VLESS+TCP+TLS
            # VLESS+TCP+XTLS
            # trojan
            cat > ${NGINX_CONF_PATH}${DOMAIN}.conf<<-EOF
server {
    listen 80;
    listen [::]:80;
    listen 81 http2;
    server_name ${DOMAIN};
    root /usr/share/nginx/html;
    location / {
        $action
    }
    $ROBOT_CONFIG
}
EOF
        fi
    fi
}

setSelinux() {
    if [[ -s /etc/selinux/config ]] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

setFirewall() {
    # Ubuntu/Debian优先使用UFW，避免绕过UFW直接写入临时iptables规则。
    if [[ "$PMT" = "apt" ]] && command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -qi '^Status: active'; then
            ufw allow 80/tcp
            ufw allow "${PORT}/tcp"
            if [[ "$KCP" = "true" ]]; then
                ufw allow "${PORT}/udp"
            fi
            colorEcho "$GREEN" " UFW规则已更新：80/tcp、${PORT}/tcp"
        else
            colorEcho "$YELLOW" " 检测到UFW但当前未启用，脚本不会自动启用，以免锁死SSH"
            colorEcho "$YELLOW" " 请先放行SSH端口，再手动执行 ufw enable"
        fi
        return 0
    fi

    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-service=http
        if [[ "$PORT" = "443" ]]; then
            firewall-cmd --permanent --add-service=https
        else
            firewall-cmd --permanent --add-port="${PORT}/tcp"
        fi
        if [[ "$KCP" = "true" ]]; then
            firewall-cmd --permanent --add-port="${PORT}/udp"
        fi
        firewall-cmd --reload
        return $?
    fi

    colorEcho "$YELLOW" " 未检测到已启用的UFW或firewalld，请确认云平台/系统防火墙已放行80和${PORT}端口"
    return 0
}

installBBR() {
    local available=""
    local current=""

    INSTALL_BBR=false
    if [[ "$NEED_BBR" != "y" ]]; then
        return 0
    fi

    available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)
    if [[ " ${available} " != *" bbr "* ]] && command -v modprobe >/dev/null 2>&1; then
        modprobe tcp_bbr >/dev/null 2>&1 || true
        available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)
    fi

    if [[ " ${available} " != *" bbr "* ]]; then
        colorEcho "$YELLOW" " 当前内核不支持BBR，跳过配置"
        return 0
    fi

    mkdir -p /etc/sysctl.d
    cat > /etc/sysctl.d/99-bbr.conf<<-EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    chmod 644 /etc/sysctl.d/99-bbr.conf

    if ! sysctl --system; then
        colorEcho "$RED" " BBR配置加载失败，请检查 /etc/sysctl.d/99-bbr.conf"
        return 1
    fi

    current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [[ "$current" = "bbr" ]]; then
        colorEcho "$GREEN" " BBR已启用"
        return 0
    fi

    colorEcho "$RED" " BBR未能成功启用"
    return 1
}

installXray() {
    local tmp_dir="/tmp/xray"
    local zip_file="${tmp_dir}/xray.zip"
    local backup_bin=""
    local data_file=""

    rm -rf -- "$tmp_dir"
    mkdir -p "$tmp_dir" || {
        colorEcho "$RED" " 无法创建Xray临时目录"
        return 1
    }

    DOWNLOAD_LINK="${V6_PROXY}https://github.com/XTLS/Xray-core/releases/download/${NEW_VER}/Xray-linux-$(archAffix).zip"
    colorEcho "$BLUE" " 下载Xray: ${DOWNLOAD_LINK}"

    if ! curl --fail --location --retry 3 --retry-delay 2 --connect-timeout 15 \
        -H "Cache-Control: no-cache" \
        -o "$zip_file" \
        "$DOWNLOAD_LINK"; then
        colorEcho "$RED" " Xray下载失败，请检查服务器网络设置"
        return 1
    fi

    if ! unzip -tq "$zip_file" >/dev/null 2>&1; then
        colorEcho "$RED" " Xray压缩包损坏或格式不正确"
        return 1
    fi

    if ! unzip -oq "$zip_file" -d "$tmp_dir"; then
        colorEcho "$RED" " Xray解压失败"
        return 1
    fi

    if [[ ! -f "${tmp_dir}/xray" ]]; then
        colorEcho "$RED" " 解压后未找到Xray程序"
        return 1
    fi
    chmod 755 "${tmp_dir}/xray"

    if ! "${tmp_dir}/xray" version >/dev/null 2>&1; then
        colorEcho "$RED" " 下载的Xray程序无法运行，未替换现有版本"
        return 1
    fi

    mkdir -p /usr/local/etc/xray /usr/local/share/xray || return 1

    if [[ -x /usr/local/bin/xray ]]; then
        backup_bin="/usr/local/bin/xray.backup.$(date +%Y%m%d%H%M%S)"
        cp -a /usr/local/bin/xray "$backup_bin" || {
            colorEcho "$RED" " 现有Xray程序备份失败"
            return 1
        }
    fi

    systemctl stop xray >/dev/null 2>&1 || true

    if ! install -m 0755 "${tmp_dir}/xray" /usr/local/bin/xray; then
        [[ -n "$backup_bin" && -f "$backup_bin" ]] && cp -af "$backup_bin" /usr/local/bin/xray
        colorEcho "$RED" " Xray程序安装失败"
        return 1
    fi

    for data_file in geoip.dat geosite.dat; do
        if [[ -f "${tmp_dir}/${data_file}" ]]; then
            install -m 0644 "${tmp_dir}/${data_file}" "/usr/local/share/xray/${data_file}" || {
                colorEcho "$RED" " ${data_file}安装失败"
                return 1
            }
        fi
    done

    cat >/etc/systemd/system/xray.service<<-EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls https://hijk.art
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
User=root
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=3s
RestartPreventExitStatus=23
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    if ! systemctl daemon-reload || ! systemctl enable xray.service; then
        colorEcho "$RED" " Xray systemd服务配置失败"
        return 1
    fi

    rm -rf -- "$tmp_dir"
    colorEcho "$GREEN" " Xray程序安装完成"
    return 0
}

trojanConfig() {
    cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "trojan",
    "settings": {
      "clients": [
        {
          "password": "$PASSWORD"
        }
      ],
      "fallbacks": [
        {
              "alpn": "http/1.1",
              "dest": 80
          },
          {
              "alpn": "h2",
              "dest": 81
          }
      ]
    },
    "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
            "serverName": "$DOMAIN",
            "alpn": ["http/1.1", "h2"],
            "certificates": [
                {
                    "certificateFile": "$CERT_FILE",
                    "keyFile": "$KEY_FILE"
                }
            ]
        }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }]
}
EOF
}

trojanXTLSConfig() {
    cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "trojan",
    "settings": {
      "clients": [
        {
          "password": "$PASSWORD",
          "flow": "$FLOW"
        }
      ],
      "fallbacks": [
        {
              "alpn": "http/1.1",
              "dest": 80
          },
          {
              "alpn": "h2",
              "dest": 81
          }
      ]
    },
    "streamSettings": {
        "network": "tcp",
        "security": "xtls",
        "xtlsSettings": {
            "serverName": "$DOMAIN",
            "alpn": ["http/1.1", "h2"],
            "certificates": [
                {
                    "certificateFile": "$CERT_FILE",
                    "keyFile": "$KEY_FILE"
                }
            ]
        }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }]
}
EOF
}

vmessConfig() {
    local uuid="$(cat '/proc/sys/kernel/random/uuid')"
    local alterid=`shuf -i50-80 -n1`
    cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "vmess",
    "settings": {
      "clients": [
        {
          "id": "$uuid",
          "level": 1,
          "alterId": $alterid
        }
      ]
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }]
}
EOF
}

vmessKCPConfig() {
    local uuid="$(cat '/proc/sys/kernel/random/uuid')"
    local alterid=`shuf -i50-80 -n1`
    cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "vmess",
    "settings": {
      "clients": [
        {
          "id": "$uuid",
          "level": 1,
          "alterId": $alterid
        }
      ]
    },
    "streamSettings": {
        "network": "mkcp",
        "kcpSettings": {
            "uplinkCapacity": 100,
            "downlinkCapacity": 100,
            "congestion": true,
            "header": {
                "type": "$HEADER_TYPE"
            },
            "seed": "$SEED"
        }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }]
}
EOF
}

vmessTLSConfig() {
    local uuid="$(cat '/proc/sys/kernel/random/uuid')"
    cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "vmess",
    "settings": {
      "clients": [
        {
          "id": "$uuid",
          "level": 1,
          "alterId": 0
        }
      ],
      "disableInsecureEncryption": false
    },
    "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
            "serverName": "$DOMAIN",
            "alpn": ["http/1.1", "h2"],
            "certificates": [
                {
                    "certificateFile": "$CERT_FILE",
                    "keyFile": "$KEY_FILE"
                }
            ]
        }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }]
}
EOF
}

vmessWSConfig() {
    local uuid="$(cat '/proc/sys/kernel/random/uuid')"
    cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $XPORT,
    "listen": "127.0.0.1",
    "protocol": "vmess",
    "settings": {
      "clients": [
        {
          "id": "$uuid",
          "level": 1,
          "alterId": 0
        }
      ],
      "disableInsecureEncryption": false
    },
    "streamSettings": {
        "network": "ws",
        "wsSettings": {
            "path": "$WSPATH",
            "headers": {
                "Host": "$DOMAIN"
            }
        }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }]
}
EOF
}

vlessTLSConfig() {
    local uuid="$(cat '/proc/sys/kernel/random/uuid')"
    cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [
        {
          "id": "$uuid",
          "level": 0
        }
      ],
      "decryption": "none",
      "fallbacks": [
          {
              "alpn": "http/1.1",
              "dest": 80
          },
          {
              "alpn": "h2",
              "dest": 81
          }
      ]
    },
    "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
            "serverName": "$DOMAIN",
            "alpn": ["http/1.1", "h2"],
            "certificates": [
                {
                    "certificateFile": "$CERT_FILE",
                    "keyFile": "$KEY_FILE"
                }
            ]
        }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }]
}
EOF
}

vlessXTLSConfig() {
    local uuid="$(cat '/proc/sys/kernel/random/uuid')"
    cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [
        {
          "id": "$uuid",
          "flow": "$FLOW",
          "level": 0
        }
      ],
      "decryption": "none",
      "fallbacks": [
          {
              "alpn": "http/1.1",
              "dest": 80
          },
          {
              "alpn": "h2",
              "dest": 81
          }
      ]
    },
    "streamSettings": {
        "network": "tcp",
        "security": "xtls",
        "xtlsSettings": {
            "serverName": "$DOMAIN",
            "alpn": ["http/1.1", "h2"],
            "certificates": [
                {
                    "certificateFile": "$CERT_FILE",
                    "keyFile": "$KEY_FILE"
                }
            ]
        }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }]
}
EOF
}

vlessWSConfig() {
    local uuid="$(cat '/proc/sys/kernel/random/uuid')"
    cat > "$CONFIG_FILE"<<-EOF
{
  "inbounds": [{
    "port": $XPORT,
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": {
        "clients": [
            {
                "id": "$uuid",
                "level": 0
            }
        ],
        "decryption": "none"
    },
    "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
            "path": "$WSPATH",
            "headers": {
                "Host": "$DOMAIN"
            }
        }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }],
  "policy": {
    "levels": {
      "0": {
        "handshake": 4,
        "connIdle": 600,
        "uplinkOnly": 2,
        "downlinkOnly": 5
      }
    }
  }
}
EOF
}

vlessKCPConfig() {
    local uuid="$(cat '/proc/sys/kernel/random/uuid')"
    cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [
        {
          "id": "$uuid",
          "level": 0
        }
      ],
      "decryption": "none"
    },
    "streamSettings": {
        "streamSettings": {
            "network": "mkcp",
            "kcpSettings": {
                "uplinkCapacity": 100,
                "downlinkCapacity": 100,
                "congestion": true,
                "header": {
                    "type": "$HEADER_TYPE"
                },
                "seed": "$SEED"
            }
        }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }]
}
EOF
}

configXray() {
    mkdir -p /usr/local/xray
    if [[ "$TROJAN" = "true" ]]; then
        if [[ "$XTLS" = "true" ]]; then
            trojanXTLSConfig
        else
            trojanConfig
        fi
        return 0
    fi
    if [[ "$VLESS" = "false" ]]; then
        # VMESS + kcp
        if [[ "$KCP" = "true" ]]; then
            vmessKCPConfig
            return 0
        fi
        # VMESS
        if [[ "$TLS" = "false" ]]; then
            vmessConfig
        elif [[ "$WS" = "false" ]]; then
            # VMESS+TCP+TLS
            vmessTLSConfig
        # VMESS+WS+TLS
        else
            vmessWSConfig
        fi
    #VLESS
    else
        if [[ "$KCP" = "true" ]]; then
            vlessKCPConfig
            return 0
        fi
        # VLESS+TCP
        if [[ "$WS" = "false" ]]; then
            # VLESS+TCP+TLS
            if [[ "$XTLS" = "false" ]]; then
                vlessTLSConfig
            # VLESS+TCP+XTLS
            else
                vlessXTLSConfig
            fi
        # VLESS+WS+TLS
        else
            vlessWSConfig
        fi
    fi
}

install() {
    getData

    $PMT clean all
    [[ "$PMT" = "apt" ]] && $PMT update
    #echo $CMD_UPGRADE | bash
    $CMD_INSTALL wget vim unzip tar gcc openssl
    $CMD_INSTALL net-tools
    if [[ "$PMT" = "apt" ]]; then
        $CMD_INSTALL libssl-dev g++
    fi
    res=`which unzip 2>/dev/null`
    if [[ $? -ne 0 ]]; then
        colorEcho $RED " unzip安装失败，请检查网络"
        exit 1
    fi

    installNginx
    setFirewall
    if [[ "$TLS" = "true" || "$XTLS" = "true" ]]; then
        getCert
    fi
    configNginx || exit 1

    colorEcho $BLUE " 安装Xray..."
    getVersion
    RETVAL="$?"
    if [[ $RETVAL == 0 ]]; then
        colorEcho $BLUE " Xray最新版 ${CUR_VER} 已经安装"
    elif [[ $RETVAL == 3 ]]; then
        exit 1
    else
        colorEcho $BLUE " 安装Xray ${NEW_VER} ，架构$(archAffix)"
        installXray || exit 1
    fi

    configXray
    chmod 600 "$CONFIG_FILE" || {
        colorEcho "$RED" " 无法设置Xray配置文件权限"
        exit 1
    }

    validate_install_configs || exit 1

    setSelinux
    installBBR || colorEcho "$YELLOW" " BBR配置未完成，但不会阻止Xray安装"

    start || exit 1
    showInfo

    # VLESS+WS+TLS安装完成后自动导出节点信息
    node_after_install || exit 1

    bbrReboot
}

bbrReboot() {
    if [[ "${INSTALL_BBR}" == "true" ]]; then
        echo  
        echo " 为使BBR模块生效，系统将在30秒后重启"
        echo  
        echo -e " 您可以按 ctrl + c 取消重启，稍后输入 ${RED}reboot${PLAIN} 重启系统"
        sleep 30
        reboot
    fi
}

update() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " Xray未安装，请先安装！"
        return
    fi

    getVersion
    RETVAL="$?"
    if [[ $RETVAL == 0 ]]; then
        colorEcho $BLUE " Xray最新版 ${CUR_VER} 已经安装"
    elif [[ $RETVAL == 3 ]]; then
        exit 1
    else
        colorEcho $BLUE " 安装Xray ${NEW_VER} ，架构$(archAffix)"
        installXray || return 1
        validate_install_configs || return 1
        start || return 1

        colorEcho $GREEN " 最新版Xray安装成功！"
    fi
}

uninstall() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " Xray未安装，请先安装！"
        return
    fi

    echo ""
    read -p " 确定卸载Xray？[y/n]：" answer
    if [[ "${answer,,}" = "y" ]]; then
        domain=`grep Host $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
        if [[ "$domain" = "" ]]; then
            domain=`grep serverName $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
        fi
        
        stop
        systemctl disable xray
        rm -rf /etc/systemd/system/xray.service
        rm -rf /usr/local/bin/xray
        rm -rf /usr/local/etc/xray

        if [[ "$BT" = "false" ]]; then
            systemctl disable nginx
            $CMD_REMOVE nginx
            if [[ "$PMT" = "apt" ]]; then
                $CMD_REMOVE nginx-common
            fi
            rm -rf /etc/nginx/nginx.conf
            if [[ -f /etc/nginx/nginx.conf.bak ]]; then
                mv /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf
            fi
        fi
        if [[ "$domain" != "" ]]; then
            rm -rf ${NGINX_CONF_PATH}${domain}.conf
        fi
        [[ -f ~/.acme.sh/acme.sh ]] && ~/.acme.sh/acme.sh --uninstall
        colorEcho $GREEN " Xray卸载成功"
    fi
}

start() {
    local current_status=""
    local xray_port=""

    current_status=$(status)
    if [[ $current_status -lt 2 ]]; then
        colorEcho "$RED" " Xray未安装，请先安装！"
        return 1
    fi

    stopNginx >/dev/null 2>&1 || true
    if ! startNginx; then
        colorEcho "$RED" " Nginx启动命令执行失败"
        return 1
    fi

    sleep 1
    if [[ "$BT" = "false" ]]; then
        if ! systemctl is-active --quiet nginx; then
            colorEcho "$RED" " Nginx启动后未保持运行，请执行 journalctl -u nginx -n 100 查看日志"
            return 1
        fi
    elif ! pgrep -x nginx >/dev/null 2>&1; then
        colorEcho "$RED" " Nginx启动后未检测到进程"
        return 1
    fi

    if ! systemctl restart xray; then
        colorEcho "$RED" " Xray重启命令执行失败"
        return 1
    fi

    sleep 1
    if ! systemctl is-active --quiet xray; then
        colorEcho "$RED" " Xray启动后未保持运行，请执行 journalctl -u xray -n 100 查看日志"
        return 1
    fi

    xray_port=$(grep -m1 '"port"' "$CONFIG_FILE" | grep -oE '[0-9]+' | head -n 1)
    if [[ -z "$xray_port" ]]; then
        colorEcho "$RED" " 无法从配置文件读取Xray监听端口"
        return 1
    fi

    if ! ss -lntp | awk -v port="$xray_port" '$4 ~ (":" port "$") && tolower($0) ~ /xray/ {found=1} END {exit !found}'; then
        colorEcho "$RED" " Xray没有监听预期端口 ${xray_port}"
        return 1
    fi

    colorEcho "$GREEN" " Nginx和Xray启动成功"
    return 0
}

stop() {
    stopNginx
    systemctl stop xray
    colorEcho $BLUE " Xray停止成功"
}


restart() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " Xray未安装，请先安装！"
        return
    fi

    stop
    start
}


getConfigFileInfo() {
    vless="false"
    tls="false"
    ws="false"
    xtls="false"
    trojan="false"
    protocol="VMess"
    kcp="false"

    uid=`grep id $CONFIG_FILE | head -n1| cut -d: -f2 | tr -d \",' '`
    alterid=`grep alterId $CONFIG_FILE  | cut -d: -f2 | tr -d \",' '`
    network=`grep network $CONFIG_FILE  | tail -n1| cut -d: -f2 | tr -d \",' '`
    [[ -z "$network" ]] && network="tcp"
    domain=`grep serverName $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    if [[ "$domain" = "" ]]; then
        domain=`grep Host $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
        if [[ "$domain" != "" ]]; then
            ws="true"
            tls="true"
            wspath=`grep path $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
        fi
    else
        tls="true"
    fi
    if [[ "$ws" = "true" ]]; then
        port=`grep -i ssl $NGINX_CONF_PATH${domain}.conf| head -n1 | awk '{print $2}'`
    else
        port=`grep port $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    fi
    res=`grep -i kcp $CONFIG_FILE`
    if [[ "$res" != "" ]]; then
        kcp="true"
        type=`grep header -A 3 $CONFIG_FILE | grep 'type' | cut -d: -f2 | tr -d \",' '`
        seed=`grep seed $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    fi

    vmess=`grep vmess $CONFIG_FILE`
    if [[ "$vmess" = "" ]]; then
        trojan=`grep trojan $CONFIG_FILE`
        if [[ "$trojan" = "" ]]; then
            vless="true"
            protocol="VLESS"
        else
            trojan="true"
            password=`grep password $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
            protocol="trojan"
        fi
        tls="true"
        encryption="none"
        xtls=`grep xtlsSettings $CONFIG_FILE`
        if [[ "$xtls" != "" ]]; then
            xtls="true"
            flow=`grep flow $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
        else
            flow="无"
        fi
    fi
}

outputVmess() {
    raw="{
  \"v\":\"2\",
  \"ps\":\"\",
  \"add\":\"$IP\",
  \"port\":\"${port}\",
  \"id\":\"${uid}\",
  \"aid\":\"$alterid\",
  \"net\":\"tcp\",
  \"type\":\"none\",
  \"host\":\"\",
  \"path\":\"\",
  \"tls\":\"\"
}"
    link=`echo -n ${raw} | base64 -w 0`
    link="vmess://${link}"

    echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
    echo -e "   ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
    echo -e "   ${BLUE}加密方式(security)：${PLAIN} ${RED}auto${PLAIN}"
    echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
    echo  
    echo -e "   ${BLUE}vmess链接:${PLAIN} $RED$link$PLAIN"
}

outputVmessKCP() {
    echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
    echo -e "   ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
    echo -e "   ${BLUE}加密方式(security)：${PLAIN} ${RED}auto${PLAIN}"
    echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}"
    echo -e "   ${BLUE}伪装类型(type)：${PLAIN} ${RED}${type}${PLAIN}"
    echo -e "   ${BLUE}mkcp seed：${PLAIN} ${RED}${seed}${PLAIN}" 
}

outputTrojan() {
    if [[ "$xtls" = "true" ]]; then
        echo -e "   ${BLUE}IP/域名(address): ${PLAIN} ${RED}${domain}${PLAIN}"
        echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
        echo -e "   ${BLUE}密码(password)：${PLAIN}${RED}${password}${PLAIN}"
        echo -e "   ${BLUE}流控(flow)：${PLAIN}$RED$flow${PLAIN}"
        echo -e "   ${BLUE}加密(encryption)：${PLAIN} ${RED}none${PLAIN}"
        echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
        echo -e "   ${BLUE}底层安全传输(tls)：${PLAIN}${RED}XTLS${PLAIN}"
    else
        echo -e "   ${BLUE}IP/域名(address): ${PLAIN} ${RED}${domain}${PLAIN}"
        echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
        echo -e "   ${BLUE}密码(password)：${PLAIN}${RED}${password}${PLAIN}"
        echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
        echo -e "   ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
    fi
}

outputVmessTLS() {
    raw="{
  \"v\":\"2\",
  \"ps\":\"\",
  \"add\":\"$IP\",
  \"port\":\"${port}\",
  \"id\":\"${uid}\",
  \"aid\":\"$alterid\",
  \"net\":\"${network}\",
  \"type\":\"none\",
  \"host\":\"${domain}\",
  \"path\":\"\",
  \"tls\":\"tls\"
}"
    link=`echo -n ${raw} | base64 -w 0`
    link="vmess://${link}"
    echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
    echo -e "   ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
    echo -e "   ${BLUE}加密方式(security)：${PLAIN} ${RED}none${PLAIN}"
    echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
    echo -e "   ${BLUE}伪装域名/主机名(host)/SNI/peer名称：${PLAIN}${RED}${domain}${PLAIN}"
    echo -e "   ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
    echo  
    echo -e "   ${BLUE}vmess链接: ${PLAIN}$RED$link$PLAIN"
}

outputVmessWS() {
    raw="{
  \"v\":\"2\",
  \"ps\":\"\",
  \"add\":\"$IP\",
  \"port\":\"${port}\",
  \"id\":\"${uid}\",
  \"aid\":\"$alterid\",
  \"net\":\"${network}\",
  \"type\":\"none\",
  \"host\":\"${domain}\",
  \"path\":\"${wspath}\",
  \"tls\":\"tls\"
}"
    link=`echo -n ${raw} | base64 -w 0`
    link="vmess://${link}"

    echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
    echo -e "   ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
    echo -e "   ${BLUE}加密方式(security)：${PLAIN} ${RED}none${PLAIN}"
    echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
    echo -e "   ${BLUE}伪装类型(type)：${PLAIN}${RED}none$PLAIN"
    echo -e "   ${BLUE}伪装域名/主机名(host)/SNI/peer名称：${PLAIN}${RED}${domain}${PLAIN}"
    echo -e "   ${BLUE}路径(path)：${PLAIN}${RED}${wspath}${PLAIN}"
    echo -e "   ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
    echo  
    echo -e "   ${BLUE}vmess链接:${PLAIN} $RED$link$PLAIN"
}

showInfo() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " Xray未安装，请先安装！"
        return
    fi
    
    echo ""
    echo -n -e " ${BLUE}Xray运行状态：${PLAIN}"
    statusText
    echo -e " ${BLUE}Xray配置文件: ${PLAIN} ${RED}${CONFIG_FILE}${PLAIN}"
    colorEcho $BLUE " Xray配置信息："

    getConfigFileInfo

    echo -e "   ${BLUE}协议: ${PLAIN} ${RED}${protocol}${PLAIN}"
    if [[ "$trojan" = "true" ]]; then
        outputTrojan
        return 0
    fi
    if [[ "$vless" = "false" ]]; then
        if [[ "$kcp" = "true" ]]; then
            outputVmessKCP
            return 0
        fi
        if [[ "$tls" = "false" ]]; then
            outputVmess
        elif [[ "$ws" = "false" ]]; then
            outputVmessTLS
        else
            outputVmessWS
        fi
    else
        if [[ "$kcp" = "true" ]]; then
            echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
            echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
            echo -e "   ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
            echo -e "   ${BLUE}加密(encryption)：${PLAIN} ${RED}none${PLAIN}"
            echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}"
            echo -e "   ${BLUE}伪装类型(type)：${PLAIN} ${RED}${type}${PLAIN}"
            echo -e "   ${BLUE}mkcp seed：${PLAIN} ${RED}${seed}${PLAIN}" 
            return 0
        fi
        if [[ "$xtls" = "true" ]]; then
            echo -e " ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
            echo -e " ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
            echo -e " ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
            echo -e " ${BLUE}流控(flow)：${PLAIN}$RED$flow${PLAIN}"
            echo -e " ${BLUE}加密(encryption)：${PLAIN} ${RED}none${PLAIN}"
            echo -e " ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
            echo -e " ${BLUE}伪装类型(type)：${PLAIN}${RED}none$PLAIN"
            echo -e " ${BLUE}伪装域名/主机名(host)/SNI/peer名称：${PLAIN}${RED}${domain}${PLAIN}"
            echo -e " ${BLUE}底层安全传输(tls)：${PLAIN}${RED}XTLS${PLAIN}"
        elif [[ "$ws" = "false" ]]; then
            echo -e " ${BLUE}IP(address):  ${PLAIN}${RED}${IP}${PLAIN}"
            echo -e " ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
            echo -e " ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
            echo -e " ${BLUE}流控(flow)：${PLAIN}$RED$flow${PLAIN}"
            echo -e " ${BLUE}加密(encryption)：${PLAIN} ${RED}none${PLAIN}"
            echo -e " ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
            echo -e " ${BLUE}伪装类型(type)：${PLAIN}${RED}none$PLAIN"
            echo -e " ${BLUE}伪装域名/主机名(host)/SNI/peer名称：${PLAIN}${RED}${domain}${PLAIN}"
            echo -e " ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
        else
            echo -e " ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
            echo -e " ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
            echo -e " ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
            echo -e " ${BLUE}流控(flow)：${PLAIN}$RED$flow${PLAIN}"
            echo -e " ${BLUE}加密(encryption)：${PLAIN} ${RED}none${PLAIN}"
            echo -e " ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
            echo -e " ${BLUE}伪装类型(type)：${PLAIN}${RED}none$PLAIN"
            echo -e " ${BLUE}伪装域名/主机名(host)/SNI/peer名称：${PLAIN}${RED}${domain}${PLAIN}"
            echo -e " ${BLUE}路径(path)：${PLAIN}${RED}${wspath}${PLAIN}"
            echo -e " ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
        fi
    fi
}

showLog() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " Xray未安装，请先安装！"
        return
    fi

    journalctl -xen -u xray --no-pager
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#                     ${RED}Xray一键安装脚本${PLAIN}                      #"
    echo -e "# ${GREEN}作者${PLAIN}: 网络跳越(hijk)                                      #"
    echo -e "# ${GREEN}网址${PLAIN}: https://hijk.art                                    #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://hijk.club                                   #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/hijkclub                               #"
    echo -e "# ${GREEN}Youtube频道${PLAIN}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo -e "  ${GREEN}1.${PLAIN}   安装Xray-VMESS"
    echo -e "  ${GREEN}2.${PLAIN}   安装Xray-${BLUE}VMESS+mKCP${PLAIN}"
    echo -e "  ${GREEN}3.${PLAIN}   安装Xray-VMESS+TCP+TLS"
    echo -e "  ${GREEN}4.${PLAIN}   安装Xray-${BLUE}VMESS+WS+TLS${PLAIN}${RED}(推荐)${PLAIN}"
    echo -e "  ${GREEN}5.${PLAIN}   安装Xray-${BLUE}VLESS+mKCP${PLAIN}"
    echo -e "  ${GREEN}6.${PLAIN}   安装Xray-VLESS+TCP+TLS"
    echo -e "  ${GREEN}7.${PLAIN}   安装Xray-${BLUE}VLESS+WS+TLS${PLAIN}${RED}(可过cdn)${PLAIN}"
    echo -e "  ${GREEN}8.${PLAIN}   安装Xray-${BLUE}VLESS+TCP+XTLS${PLAIN}${RED}(推荐)${PLAIN}"
    echo -e "  ${GREEN}9.${PLAIN}   安装${BLUE}trojan${PLAIN}${RED}(推荐)${PLAIN}"
    echo -e "  ${GREEN}10.${PLAIN}  安装${BLUE}trojan+XTLS${PLAIN}${RED}(推荐)${PLAIN}"
    echo " -------------"
    echo -e "  ${GREEN}11.${PLAIN}  更新Xray"
    echo -e "  ${GREEN}12.  ${RED}卸载Xray${PLAIN}"
    echo " -------------"
    echo -e "  ${GREEN}13.${PLAIN}  启动Xray"
    echo -e "  ${GREEN}14.${PLAIN}  重启Xray"
    echo -e "  ${GREEN}15.${PLAIN}  停止Xray"
    echo " -------------"
    echo -e "  ${GREEN}16.${PLAIN}  查看Xray配置"
    echo -e "  ${GREEN}17.${PLAIN}  查看Xray日志"
    echo -e "  ${GREEN}18.${PLAIN}  Xray节点管理"
    echo " -------------"
    echo -e "  ${GREEN}0.${PLAIN}   退出"
    echo -n " 当前状态："
    statusText
    echo 

    read -p " 请选择操作[0-18]：" answer
    case $answer in
        0)
            exit 0
            ;;
        1)
            install
            ;;
        2)
            KCP="true"
            install
            ;;
        3)
            TLS="true"
            install
            ;;
        4)
            TLS="true"
            WS="true"
            install
            ;;
        5)
            VLESS="true"
            KCP="true"
            install
            ;;
        6)
            VLESS="true"
            TLS="true"
            install
            ;;
        7)
            VLESS="true"
            TLS="true"
            WS="true"
            install
            ;;
        8)
            VLESS="true"
            TLS="true"
            XTLS="true"
            install
            ;;
        9)
            TROJAN="true"
            TLS="true"
            install
            ;;
        10)
            TROJAN="true"
            TLS="true"
            XTLS="true"
            install
            ;;
        11)
            update
            ;;
        12)
            uninstall
            ;;
        13)
            start
            ;;
        14)
            restart
            ;;
        15)
            stop
            ;;
        16)
            showInfo
            ;;
        17)
            showLog
            ;;
        18)
            node_manager
            ;;
        *)
            colorEcho $RED " 请选择正确的操作！"
            exit 1
            ;;
    esac
}

# ========================
# 安装验证与Nginx兼容模块（新增）
# ========================

nginx_http2_listen_config() {
    local port="$1"
    local version_output=""
    local version=""
    local major="0"
    local minor="0"
    local patch="0"

    version_output=$(nginx -v 2>&1)
    version=$(printf '%s' "$version_output" | sed -n 's#.*nginx/\([0-9][0-9.]*\).*#\1#p')
    if [[ -z "$version" ]]; then
        colorEcho "$RED" " 无法读取Nginx版本：${version_output}" >&2
        return 1
    fi

    IFS='.' read -r major minor patch <<< "$version"
    major=${major:-0}
    minor=${minor:-0}
    patch=${patch:-0}

    if (( major > 1 || (major == 1 && minor > 25) || (major == 1 && minor == 25 && patch >= 1) )); then
        printf '    listen       %s ssl;\n' "$port"
        printf '    listen       [::]:%s ssl;\n' "$port"
        printf '    http2 on;\n'
    else
        printf '    listen       %s ssl http2;\n' "$port"
        printf '    listen       [::]:%s ssl http2;\n' "$port"
    fi
}

validate_install_configs() {
    colorEcho "$BLUE" " 检查Nginx配置..."
    if ! nginx -t; then
        colorEcho "$RED" " Nginx配置测试失败，安装已停止"
        return 1
    fi

    if [[ ! -x /usr/local/bin/xray ]]; then
        colorEcho "$RED" " 未找到Xray程序：/usr/local/bin/xray"
        return 1
    fi

    colorEcho "$BLUE" " 检查Xray配置..."
    if ! /usr/local/bin/xray run -test -config "$CONFIG_FILE"; then
        colorEcho "$RED" " Xray配置测试失败，安装已停止"
        return 1
    fi

    colorEcho "$GREEN" " Nginx和Xray配置测试通过"
}

# ========================
# Xray节点管理模块（新增）
# ========================

node_install_package() {
    local package_name="$1"

    if [[ "$PMT" = "apt" ]]; then
        if [[ "${NODE_APT_UPDATED:-false}" != "true" ]]; then
            apt-get update || return 1
            NODE_APT_UPDATED="true"
        fi
        apt-get install -y "$package_name"
    elif [[ "$PMT" = "yum" ]]; then
        yum install -y "$package_name"
    else
        colorEcho "$RED" " 无法识别包管理器，不能安装 ${package_name}"
        return 1
    fi
}

node_require_command() {
    local command_name="$1"
    local package_name="$2"

    if command -v "$command_name" >/dev/null 2>&1; then
        return 0
    fi

    colorEcho "$YELLOW" " 未检测到 ${command_name}，正在安装 ${package_name}..."
    node_install_package "$package_name" || return 1
    if ! command -v "$command_name" >/dev/null 2>&1; then
        colorEcho "$RED" " ${command_name} 安装失败"
        return 1
    fi
}

node_urlencode() {
    printf '%s' "$1" | jq -sRr @uri
}

node_unsupported_message() {
    colorEcho "$YELLOW" " 当前自动输出和节点管理仅支持 VLESS + WS + TLS"
    colorEcho "$YELLOW" " 其他VLESS传输方式暂不支持自动导出，不会生成链接"
}

node_load_vless_info() {
    local nginx_port=""

    if [[ ! -f "$CONFIG_FILE" ]]; then
        colorEcho "$RED" " Xray配置文件不存在：${CONFIG_FILE}"
        return 1
    fi

    node_require_command jq jq || return 1
    if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
        colorEcho "$RED" " Xray配置文件不是有效的JSON：${CONFIG_FILE}"
        return 1
    fi

    NODE_UUID=$(jq -r 'first(.inbounds[]? | select(.protocol == "vless") | .settings.clients[]? | .id // empty)' "$CONFIG_FILE")
    NODE_XRAY_PORT=$(jq -r 'first(.inbounds[]? | select(.protocol == "vless") | .port // empty) | tostring' "$CONFIG_FILE")
    NODE_TRANSPORT=$(jq -r 'first(.inbounds[]? | select(.protocol == "vless") | (.streamSettings.network // "tcp"))' "$CONFIG_FILE")
    NODE_SECURITY=$(jq -r 'first(.inbounds[]? | select(.protocol == "vless") | (.streamSettings.security // "none"))' "$CONFIG_FILE")
    NODE_DOMAIN=$(jq -r 'first(.inbounds[]? | select(.protocol == "vless") | (.streamSettings.wsSettings.headers.Host // .streamSettings.tlsSettings.serverName // .streamSettings.xtlsSettings.serverName // empty))' "$CONFIG_FILE")
    NODE_WS_PATH=$(jq -r 'first(.inbounds[]? | select(.protocol == "vless") | (.streamSettings.wsSettings.path // empty))' "$CONFIG_FILE")
    NODE_FLOW=$(jq -r 'first(.inbounds[]? | select(.protocol == "vless") | .settings.clients[]? | (.flow // empty))' "$CONFIG_FILE")

    if [[ -z "$NODE_UUID" || -z "$NODE_XRAY_PORT" ]]; then
        colorEcho "$RED" " 当前配置中没有可管理的VLESS客户端"
        return 1
    fi
    if [[ "$NODE_XRAY_PORT" = *[!0-9]* ]]; then
        colorEcho "$RED" " 读取到的Xray监听端口无效：${NODE_XRAY_PORT}"
        return 1
    fi

    NODE_PUBLIC_PORT="$NODE_XRAY_PORT"
    NODE_NGINX_CONF=""

    if [[ "$NODE_TRANSPORT" != "ws" || -z "$NODE_WS_PATH" || -z "$NODE_DOMAIN" ]]; then
        node_unsupported_message
        return 1
    fi

    NODE_NGINX_CONF="${NGINX_CONF_PATH}${NODE_DOMAIN}.conf"
    if [[ ! -f "$NODE_NGINX_CONF" ]]; then
        colorEcho "$RED" " 未找到VLESS WS对应的Nginx配置：${NODE_NGINX_CONF}"
        node_unsupported_message
        return 1
    fi

    nginx_port=$(awk '$1 == "listen" && $0 ~ /ssl/ { value=$2; gsub(/[^0-9]/, "", value); if (value != "") { print value; exit } }' "$NODE_NGINX_CONF")
    if [[ -z "$nginx_port" || "$nginx_port" = *[!0-9]* ]] || ! grep -qiE 'listen[[:space:]].*ssl' "$NODE_NGINX_CONF"; then
        colorEcho "$RED" " Nginx配置中未检测到有效的TLS监听端口"
        node_unsupported_message
        return 1
    fi

    NODE_PUBLIC_PORT="$nginx_port"
    NODE_SECURITY="tls"
}

node_build_vless_link() {
    local encoded_domain=""
    local encoded_path=""
    local encoded_name=""
    local query=""

    node_load_vless_info || return 1

    encoded_domain=$(node_urlencode "$NODE_DOMAIN") || return 1
    encoded_path=$(node_urlencode "$NODE_WS_PATH") || return 1
    encoded_name=$(node_urlencode "$NODE_DOMAIN") || return 1
    query="encryption=none&security=$(node_urlencode "$NODE_SECURITY")&type=$(node_urlencode "$NODE_TRANSPORT")"

    if [[ "$NODE_TRANSPORT" = "ws" ]]; then
        query="${query}&host=${encoded_domain}&path=${encoded_path}"
        if [[ "$NODE_SECURITY" = "tls" ]]; then
            query="${query}&sni=${encoded_domain}"
        fi
    elif [[ "$NODE_SECURITY" = "tls" || "$NODE_SECURITY" = "xtls" ]]; then
        query="${query}&sni=${encoded_domain}"
    fi

    if [[ -n "$NODE_FLOW" ]]; then
        query="${query}&flow=$(node_urlencode "$NODE_FLOW")"
    fi

    NODE_VLESS_LINK="vless://${NODE_UUID}@${NODE_DOMAIN}:${NODE_PUBLIC_PORT}?${query}#${encoded_name}"
}

node_print_vless_info() {
    echo ""
    echo "================"
    echo "Domain: ${NODE_DOMAIN}"
    echo "UUID: ${NODE_UUID}"
    echo "Protocol: VLESS"
    echo "Transport: ${NODE_TRANSPORT}"
    echo "TLS: ${NODE_SECURITY}"
    echo "Port: ${NODE_PUBLIC_PORT}"
    echo "Xray Listen Port: ${NODE_XRAY_PORT}"
    echo "WS Path: ${NODE_WS_PATH}"
    echo "VLESS Link: ${NODE_VLESS_LINK}"
    echo "================"
}

node_show_qrcode() {
    if [[ -z "$NODE_VLESS_LINK" ]]; then
        node_build_vless_link || return 1
    fi

    node_require_command qrencode qrencode || return 1
    echo ""
    colorEcho "$BLUE" " VLESS终端二维码："
    printf '%s' "$NODE_VLESS_LINK" | qrencode -t ANSIUTF8
}

node_show_vless_link() {
    node_build_vless_link || return 1
    node_print_vless_info
}

node_try_show_qrcode() {
    if ! node_show_qrcode; then
        colorEcho "$YELLOW" " 二维码生成失败，VLESS文本链接和节点信息文件仍然有效"
    fi
    return 0
}

node_regenerate_uuid() {
    local backup_file=""
    local new_uuid=""
    local temp_file=""
    local xray_bin=""

    node_require_command jq jq || return 1
    node_require_command uuidgen uuid-runtime || return 1
    node_load_vless_info || return 1

    backup_file="${CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    if [[ -e "$backup_file" ]]; then
        backup_file="${backup_file}.$$"
    fi
    if ! cp -a -- "$CONFIG_FILE" "$backup_file"; then
        colorEcho "$RED" " 配置文件备份失败"
        return 1
    fi
    if ! chmod 600 "$backup_file"; then
        rm -f -- "$backup_file"
        colorEcho "$RED" " 无法保护配置备份权限，已删除不安全的备份文件"
        return 1
    fi
    colorEcho "$BLUE" " 已备份配置：${backup_file}"

    new_uuid=$(uuidgen)
    if [[ -z "$new_uuid" ]]; then
        colorEcho "$RED" " UUID生成失败"
        return 1
    fi

    temp_file=$(mktemp "${CONFIG_FILE}.tmp.XXXXXX") || return 1
    if ! jq --arg uuid "$new_uuid" '
        (.inbounds | map(.protocol == "vless") | index(true)) as $index
        | if $index == null then
            error("VLESS inbound not found")
          elif (.inbounds[$index].settings.clients | length) == 0 then
            error("VLESS client not found")
          else
            .inbounds[$index].settings.clients[0].id = $uuid
          end
    ' "$CONFIG_FILE" > "$temp_file"; then
        rm -f -- "$temp_file"
        colorEcho "$RED" " UUID写入失败，原配置未改变"
        return 1
    fi

    chmod --reference="$CONFIG_FILE" "$temp_file" 2>/dev/null || chmod 600 "$temp_file"
    chown --reference="$CONFIG_FILE" "$temp_file" 2>/dev/null || true
    if ! mv -f -- "$temp_file" "$CONFIG_FILE"; then
        rm -f -- "$temp_file"
        colorEcho "$RED" " 新配置替换失败"
        return 1
    fi

    xray_bin=$(command -v xray 2>/dev/null)
    [[ -z "$xray_bin" && -x /usr/local/bin/xray ]] && xray_bin="/usr/local/bin/xray"
    if [[ -z "$xray_bin" ]]; then
        cp -af -- "$backup_file" "$CONFIG_FILE"
        colorEcho "$RED" " 未找到Xray程序，已恢复原配置"
        return 1
    fi

    if ! "$xray_bin" run -test -config "$CONFIG_FILE"; then
        cp -af -- "$backup_file" "$CONFIG_FILE"
        colorEcho "$RED" " Xray配置测试失败，已恢复原配置"
        return 1
    fi

    if ! systemctl restart xray; then
        cp -af -- "$backup_file" "$CONFIG_FILE"
        systemctl restart xray
        colorEcho "$RED" " Xray重启失败，已恢复原配置"
        return 1
    fi

    sleep 1
    if ! systemctl is-active --quiet xray; then
        cp -af -- "$backup_file" "$CONFIG_FILE"
        systemctl restart xray
        sleep 1
        if systemctl is-active --quiet xray; then
            colorEcho "$RED" " 新配置启动后未保持active，已恢复旧配置"
        else
            colorEcho "$RED" " 新配置启动后未保持active；旧配置已恢复，但Xray仍未正常运行"
        fi
        return 1
    fi

    colorEcho "$GREEN" " UUID已更新，Xray已重启"
    node_show_vless_link || return 1
    node_save_info || return 1
    node_try_show_qrcode
}

node_restart_xray() {
    if systemctl restart xray; then
        colorEcho "$GREEN" " Xray重启成功"
    else
        colorEcho "$RED" " Xray重启失败，请查看日志"
        return 1
    fi
}

node_show_status() {
    systemctl status xray --no-pager -l
}

node_show_log() {
    journalctl -u xray -n 100 --no-pager
}

node_check_listener() {
    local port="$1"
    local process_name="$2"
    local label="$3"
    local listen_info=""

    listen_info=$(ss -lntp | awk -v target_port="$port" 'NR == 1 || $4 ~ (":" target_port "$")')
    echo ""
    colorEcho "$BLUE" " ${label}：${port}"
    echo "$listen_info"

    if echo "$listen_info" | grep -qi "$process_name"; then
        colorEcho "$GREEN" " ${label} ${port} 正在由 ${process_name} 监听"
        return 0
    fi

    colorEcho "$RED" " ${label} ${port} 未由 ${process_name} 监听"
    return 1
}

node_check_port() {
    local check_failed="false"

    node_load_vless_info || return 1
    if ! command -v ss >/dev/null 2>&1; then
        colorEcho "$RED" " 未找到ss命令，无法检查端口"
        return 1
    fi

    node_check_listener "$NODE_PUBLIC_PORT" nginx "Nginx公网端口" || check_failed="true"
    node_check_listener "$NODE_XRAY_PORT" xray "Xray内部端口" || check_failed="true"

    [[ "$check_failed" = "false" ]]
}

node_save_info() {
    local info_file="/root/vless-info.txt"

    node_build_vless_link || return 1
    if ! (umask 077; cat > "$info_file" <<-EOF
================

Domain: ${NODE_DOMAIN}

UUID: ${NODE_UUID}

Protocol: VLESS

Transport: ${NODE_TRANSPORT}

TLS: ${NODE_SECURITY}

Port: ${NODE_PUBLIC_PORT}

WS Path: ${NODE_WS_PATH}

VLESS Link: ${NODE_VLESS_LINK}

================
EOF
    ); then
        colorEcho "$RED" " 节点信息保存失败"
        return 1
    fi

    if ! chmod 600 "$info_file"; then
        colorEcho "$RED" " 无法设置节点信息文件权限：${info_file}"
        return 1
    fi

    colorEcho "$GREEN" " 节点信息已保存到 ${info_file}"
}

node_after_install() {
    if [[ "$VLESS" != "true" ]]; then
        return 0
    fi

    if [[ "$WS" = "true" && "$TLS" = "true" && "$XTLS" = "false" && "$KCP" = "false" ]]; then
        node_show_vless_link || return 1
        node_save_info || return 1
        node_try_show_qrcode
    else
        node_unsupported_message
    fi
}

node_manager() {
    local answer=""

    if ! node_load_vless_info; then
        return 1
    fi

    while true
    do
        clear
        echo "================="
        echo "Xray节点管理"
        echo "================="
        echo "1. 查看VLESS链接"
        echo "2. 重新生成UUID"
        echo "3. 重启Xray"
        echo "4. 查看Xray状态"
        echo "5. 查看Xray日志"
        echo "6. 检查端口监听"
        echo "7. 保存节点信息"
        echo "0. 退出节点管理"
        echo "================="
        read -r -p "请选择操作[0-7]：" answer

        case "$answer" in
            1)
                node_show_vless_link && node_try_show_qrcode
                ;;
            2)
                node_regenerate_uuid
                ;;
            3)
                node_restart_xray
                ;;
            4)
                node_show_status
                ;;
            5)
                node_show_log
                ;;
            6)
                node_check_port
                ;;
            7)
                node_save_info
                ;;
            0)
                return 0
                ;;
            *)
                colorEcho "$RED" " 请选择正确的操作！"
                ;;
        esac

        echo ""
        read -r -p "按回车键继续..." answer
    done
}

checkSystem

action=$1
[[ -z $1 ]] && action=menu
case "$action" in
    menu|update|uninstall|start|restart|stop|showInfo|showLog|node_manager)
        ${action}
        ;;
    *)
        echo " 参数错误"
        echo " 用法: `basename $0` [menu|update|uninstall|start|restart|stop|showInfo|showLog|node_manager]"
        ;;
esac
