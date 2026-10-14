# 服务器部署手册（我来执行，你可对照）

前提：实例已创建，安全列表已放行 22/tcp、443/tcp、443/udp、8443/tcp（订阅分发，见 docs/03-subscription.md），公网 IP 已知。

> 2026-10-11 实际：A1 无容量，当前实例是 **E2.1.Micro（x86_64，1 核 1 GB）**，公网 IP `<服务器公网IP>`，`ssh myvpn` 已可用。A1 抢到后按本手册在新机重跑一遍再迁移。命令对 amd64/arm64 通用，差异只在第 3 节的防闲置回收。

## 0. 本机准备

- `~/.ssh/config` 添加 `Host myvpn`（HostName = 公网 IP，User = ubuntu，IdentityFile = `~/.ssh/oci_myvpn`）。
- 首次 `ssh myvpn` 记录主机指纹。SSH 不走本机 Clash（OpenSSH 不读 proxy 环境变量）。

## 1. 系统基线（root）

1. `DEBIAN_FRONTEND=noninteractive apt update && apt full-upgrade -y`。
2. 预装脚本依赖，避免脚本内 apt 弹 debconf：`jq cron socat busybox iptables-persistent curl openssl iptables tar expect wget xxd python3 qrencode git`。
3. 确认 sshd `PasswordAuthentication no`；确认 `unattended-upgrades` 已启用。
4. BBR + fq：`/etc/sysctl.d/99-bbr.conf` 写 `net.core.default_qdisc=fq`、`net.ipv4.tcp_congestion_control=bbr`。
5. 主机防火墙：OCI 的 Ubuntu 镜像预置了 iptables（只放 22，末尾 REJECT）。在 REJECT 之前插入 443/tcp、443/udp 的 ACCEPT，`netfilter-persistent save`。

## 2. 运行 sing-box-yg（审计副本）

- `scp .audit/sb.sh myvpn:/root/sb.sh`，服务器上 `sha256sum` 必须等于 `5961a0d9a9a4574df45b12567b0791bfb8af2ec815069b7508755236846602ba`。
- 非交互驱动：

  ```bash
  printf '1\n2\n1\n1\n2\n443\n\n443\n\n\n' | DEBIAN_FRONTEND=noninteractive bash /root/sb.sh 2>&1 | tee /root/sb-install.log
  ```

  输入序列含义：`1` 安装 → `2` 不关防火墙 → `1` 最新正式版内核 → `1` 自签证书 → `2` 自定义端口 → Reality `443` → Vmess 回车随机 → Hy2 `443` → Tuic 回车随机 → AnyTLS 回车随机。
- 校验：`systemctl is-active sing-box`；`ss -tunlp | grep 443` 应有 tcp、udp 各一条；日志无 error。

## 3. 安装后收口

- 用审计副本覆盖 `/usr/bin/sb`（脚本用 `curl --insecure` 重下过一份），再校验 sha256。
- 删除脚本加的每日 01:00 UTC 重启 cron（北京时间 09:00 会闪断）。
- 检查 `/etc/s-box/sb.json`：inbounds 端口正确；route 规则默认不把流量导向 warp。
- 不执行"本地 IP 订阅"（菜单 3 → 8）；不装 WARP-plus/Argo；不开自动更新。
- 防闲置回收：Oracle 会回收 7 天内 CPU 95 分位 < 20%、网络 < 20%（A1 还要求内存 < 20%）同时成立的 Always Free 实例。保持 Oracle Cloud Agent 监控插件开启。
  - A1：部署 `server/oci-keepalive.service`（常驻占用 3 GiB 内存，CPU 几乎为零）让内存条件不成立。
  - **E2.1.Micro（当前）**：内存条件不适用、也只有 1 GB，占内存没用，只能靠 CPU。95 分位 ≥ 20% 只需要 5% 以上的时间 CPU 高于 20%，所以每小时跑 4～5 分钟满负载的 cron 任务即可，不影响日常使用（nice 19，转发优先）。2026-10-11 已装：`server/deploy-cpuload.sh [host] [minute] [duration]` 幂等部署 `/opt/myvpn-cpuload/oci-cpu-load.sh` + `/etc/cron.d/myvpn-cpuload`（默认每小时第 7 分、满负载 300 秒、nproc 个 worker）+ logrotate，日志 `/var/log/myvpn-cpuload.log`；卸载命令在脚本头注释，决策见 docs/adr/0003。
  - 更稳的办法仍是账户升级 Pay As You Go（免费额度不变）；升级落地后该 cron 可留（无害）可卸。

## 4. 取回客户端配置

- `scp myvpn:/etc/s-box/{clmi.yaml,sbox.json,jhsub.txt} ./.secrets/`（该目录含密钥，不入库、不外传）。
- 从 `jhsub.txt` 解出 Reality 与 Hy2 分享链接；在服务器上用 `qrencode` 生成二维码 PNG（本机未装）再 scp 回来供手机扫描；Clash YAML 供电脑导入。
- 订阅分发自 2026-10-11 起改为服务器常驻（systemd `myvpn-sub`，8443/tcp，只服务 `/opt/myvpn-sub/<token>/myvpn.yaml`）：改完 `.secrets/sub/myvpn.yaml` 后跑 `server/deploy-sub.sh <token>` 即完成更新，各设备粘订阅 URL 或 `clash://` 深链导入；详见 docs/03-subscription.md。

## 5. 实测顺序

1. Android（FlClash，蜂窝网络，不连 Wi-Fi）先：导入 → 开 Google / YouTube → 延迟、测速。
2. 本机：Clash Verge Rev 导入本地文件；`curl --noproxy '*'` 测裸线路到公网 IP:443 的握手时延。
3. Windows、iPhone（Karing）。

## 6. 回滚

- `sb` 菜单 2 卸载；或直接在控制台终止实例重建。

## 7. 实际执行记录（2026-10-11）

- §1 基线：apt 全量升级后重启，内核 `7.0.0-1013-oracle` 生效；`netfilter-persistent` active，443/tcp、443/udp 的 ACCEPT 规则重启后仍在；BBR+fq 生效；sshd 已禁密码登录、unattended-upgrades 已启用；Oracle Cloud Agent（snap 单元 `snap.oracle-cloud-agent.oracle-cloud-agent.service`）enabled + active。
- §2 安装：非交互驱动 `install_rc=0`；sing-box active 且已 enabled（开机自启）；443/tcp、443/udp 均在监听；journal 无 warning；`/etc/s-box/` 下生成了 `clmi.yaml`、`sbox.json`、`jhsub.txt` 及各协议分享链接文件。
- §3 收口：`/usr/bin/sb` 已用审计副本覆盖，sha256 与 `5961a0…02ba` 一致；已删除脚本写入根 crontab 的唯一一条 `0 1 * * * systemctl restart sing-box;rc-service sing-box restart`（删后 crontab 为空）；`/etc/s-box/sb.json` 五个 inbound 端口 443/11437/443/33276/65062 正确，warp 规则域名是占位符 `yg_kkk`、不引流；防闲置 keepalive 未装（待用户决定）。
- §4：客户端配置已取回本机 `./.secrets/`：`clmi.yaml`、`sbox.json`、`jhsub.txt`、`vl_reality.txt`、`hy2.txt`、`qr-vl-reality.png`、`qr-hy2.png`（两张二维码分别是 Reality 与 Hy2 的分享链接）。
- §5：本机 `curl --noproxy '*'` 直连 <服务器公网IP>:443 通过（TCP 0.61 s / TLS 1.43 s，HTTP 层有响应；服务器上只有 sing-box 监听 443）；手机、电脑、Windows/iPhone 的实测由用户完成。
- 补记（2026-10-11 15:15）：订阅分发上线——`myvpn-sub.service`（8443/tcp，token 32 位十六进制，地址见 `.secrets/sub-url.txt`）；iptables 与 OCI 安全列表各放行 8443/TCP；本机 curl 200（connect 1.4 s）且 sha256 一致、错误路径 404，手机独立网络 200；Clash Verge Rev 与手机 FlClash 经 `clash://install-config` 深链导入成功（在客户端侧待用户选用）。
- 补记（2026-10-11 16:45 北京时间）：防闲置回收 cron 上线——`/etc/cron.d/myvpn-cpuload` 每小时第 7 分 nice 19 满负载 300 秒（`/opt/myvpn-cpuload/oci-cpu-load.sh`，日志 `/var/log/myvpn-cpuload.log` 带 logrotate）。安装时先以「当前分钟+3」（第 40 分）实测：08:40:01 UTC 到点触发；负载期间 `vmstat` 显示 id=0（该 burstable 机型把超出基线的部分记为 steal，st≈75%，不影响"非空闲"口径）；OCI 控制台 oci_computeagent 的 CPU 占用率曲线在负载窗口的 5 个采样点为 94.6–100.7%，空闲时段约 0–2%（截图 docs/anti-reclaim-cpu-metric.png）——7 天窗口内约 8.3% 的时间远超 20%，95 分位条件被破坏。随后以默认第 7 分重跑部署脚本归一，最终状态即 §3 所述。决策见 docs/adr/0003。
