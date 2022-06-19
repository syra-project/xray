#!/bin/bash
# Auth: syra
# Desc: v2ray installation script
# 	ws+vless,ws+trojan,ws+socks,ws+shadowsocks
#	grpc+vless,grpc+trojan,grpc+socks,grpc+shadowsocks
# Plat: ubuntu 18.04+
# Eg  : bash v2ray_installation_ws+grpc_vless+trojan+socks+shadowsocks.sh "nama domain Anda"

if [ -z "10028978.xray.syra.co.id" ];then
	echo "Nama domain tidak boleh kosong"
	exit
fi

# Konfigurasikan zona waktu sistem sebagai Distrik Kedelapan Timur, dan atur waktu ke 24H
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
if ! grep -q 'LC_TIME' /etc/default/locale;then echo 'LC_TIME=en_DK.UTF-8' >> /etc/default/locale;fi


# Perbarui sumber resmi Ubuntu, gunakan sumber resmi ubuntu untuk menginstal nginx dan paket dependen dan mengatur startup, tutup firewall ufw
apt clean all && apt update && apt upgrade -y
apt install socat nginx curl pwgen openssl netcat cron -y
systemctl enable nginx
ufw disable


# Sebelum memulai penerapan, mari kita konfigurasikan parameter yang perlu digunakan, sebagai berikut: 27 
# "nama domain, uuid, jalur ws dan grpc, direktori domainSock, direktori sertifikat ssl"

# 1. Tetapkan nama domain Anda yang telah diselesaikan
domainName="10028978.xray.syra.co.id"

# 2. Secara acak menghasilkan uuid
uuid="`uuidgen`"

# 3. Buat port layanan secara acak yang perlu digunakan oleh socks dan shadowsocks
socks_ws_port="`shuf -i 20000-30000 -n 1`"
shadowsocks_ws_port="`shuf -i 30001-40000 -n 1`"
socks_grpc_port="`shuf -i 40001-50000 -n 1`"
shadowsocks_grpc_port="`shuf -i 50001-60000 -n 1`"

# 4. Buat kata sandi pengguna trojan, socks, dan shadowsocks secara acak
trojan_passwd="syra"
socks_user="syra"
socks_passwd="syra"
shadowsocks_passwd="syra"

# 5. Gunakan WS untuk mengonfigurasi protokol vless, trojan, socks, shadowsocks 48 
# Secara acak menghasilkan jalur ws yang perlu digunakan vless, trojan, socks, shadowsocks
vmess_ws_path="/syra/vmess_ws"
vless_ws_path="/syra/vless_ws"
trojan_ws_path="/syra/trojan_ws"
socks_ws_path="/syra/socks_ws"
shadowsocks_ws_path="/syra/ss_ws"

# 6. Gunakan gRPC untuk mengonfigurasi protokol vless, trojan, socks, shadowsocks 55 
# Secara acak menghasilkan jalur grpc yang perlu digunakan vless, trojan, socks, shadowsocks
vmess_grpc_path="vmess_grpc"
vless_grpc_path="vless_grpc"
trojan_grpc_path="trojan_grpc"
socks_grpc_path="socks_grpc"
shadowsocks_grpc_path="ss_grpc"

# 7. Buat direktori domainSock yang diperlukan dan otorisasi izin pengguna nginx
domainSock_dir="/run/xray";! [ -d $domainSock_dir ] && mkdir -pv $domainSock_dir
chown www-data.www-data $domainSock_dir

#8. Tentukan nama file domainSock yang perlu digunakan
vmess_ws_domainSock="${domainSock_dir}/vmess_ws.sock"
vless_ws_domainSock="${domainSock_dir}/vless_ws.sock"
trojan_ws_domainSock="${domainSock_dir}/trojan_ws.sock"
vmess_grpc_domainSock="${domainSock_dir}/vmess_grpc.sock"
vless_grpc_domainSock="${domainSock_dir}/vless_grpc.sock"
trojan_grpc_domainSock="${domainSock_dir}/trojan_grpc.sock"

# 9. Buat direktori secara acak untuk menyimpan sertifikat ssl berdasarkan waktu
ssl_dir="$(mkdir -pv "/etc/nginx/ssl/`date +"%F-%H-%M-%S"`" |awk -F"'" END'{print $2}')"


# Instal xray menggunakan perintah xray resmi dan tentukan www-data sebagai pengguna yang sedang berjalan
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u www-data


##Instal acme dan ajukan sertifikat enkripsi
source ~/.bashrc
if nc -z localhost 443;then /etc/init.d/nginx stop;fi
if ! [ -d /root/.acme.sh ];then curl https://get.acme.sh | sh;fi
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue -d "$domainName" -k ec-256 --alpn
~/.acme.sh/acme.sh --installcert -d "$domainName" --fullchainpath $ssl_dir/xray.crt --keypath $ssl_dir/xray.key --ecc
chown www-data.www-data $ssl_dir/xray.*

## Tambahkan perintah perbarui sertifikat ke tugas yang dijadwalkan
echo -n '#!/bin/bash
/etc/init.d/nginx stop
"/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" &> /root/renew_ssl.log
/etc/init.d/nginx start
' > /usr/local/bin/ssl_renew.sh
chmod +x /usr/local/bin/ssl_renew.sh
if ! grep -q 'ssl_renew.sh' /var/spool/cron/crontabs/root;then (crontab -l;echo "15 03 */3 * * /usr/local/bin/ssl_renew.sh") | crontab;fi


# Konfigurasi nginx, jalankan perintah berikut untuk menambahkan file konfigurasi nginx
echo "
server {
	listen 80;
	server_name "$domainName";
	return 301 https://"'$host'""'$request_uri'";
}
server {
	listen 443 ssl http2;
	listen [::]:443 ssl http2;
	server_name "$domainName";
	ssl_certificate $ssl_dir/xray.crt;
	ssl_certificate_key $ssl_dir/xray.key;
	ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5;
	ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
	root /usr/share/nginx/html;
  
	# ------------------- WS -------------------
	location = "$vmess_ws_path" {
		proxy_redirect off;
		proxy_pass http://unix:"${vmess_ws_domainSock}";
		proxy_http_version 1.1;
		proxy_set_header Upgrade "'"$http_upgrade"'";
		proxy_set_header Connection '"'upgrade'"';
    	proxy_set_header Host "'"$host"'";
    	proxy_set_header X-Real-IP "'"$remote_addr"'";
    	proxy_set_header X-Forwarded-For "'"$proxy_add_x_forwarded_for"'";		
	}

	location = "$vless_ws_path" {
		proxy_redirect off;
		proxy_pass http://unix:"${vless_ws_domainSock}";
		proxy_http_version 1.1;
		proxy_set_header Upgrade "'"$http_upgrade"'";
		proxy_set_header Connection '"'upgrade'"';
    	proxy_set_header Host "'"$host"'";
    	proxy_set_header X-Real-IP "'"$remote_addr"'";
    	proxy_set_header X-Forwarded-For "'"$proxy_add_x_forwarded_for"'";		
	}	
	
	location = "$trojan_ws_path" {
		proxy_redirect off;
		proxy_pass http://unix:"${trojan_ws_domainSock}";
		proxy_http_version 1.1;
		proxy_set_header Upgrade "'"$http_upgrade"'";
		proxy_set_header Connection '"'upgrade'"';
	  proxy_set_header Host "'"$host"'";
	  proxy_set_header X-Real-IP "'"$remote_addr"'";
	  proxy_set_header X-Forwarded-For "'"$proxy_add_x_forwarded_for"'";		
	}	
	
	location = "$socks_ws_path" {
		proxy_redirect off;
		proxy_pass http://127.0.0.1:"$socks_ws_port";
		proxy_http_version 1.1;
		proxy_set_header Upgrade "'"$http_upgrade"'";
		proxy_set_header Connection '"'upgrade'"';
	  proxy_set_header Host "'"$host"'";
	  proxy_set_header X-Real-IP "'"$remote_addr"'";
	  proxy_set_header X-Forwarded-For "'"$proxy_add_x_forwarded_for"'";		
	}
	
	location = "$shadowsocks_ws_path" {
		proxy_redirect off;
		proxy_pass http://127.0.0.1:"$shadowsocks_ws_port";
		proxy_http_version 1.1;
		proxy_set_header Upgrade "'"$http_upgrade"'";
		proxy_set_header Connection '"'upgrade'"';
	  proxy_set_header Host "'"$host"'";
	  proxy_set_header X-Real-IP "'"$remote_addr"'";
	  proxy_set_header X-Forwarded-For "'"$proxy_add_x_forwarded_for"'";	
	}	
	# ------------------- WS -------------------
	
	# ------------------ gRPC ------------------
	location ^~ "/$vmess_grpc_path" {
		proxy_redirect off;
	  grpc_set_header Host "'"$host"'";
	  grpc_set_header X-Real-IP "'"$remote_addr"'";
	  grpc_set_header X-Forwarded-For "'"$proxy_add_x_forwarded_for"'";
		grpc_pass grpc://unix:"${vmess_grpc_domainSock}";		
	}

	location ^~ "/$vless_grpc_path" {
		proxy_redirect off;
	  grpc_set_header Host "'"$host"'";
	  grpc_set_header X-Real-IP "'"$remote_addr"'";
	  grpc_set_header X-Forwarded-For "'"$proxy_add_x_forwarded_for"'";
		grpc_pass grpc://unix:"${vless_grpc_domainSock}";		
	}
	
	location ^~ "/$trojan_grpc_path" {
		proxy_redirect off;
	  grpc_set_header Host "'"$host"'";
	  grpc_set_header X-Real-IP "'"$remote_addr"'";
	  grpc_set_header X-Forwarded-For "'"$proxy_add_x_forwarded_for"'";
		grpc_pass grpc://unix:"${trojan_grpc_domainSock}";	
	}	
	
	location ^~ "/$socks_grpc_path" {
		proxy_redirect off;
	  grpc_set_header Host "'"$host"'";
	  grpc_set_header X-Real-IP "'"$remote_addr"'";
	  grpc_set_header X-Forwarded-For "'"$proxy_add_x_forwarded_for"'";
		grpc_pass grpc://127.0.0.1:"$socks_grpc_port";	
	}
	
	location ^~ "/$shadowsocks_grpc_path" {
		proxy_redirect off;
	  grpc_set_header Host "'"$host"'";
	  grpc_set_header X-Real-IP "'"$remote_addr"'";
	  grpc_set_header X-Forwarded-For "'"$proxy_add_x_forwarded_for"'";
		grpc_pass grpc://127.0.0.1:"$shadowsocks_grpc_port";		
	}	
	# ------------------ gRPC ------------------	
	
}
" > /etc/nginx/conf.d/xray.conf

# Konfigurasi xray, jalankan perintah berikut untuk menambahkan file konfigurasi xray
echo '
{
  "log" : {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
	{
		"listen": '"\"${vmess_ws_domainSock}\""',
		"protocol": "vless",
		"settings": {
			"decryption":"none",
			"clients": [
				{
          "id": '"\"$uuid\""',
          "level": 1
				}
			]
		},
		"streamSettings":{
			"network": "ws",
			"wsSettings": {
				"path": '"\"$vmess_ws_path\""'
			}
		}
	},	
	{
		"listen": '"\"${vless_ws_domainSock}\""',
		"protocol": "vless",
		"settings": {
			"decryption":"none",
			"clients": [
				{
          "id": '"\"$uuid\""',
          "level": 1
				}
			]
		},
		"streamSettings":{
			"network": "ws",
			"wsSettings": {
				"path": '"\"$vless_ws_path\""'
			}
		}
	},
	{
		"listen": '"\"$trojan_ws_domainSock\""',
		"protocol": "trojan",
		"settings": {
			"decryption":"none",		
			"clients": [
				{
					"password": '"\"$trojan_passwd\""',
					"email": "",
					"level": 0
				}
			],
			"udp": true
		},
		"streamSettings":{
			"network": "ws",
			"wsSettings": {
				"path": '"\"$trojan_ws_path\""'
			}
		}
	},
	{
		"listen": "127.0.0.1",
		"port": '"\"$socks_ws_port\""',
		"protocol": "socks",
		"settings": {
			"auth": "password",
			"accounts": [
				{
					"user": '"\"$socks_user\""',
					"pass": '"\"$socks_passwd\""'
				}
			],
			"level": 0,
			"udp": true
		},
		"streamSettings":{
			"network": "ws",
			"wsSettings": {
				"path": '"\"$socks_ws_path\""'
			}
		}
	},
	{
		"listen": "127.0.0.1",
		"port": '"\"$shadowsocks_ws_port\""',
		"protocol": "shadowsocks",
		"settings": {
			"decryption":"none",
			"email": "",
			"method": "AES-128-GCM",
			"password": '"\"$shadowsocks_passwd\""',
			"level": 0,
			"network": "tcp,udp",
			"ivCheck": false
		},
		"streamSettings":{
			"network": "ws",
			"wsSettings": {
				"path": '"\"$shadowsocks_ws_path\""'
			}
		}
	},	
	{
		"listen": '"\"${vmess_grpc_domainSock}\""',
		"protocol": "vmess",
		"settings": {
			"decryption":"none",
			"clients": [
				{
				"id": '"\"$uuid\""',
				"level": 0
				}
			]
		},
		"streamSettings":{
			"network": "grpc",
			"grpcSettings": {
				"serviceName": '"\"$vmess_grpc_path\""',
				"multiMode": true
			}
		}
	},
  	{
		"listen": '"\"${vless_grpc_domainSock}\""',
		"protocol": "vless",
		"settings": {
			"decryption":"none",
			"clients": [
				{
				"id": '"\"$uuid\""',
				"level": 0
				}
			]
		},
		"streamSettings":{
			"network": "grpc",
			"grpcSettings": {
				"serviceName": '"\"$vless_grpc_path\""',
				"multiMode": true
			}
		}
	},
	{
		"listen": '"\"$trojan_grpc_domainSock\""',
		"protocol": "trojan",
		"settings": {
			"decryption":"none",
			"clients": [
				{
					"password": '"\"$trojan_passwd\""',
					"email": "",
					"level": 0
				}
			]
		},
		"streamSettings":{
		"network": "grpc",
			"grpcSettings": {
				"serviceName": '"\"$trojan_grpc_path\""'
			}
		}
	},
	{
		"listen": "127.0.0.1",
		"port": '"\"$socks_grpc_port\""',
		"protocol": "socks",
		"settings": {
			"decryption":"none",
			"auth": "password",
			"accounts": [
				{
					"user": '"\"$socks_user\""',
					"pass": '"\"$socks_passwd\""'
				}
			],
			"level": 0,
			"udp": true
		},
		"streamSettings":{
		"network": "grpc",
			"grpcSettings": {
				"serviceName": '"\"$socks_grpc_path\""'
			}
		}
	},
	{
		"listen": "127.0.0.1",
		"port": '"\"$shadowsocks_grpc_port\""',
		"protocol": "shadowsocks",
		"settings": {
			"decryption":"none",
			"email": "",
			"method": "AES-128-GCM",
			"password": '"\"$shadowsocks_passwd\""',
			"network": "tcp,udp",
			"ivCheck": false,
			"level": 0
		},
		"streamSettings":{
		"network": "grpc",
			"grpcSettings": {
				"serviceName": '"\"$shadowsocks_grpc_path\""'
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

# perbesar hash bucket size ke 64 
# sed -i 's/# server_names_hash_bucket_size 64;/server_names_hash_bucket_size 64;/g' /etc/nginx/nginx.conf

# restart xray dan nginx
systemctl restart xray
#systemctl status xray
/usr/sbin/nginx -t && systemctl restart nginx


# Keluarkan informasi konfigurasi dan simpan ke file
xray_config_info="/root/xray_config.info"
echo "
----------- Nama domain dan port terpadu untuk semua metode koneksi -----------
nama domain	: $domainName
Port		: 443
------------- WS ------------
----------- vmess+ws -----------
Protokol	: vmess
UUID		: $uuid
Path		: $vmess_ws_path
----------- vless+ws -----------
Protokol	: vless
UUID		: $uuid
Path		: $vless_ws_path
----------- trojan+ws -----------
Protokol	: trojan
Password	: $trojan_passwd
Path	: $trojan_ws_path
----------- socks+ws ------------
Protokol	: socks
User		：$socks_user	
Pass		: $socks_passwd
Path		: $socks_ws_path
-------- shadowsocks+ws ---------
Protokol	: shadowsocks
Pass		: $shadowsocks_passwd
Enkripsi	：AES-128-GCM
Path		: $shadowsocks_ws_path

------------ gRPC -----------
------------ vmess+grpc -----------
Protokol	: vmess
UUID		: $uuid
Path		: $vmess_grpc_path
------------ vless+grpc -----------
Protokol	: vless
UUID		: $uuid
Path		: $vless_grpc_path
----------- trojan+grpc -----------
Protokol	: trojan
Pass		: $trojan_passwd
Path		: $trojan_grpc_path
----------- socks+grpc ------------
Protokol	: socks
User  		：$socks_user
Pass		: $socks_passwd
Path		: $socks_grpc_path
-------- shadowsocks+grpc ---------
Protokol	: shadowsocks
Pass		: $shadowsocks_passwd
Enkripsi	：AES-128-GCM
Path		: $shadowsocks_grpc_path
" | tee $xray_config_info
