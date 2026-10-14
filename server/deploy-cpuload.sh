#!/usr/bin/env bash
# 把"防闲置回收"CPU 负载 cron 部署到节点服务器（E2.1.Micro 用；A1 用 oci-keepalive）。
# 用法: server/deploy-cpuload.sh [ssh-host] [minute] [duration-seconds]
#   - 幂等，可重复执行；重跑即重置 cron 触发分钟与负载时长。
#   - 安装：/opt/myvpn-cpuload/oci-cpu-load.sh、/etc/cron.d/myvpn-cpuload、
#     /etc/logrotate.d/myvpn-cpuload；日志 /var/log/myvpn-cpuload.log。
#   - 卸载：sudo rm /etc/cron.d/myvpn-cpuload /etc/logrotate.d/myvpn-cpuload
#           sudo rm -r /opt/myvpn-cpuload /var/log/myvpn-cpuload.log
set -euo pipefail

HOST="${1:-myvpn}"
MINUTE="${2:-7}"
DURATION="${3:-300}"
DIR=/opt/myvpn-cpuload
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "== 上传负载脚本 =="
ssh "$HOST" "sudo install -d -m 755 $DIR"
scp -q "$ROOT/server/oci-cpu-load.sh" "$HOST:/tmp/oci-cpu-load.sh"
ssh "$HOST" "sudo install -m 755 -o root -g root /tmp/oci-cpu-load.sh $DIR/oci-cpu-load.sh && rm -f /tmp/oci-cpu-load.sh"

echo "== 安装 cron（每小时第 $MINUTE 分，满负载 ${DURATION}s）=="
ssh "$HOST" "sudo tee /etc/cron.d/myvpn-cpuload >/dev/null \
  && sudo chown root:root /etc/cron.d/myvpn-cpuload && sudo chmod 644 /etc/cron.d/myvpn-cpuload" <<EOF
# myvpn: 防 Oracle Always Free 闲置回收——每小时满负载 $DURATION 秒，把 7 天
# CPU 95 分位拉到 20% 以上（依据与算式见 docs/02-deploy-runbook.md §3）。
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$MINUTE * * * * root nice -n 19 $DIR/oci-cpu-load.sh $DURATION >> /var/log/myvpn-cpuload.log 2>&1
EOF

echo "== 安装 logrotate =="
# Ubuntu 24.04 的 /var/log 组可写（root:syslog 775），logrotate 需要 su 指令才肯轮转。
ssh "$HOST" "sudo tee /etc/logrotate.d/myvpn-cpuload >/dev/null" <<'EOF'
/var/log/myvpn-cpuload.log {
  su root root
  weekly
  rotate 4
  compress
  missingok
  notifempty
}
EOF

echo "== 服务器自检 =="
ssh "$HOST" "
set -e
sudo touch /var/log/myvpn-cpuload.log
systemctl is-active cron
ls -l /etc/cron.d/myvpn-cpuload $DIR/oci-cpu-load.sh
sudo bash -n $DIR/oci-cpu-load.sh && echo '脚本语法 OK'
echo '== 冒烟：满负载 5 秒 =='
sudo nice -n 19 $DIR/oci-cpu-load.sh 5
"

echo "== 完成。cron: 每小时第 $MINUTE 分；日志: ssh $HOST 'tail /var/log/myvpn-cpuload.log' =="
