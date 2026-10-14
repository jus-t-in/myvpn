#!/usr/bin/env bash
# 在新建的 OCI Ubuntu 实例上安装官方 sing-box，配置单个 Reality / TCP 443。
# sudo bash /tmp/setup-reality.sh；客户端参数保存在 /root/myvpn-client.json。
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo '请使用 sudo 运行。' >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
umask 077

if ! command -v sing-box >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl openssl python3 iptables-persistent
  install -d -m 755 /etc/apt/keyrings
  curl -fsSL --retry 2 https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
  chmod 644 /etc/apt/keyrings/sagernet.asc
  cat > /etc/apt/sources.list.d/sagernet.sources <<'EOF'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
EOF
  apt-get update -qq
  apt-get install -y -qq sing-box
fi
apt-mark hold sing-box
openssl s_client -connect www.microsoft.com:443 -servername www.microsoft.com \
  -tls1_3 -brief </dev/null

python3 - <<'PY'
import grp
import json
import os
import pathlib
import secrets
import subprocess
import uuid

credentials_path = pathlib.Path('/root/myvpn-reality-credentials.json')
if credentials_path.exists():
    credentials = json.loads(credentials_path.read_text())
else:
    output = subprocess.check_output(['sing-box', 'generate', 'reality-keypair'], text=True)
    keys = {}
    for line in output.splitlines():
        key, sep, value = line.partition(':')
        if sep:
            keys[key.strip().replace(' ', '').replace('_', '').lower()] = value.strip()
    credentials = dict(uuid=str(uuid.uuid4()), private_key=keys['privatekey'],
                       public_key=keys['publickey'], short_id=secrets.token_hex(4),
                       servername='www.microsoft.com')
    credentials_path.write_text(json.dumps(credentials, indent=2) + '\n')
    os.chmod(credentials_path, 0o600)
config = {
    'log': {'level': 'info', 'timestamp': True},
    'inbounds': [{
        'type': 'vless', 'tag': 'reality-in', 'listen': '0.0.0.0', 'listen_port': 443,
        'users': [{'uuid': credentials['uuid'], 'flow': 'xtls-rprx-vision'}],
        'tls': {'enabled': True, 'server_name': credentials['servername'], 'reality': {
            'enabled': True,
            'handshake': {'server': credentials['servername'], 'server_port': 443},
            'private_key': credentials['private_key'], 'short_id': [credentials['short_id']],
        }},
    }],
    'outbounds': [{'type': 'direct', 'tag': 'direct'}],
}
path = pathlib.Path('/etc/sing-box/config.json')
path.write_text(json.dumps(config, indent=2) + '\n')
os.chown(path, 0, grp.getgrnam('sing-box').gr_gid)
os.chmod(path, 0o640)
client = {key: value for key, value in credentials.items() if key != 'private_key'}
client_path = pathlib.Path('/root/myvpn-client.json')
client_path.write_text(json.dumps(client, indent=2) + '\n')
os.chmod(client_path, 0o600)
PY

sing-box check -c /etc/sing-box/config.json
if ! iptables -C INPUT -p tcp --dport 443 -m conntrack --ctstate NEW -j ACCEPT 2>/dev/null; then
  reject_line=$(iptables -L INPUT -n --line-numbers | awk '/REJECT/{print $1; exit}')
  [[ -n $reject_line ]] || { echo '未找到兜底 REJECT，请先核对防火墙布局。' >&2; exit 1; }
  iptables -I INPUT "$reject_line" -p tcp --dport 443 -m conntrack --ctstate NEW -j ACCEPT
fi
netfilter-persistent save
systemctl enable --now sing-box
systemctl restart sing-box
for attempt in {1..10}; do
  if ss -lntp | grep ':443 '; then break; fi
  sleep 1
done
systemctl is-active sing-box
systemctl is-enabled sing-box
ss -lntp | grep ':443 '
sing-box version
