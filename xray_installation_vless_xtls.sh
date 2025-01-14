#!/bin/bash
# Auth: happylife
# Desc: xray installation script
# Plat: ubuntu 18.04+
# Eg  : bash xray_installation_vless_xtls.sh "你的域名"

##安装依赖包，关闭防火墙ufw
apt update
apt install curl pwgen openssl netcat cron -y
ufw disable

domainName="$1"
xrayPort="`shuf -i 20000-49000 -n 1`"
fallbacksPort="`shuf -i 50000-65000 -n 1`"
uuid="`uuidgen`"

if [ -z "$domainName" ];then
	echo "域名不能为空"
	exit
fi


##配置系统时区为东八区
rm -f /etc/localtime
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime


##使用xray官方命令安装xray并设置开机启动
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
systemctl enable xray


##安装nginx并确保开机启动
apt install nginx -y
systemctl enable nginx
systemctl start nginx


##安装acme,并申请加密证书
## ssl_dir="`mkdir -pv /usr/local/etc/xray/ssl | awk -F"'" 'END{print $2}'`"
ssl_dir="/usr/local/etc/xray/ssl";! [ -d $ssl_dir ] && mkdir -p $ssl_dir
source ~/.bashrc
curl  https://get.acme.sh | sh
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue -d "$domainName" -k ec-256 --alpn
~/.acme.sh/acme.sh --installcert -d "$domainName" --fullchainpath $ssl_dir/xray.crt --keypath $ssl_dir/xray.key --ecc


## 把申请证书命令添加到计划任务
echo -n '#!/bin/bash
/etc/init.d/nginx stop
"/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" &> /root/renew_ssl.log
/etc/init.d/nginx start
' > /usr/local/bin/ssl_renew.sh
chmod +x /usr/local/bin/ssl_renew.sh
(crontab -l;echo "15 03 */3 * * /usr/local/bin/ssl_renew.sh") | crontab


##配置nginx
echo "
stream {
        map "'$ssl_preread_server_name'" "'$all_services'" {
		$domainName xtls;
	}
	upstream xtls {
		server 127.0.0.1:$xrayPort; # xray服务端口
	}
	server {
		listen 443      reuseport;
		listen [::]:443 reuseport;
		proxy_pass      "'$all_services'";
		ssl_preread     on;
	}
}
" > /etc/nginx/modules-enabled/stream.conf

echo "
server {
	listen 80;
	server_name $domainName;
	if ("'$host'" = $domainName) {
		return 301 https://"'$host$request_uri'";
	}
	return 404;
}

server {
	listen 127.0.0.1:$fallbacksPort;
	server_name $domainName;
	index index.html;
	root /usr/share/nginx/html;
}
" > /etc/nginx/conf.d/xray.conf


##配置xray
echo '
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": '$xrayPort',
	    "listen": "127.0.0.1",
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": '"\"$uuid\""',
                        "flow": "xtls-rprx-direct",
                        "level": 0,
                        "email": "happylife@happylife.page"
                    }
                ],
                "decryption": "none",
                "fallbacks": [
                    {
                        "dest": '$fallbacksPort'
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "xtls",
                "xtlsSettings": {
                    "alpn": [
                        "http/1.1"
                    ],
                    "certificates": [
                        {
                            "certificateFile": '"\"$ssl_dir/xray.crt\""',
                            "keyFile": '"\"$ssl_dir/xray.key\""'
                        }
                    ]
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
' > /usr/local/etc/xray/config.json

##重启xray和nginx
systemctl restart xray
systemctl status -l xray
/usr/sbin/nginx -t && systemctl restart nginx

##输出配置信息
echo
echo "域名: $domainName"
echo "端口: 443"
echo "UUID: $uuid"
echo "xray协议: vless"
echo "传输协议: tcp"
echo "安全协议: xtls"
echo "flow: xtls-rprx-direct"
