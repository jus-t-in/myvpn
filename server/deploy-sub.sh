#!/usr/bin/env bash
# 把订阅文件部署到节点服务器，并以 systemd 服务常驻对外提供（默认端口 8443/tcp）。
# 用法: server/deploy-sub.sh <token> [ssh-host] [port]
# 项目内 SSH 配置：MYVPN_SSH_CONFIG=.secrets/ssh/config bash server/deploy-sub.sh <token> myvpn-new
#   - 幂等，可重复执行；改了 .secrets/sub/myvpn.yaml 后重跑即完成"更新订阅"。
#   - 换 token 时旧目录需手动删：ssh myvpn 'sudo rm -rf /opt/myvpn-sub/<旧token>'
#   - 端口放行分两处：这里做服务器 iptables；OCI 安全列表在控制台加对应入站规则。
set -euo pipefail

TOKEN="${1:?用法: server/deploy-sub.sh <token> [ssh-host] [port]}"
HOST="${2:-myvpn}"
PORT="${3:-8443}"
MYVPN_SSH=(ssh)
MYVPN_SCP=(scp)
if [[ -n "${MYVPN_SSH_CONFIG:-}" ]]; then
  MYVPN_SSH+=(-F "$MYVPN_SSH_CONFIG")
  MYVPN_SCP+=(-F "$MYVPN_SSH_CONFIG")
fi
DIR=/opt/myvpn-sub
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUB="$ROOT/.secrets/sub/myvpn.yaml"
[ -f "$SUB" ] || { echo "错误：找不到 $SUB" >&2; exit 1; }

echo "== 上传订阅文件与脚本 =="
"${MYVPN_SSH[@]}" "$HOST" "sudo install -d -m 755 $DIR $DIR/$TOKEN"
"${MYVPN_SCP[@]}" -q "$SUB" "$HOST:/tmp/myvpn.yaml"
"${MYVPN_SCP[@]}" -q "$ROOT/server/myvpn-sub.py" "$HOST:/tmp/myvpn-sub.py"
"${MYVPN_SSH[@]}" "$HOST" "sudo install -m 644 -o root -g root /tmp/myvpn.yaml $DIR/$TOKEN/myvpn.yaml \
  && sudo install -m 755 -o root -g root /tmp/myvpn-sub.py $DIR/myvpn-sub.py \
  && rm -f /tmp/myvpn.yaml /tmp/myvpn-sub.py"

echo "== 安装 systemd 单元 =="
sed -e "s|__DIR__|$DIR|g" -e "s|__TOKEN__|$TOKEN|g" -e "s|__PORT__|$PORT|g" \
  "$ROOT/server/myvpn-sub.service" \
  | "${MYVPN_SSH[@]}" "$HOST" "sudo tee /etc/systemd/system/myvpn-sub.service >/dev/null"
"${MYVPN_SSH[@]}" "$HOST" "sudo systemctl daemon-reload && sudo systemctl enable --now myvpn-sub.service && sudo systemctl restart myvpn-sub.service"

echo "== 放行 iptables $PORT/tcp（插到 REJECT 之前）=="
"${MYVPN_SSH[@]}" "$HOST" "bash -s" <<EOF
set -euo pipefail
if ! sudo iptables -C INPUT -p tcp --dport $PORT -m conntrack --ctstate NEW -j ACCEPT 2>/dev/null; then
  line=\$(sudo iptables -L INPUT -n --line-numbers | awk '/REJECT/{print \$1; exit}')
  sudo iptables -I INPUT "\$line" -p tcp --dport $PORT -m conntrack --ctstate NEW -j ACCEPT
fi
sudo netfilter-persistent save >/dev/null
EOF

echo "== 服务器本地自检 =="
"${MYVPN_SSH[@]}" "$HOST" "for attempt in 1 2 3 4 5; do
  if ss -tln | grep -q ':$PORT '; then echo '监听 OK: $PORT'; exit 0; fi
  sleep 1
done
echo '监听失败'; exit 1"

IP="$("${MYVPN_SSH[@]}" -G "$HOST" | awk '/^hostname /{print $2}')"
URL="http://$IP:$PORT/$TOKEN/myvpn.yaml"
echo "$URL" > "$ROOT/.secrets/sub-url.txt"
echo "== 完成。订阅地址（已写入 .secrets/sub-url.txt）："
echo "   $URL"
