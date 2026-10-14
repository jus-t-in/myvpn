# 从申请甲骨文实例到验证代理节点

本教程按 myVPN 的实际部署方案，串起 Oracle Cloud 实例申请、SSH 连接、Ubuntu 配置、节点安装、订阅分发和客户端测试。完成后，你会得到两个直连节点：**VLESS-REALITY（TCP 443）** 和 **Hysteria2（UDP 443）**，由客户端按规则分流。

本项目在 2026-10-11 实际部署于 Phoenix 的 E2.1.Micro，使用 Ubuntu 24.04。A1.Flex 当时容量不足，本教程保留 A1 优先、Micro 备用的选择。云平台菜单、免费额度与容量可能变化，创建时以当前控制台的提示为准。

阅读路径：[申请实例](#1-创建网络和申请实例) → [云端入站规则](#2-配置-oci-入站规则) → [SSH 连接](#3-配置-ssh-并首次连接) → [系统基线](#4-配置-ubuntu-系统基线) → [安装节点](#5-安装-sing-box-节点) → [制作配置](#6-取回配置并制作双节点订阅) → [部署订阅](#7-部署订阅分发服务) → [客户端导入](#8-导入并激活客户端) → [节点测试](#9-分层测试节点)。

## 0. 准备与阅读约定

需要准备：

- 已能登录控制台的 Oracle Cloud 账号；尚未注册时，先通过 [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/) 入口完成注册、邮箱及付款方式验证，再进入控制台。
- 一台本机，具备 Bash、OpenSSH（`ssh` / `scp`）、`curl`、`openssl` 和 `sha256sum`。下文以 Linux 为例；Windows 可使用 WSL，macOS 可用 `shasum -a 256` 替代 `sha256sum`。
- 本项目目录，以及 `.audit/sb.sh` 的已审计副本。该副本被忽略，不随仓库分发；获取和校验方法见第 5 节。
- 支持 Reality、Hysteria2 和证书指纹校验的客户端：本教程以 Clash Verge Rev 和 FlClash 使用的 Mihomo 配置为例。

**本机**指你的电脑；**服务器**指 OCI 实例。每个命令块前都标明执行位置。本机涉及项目文件的命令均在项目根目录执行，服务器的系统配置命令使用 `sudo -i` 后的 root shell。

`<服务器公网IP>`、`<UUID>` 等是待替换的占位符。不要把文档中的占位符原样粘贴为配置，也不要复用旧部署记录中的 IP、公钥或节点凭据。

先在本机准备目录：

```bash
cd myVPN
mkdir -p .audit .secrets/sub
chmod 700 .secrets
```

私钥、节点配置、订阅 URL 和 token 保存在本机，不公开。下面只写操作方法，不包含现有实例凭据。

## 1. 创建网络和申请实例

本节按实例创建向导的顺序填写。Oracle 会调整中文翻译和页面布局，遇到名称略有不同的字段时，以括号中的英文关键词和字段含义定位。先不要点最后的「创建」：等各步骤都核对完再提交。

### 1.1 打开创建向导并选区域

1. 登录 OCI 控制台，在顶部区域菜单选择准备部署的区域。本项目按 Phoenix（`US West (Phoenix)`）编写；实例、VCN 和子网必须位于同一区域。
2. 打开左上角导航菜单，进入「计算 → 实例」。确认页面显示的是目标区域和 compartment（区间）；compartment 不确定时使用账号默认的区间，不要为了本教程新建区间。
3. 点击「创建实例」。实例名称填 `myvpn`。名称仅用于控制台识别，不是 SSH 地址或域名。

如果页面顶部提示免费套餐账号需要升级才能访问某些资源，先阅读该账号提示和创建页面的费用信息。不要为了继续向导而确认升级、付款或计费授权；本教程不要求执行账号升级。

### 1.2 选择形状（机型）

在「形状 / Shape」区域点击「更改形状」，按下面顺序尝试：

1. 选择 Ampere 系列，再选择 `VM.Standard.A1.Flex`。点选形状行后，如果没有看到 CPU 和内存输入项，展开该行的详细配置。
2. 将 OCPU 数设为 `2`、内存设为 `12 GB`，然后点「选择形状 / Select shape」返回向导。A1 使用 ARM64 架构；后面的 Ubuntu 映像要与之匹配。
3. 若提交时提示所选可用性域没有容量，可返回形状或可用性域选择，在该区域的其他可用性域重试，也可稍后重试。不要仅为消除容量错误而增加 OCPU 或内存。
4. A1 在所有可用性域都无容量时，改试 `VM.Standard.E2.1.Micro`：在形状选择器中切换到 Intel / x86 形状系列，选择 Micro（固定 1 OCPU、1 GB 内存）。如果列表中没有该形状，或该可用性域也无容量，先停止创建并确认该区域的可用形状；不要改选付费形状。

本项目预期优先使用 A1 的 2 OCPU / 12 GB；部署记录中 A1 当时无容量，实际使用了 E2.1.Micro。免费额度、账户资格和可用容量可能变化，应以页面中的 Always Free 标记、配额与费用估算为准。创建前确认费用估算符合预期；不要假设未标记为免费额度内的资源不会收费。

### 1.3 选择 Ubuntu 映像

在「映像和配置 / Image and shape」区域点击「更改映像」，按以下条件选择：

1. 选择 Canonical 的 Ubuntu。
2. 版本选 Ubuntu 24.04；选择标准映像，不选 Minimal。
3. 检查映像架构与形状一致：A1 选择 ARM64 / aarch64，E2.1.Micro 选择 AMD64 / x86_64。若页面已按形状自动筛选，仍检查映像说明中的架构。
4. 点「选择映像」返回创建向导。镜像默认登录用户名是 `ubuntu`。

### 1.4 选择 VCN、子网并启用公网 IPv4

在「主要网络 / Primary VNIC」区域选择网络：

1. 选择「选择现有虚拟云网络」。从 VCN 列表中选目标网络，再选择其公共子网。不要选仅供私有网络使用的子网。
2. 如果尚无 VCN，先取消或保留当前向导页，进入「网络 → 虚拟云网络」，使用「创建 VCN」中的 Internet 连接向导创建带 Internet 网关、路由表和公共子网的网络，再返回实例向导选择它。不要同时创建一套重复网络。
3. 对照网络配置确认 VCN 有已启用的 Internet 网关，所选子网关联的路由表有 `0.0.0.0/0 → Internet 网关`，且子网允许分配公共 IP。具体检查方式见第 1.5 节。
4. 打开「自动分配公共 IPv4 地址」。公网地址先使用自动分配的临时 IP 即可，本教程没有要求预留或购买保留 IP。

若公网 IPv4 开关关闭、不可编辑，或提示必须选择公共子网，通常是所选子网不是公共子网，或 VCN / 路由配置未完成。返回网络页面确认 Internet 网关、路由表和子网属性，再回向导选择正确的子网；不要继续创建一台没有公网地址的实例。

### 1.5 网络前置检查

已有 VCN 时先检查，不要重复创建。进入「网络 → 虚拟云网络 → 目标 VCN」，确认：

1. VCN 已启用 Internet 网关。
2. 创建实例所选子网关联的路由表中有目的地 `0.0.0.0/0`、目标为 Internet 网关的规则。
3. 所选子网是公共子网，允许 VNIC 分配公共 IPv4。

本项目当前账号的 VCN 名称显示为 `1`、子网也显示为 `1`；名称只是本账号的既有资源标识，其他账号不要照抄。该网络最初因没有 Internet 网关和默认路由而无法启用公网 IPv4，补齐后子网才显示为公共子网。新建网络时使用控制台 Internet 连接向导通常会一并创建这些组件。

### 1.6 添加 SSH 公钥

**本机执行**。已有专用密钥时直接使用，不要覆盖现有密钥；首次创建可生成一把：

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/oci_myvpn -C myvpn-oracle
chmod 600 ~/.ssh/oci_myvpn
cat ~/.ssh/oci_myvpn.pub
```

按提示设置密钥口令（可留空）。在向导「添加 SSH 密钥」中选择「粘贴公钥 / Paste public keys」，把 `cat` 输出的**整行公钥**粘贴进去。不要上传或粘贴没有 `.pub` 后缀的私钥文件；私钥只留在本机。

### 1.7 检查引导卷并提交

展开「引导卷 / Boot volume」设置：

1. 初次部署保留默认卷性能和加密设置；如页面显示卷大小，确认其在账号免费额度及费用估算范围内，不需要为本教程额外扩大。
2. 不启用额外的性能配置或备份选项，除非你已确认其费用和用途。
3. 点创建前逐项复核：实例名称 `myvpn`；形状为 A1.Flex `2 OCPU / 12 GB` 或容量不足时的 E2.1.Micro；Ubuntu 24.04 与形状架构匹配；VCN 和公共子网正确；自动分配公共 IPv4 已启用；粘贴的是 SSH 公钥；费用估算符合预期。
4. 点击「创建」。等实例状态从 `Provisioning` 变成 `Running`。进入实例详情，记录公共 IPv4 地址和所用形状；后续连接使用该地址。

如果创建失败，先记录页面显示的错误，再按错误类型处理：容量错误回到 1.2；无公共 IP 或公共子网错误回到 1.4–1.5；配额或费用错误先检查账号额度和资源配置。不要在错误原因不明时重复创建多个实例。

**本阶段通过标准**：实例状态为 `Running`，详情页显示公共 IPv4，Ubuntu 版本和 CPU 架构与所选形状匹配。此时还未配置云端入站端口，SSH 是否可连要到第 2 节核对安全规则后再验证。

## 2. 配置 OCI 入站规则

进入实例所用 VCN，找到**公共子网关联的安全列表**，添加或确认以下有状态入站规则。若 VNIC 还关联 NSG（网络安全组），一并核对其规则。

| 用途 | IP 协议 | 目标端口 | 源 CIDR |
| --- | --- | --- | --- |
| SSH | TCP | 22 | 本机出口 IP 的 `/32`；动态网络可按需调整 |
| Reality | TCP | 443 | `0.0.0.0/0` |
| Hysteria2 | UDP | 443 | `0.0.0.0/0` |
| 订阅分发 | TCP | 8443 | `0.0.0.0/0` |

源端口范围保留全部；填写的是**目标端口**。「无状态」不勾选。SSH 默认规则若已存在，可保留并确认能够从本机连接。出站规则应允许节点访问互联网。

TCP 443 和 UDP 443 是两条独立规则。安装脚本生成的 VMess / TUIC / AnyTLS 高位端口不放行。

此处只是云端防火墙，服务器内还有主机防火墙，第 4 节会单独配置。

## 3. 配置 SSH 并首次连接

**本机操作**：编辑 `~/.ssh/config`，添加以下段落；已有 `Host myvpn` 时修改其内容，不重复添加：

```sshconfig
Host myvpn
    HostName <服务器公网IP>
    User ubuntu
    IdentityFile ~/.ssh/oci_myvpn
    IdentitiesOnly yes
```

设置权限并连接：

```bash
chmod 600 ~/.ssh/config
ssh myvpn
```

首次连接会提示服务器主机指纹。确认目标实例、IP 和指纹来源后接受并保存；已有主机指纹突然变化时，先确认是否重建或迁移，不要直接忽略提示。

**服务器执行**：

```bash
whoami
uname -m
sudo -v
```

预期用户为 `ubuntu`；Micro 的架构为 `x86_64`，A1 为 `aarch64`；`sudo -v` 成功。

普通用户不能直接写 `/root`。后续文件先上传到 `/tmp`，再通过 `sudo install` 放到目标位置。也无需启用 root 的远程登录。

**本阶段通过标准**：`ssh myvpn` 可以使用密钥登录，远端可执行 sudo。

## 4. 配置 Ubuntu 系统基线

### 4.1 更新系统与安装依赖

**服务器执行**：

```bash
sudo -i
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  jq cron socat busybox iptables-persistent curl openssl iptables tar \
  expect wget xxd python3 qrencode git unattended-upgrades logrotate
```

升级中若有配置文件询问，先看变更内容再选择；不要覆盖自己已配置的 SSH / 防火墙设置。需要内核更新时，在这一步重启：

```bash
reboot
```

SSH 断开属正常现象。等待实例恢复后，在**本机**重新执行 `ssh myvpn`，再用 `sudo -i` 进入 root shell。

### 4.2 确认密钥登录并禁用密码登录

保留当前 SSH 会话，在**服务器 root shell**创建专用配置：

```bash
cat > /etc/ssh/sshd_config.d/00-myvpn.conf <<'EOF'
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
sshd -t
```

只有 `sshd -t` 成功后才执行：

```bash
systemctl reload ssh
sshd -T | grep -E '^(pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication) '
```

预期分别为 `yes`、`no`、`no`。如果生效结果不同，检查主配置和其他 drop-in 中的设置，先处理冲突。

此时另开一个**本机终端**执行 `ssh myvpn`，确认新连接成功，再关闭旧连接。

### 4.3 启用安全更新与 BBR

**服务器 root shell 执行**：

```bash
dpkg-reconfigure -plow unattended-upgrades
```

在提示中选择启用自动安全更新，并检查：

```bash
systemctl is-enabled unattended-upgrades
cat /etc/apt/apt.conf.d/20auto-upgrades
```

预期服务已启用，自动更新包列表和执行 unattended upgrade 的值为 `1`。

**本机项目根目录执行**，上传项目中的 BBR 配置：

```bash
scp server/99-bbr.conf myvpn:/tmp/myvpn-99-bbr.conf
```

**服务器 root shell 执行**：

```bash
install -m 644 /tmp/myvpn-99-bbr.conf /etc/sysctl.d/99-bbr.conf
rm /tmp/myvpn-99-bbr.conf
sysctl --system
sysctl net.core.default_qdisc net.ipv4.tcp_congestion_control
```

预期分别为 `fq`、`bbr`。如果内核不支持 BBR，先解决内核问题，不必运行第三方内核安装脚本。

### 4.4 配置主机防火墙

OCI Ubuntu 镜像通常预置 iptables，允许 SSH 后有一条 REJECT。**服务器 root shell**先查看：

```bash
iptables -L INPUT -n --line-numbers
```

确认 SSH 已放行，并存在兜底 REJECT。下面的代码只适用于这种布局，将 443 的规则插在 REJECT 前；没有 REJECT 或使用其他防火墙管理器时，应先确认实际规则结构。

```bash
reject_line=$(iptables -L INPUT -n --line-numbers | awk '/REJECT/{print $1; exit}')
if [ -z "$reject_line" ]; then
  echo '未找到 REJECT，停止；请先核对防火墙布局。'
else
  for protocol in tcp udp; do
    if ! iptables -C INPUT -p "$protocol" --dport 443 \
      -m conntrack --ctstate NEW -j ACCEPT 2>/dev/null; then
      iptables -I INPUT "$reject_line" -p "$protocol" --dport 443 \
        -m conntrack --ctstate NEW -j ACCEPT
    fi
  done
  netfilter-persistent save
fi
```

再查看一次 INPUT 链，确认 TCP / UDP 443 的 ACCEPT 在 REJECT 前面。8443 的主机规则由订阅部署脚本添加。

**本阶段通过标准**：重启后 SSH 仍可用，密码登录关闭，安全更新启用，BBR 配置生效，443 的主机规则已持久化。

## 5. 安装 sing-box 节点

### 5.1 准备并校验审计副本

本项目使用 [sing-box-yg](https://github.com/yonggekkk/sing-box-yg) 的审计副本，2026-10-11 保存的 `sb.sh` SHA-256 为：

```text
5961a0d9a9a4574df45b12567b0791bfb8af2ec815069b7508755236846602ba
```

**本机项目根目录执行**：

```bash
sha256sum .audit/sb.sh
```

若副本缺失，可先从上游下载到本地，**不要直接通过 curl 管道执行**：

```bash
curl -fL --retry 2 \
  https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh \
  -o .audit/sb.sh
sha256sum .audit/sb.sh
```

上游 `main` 会变化，下载文件不一定与本项目副本相同。**哈希不一致就停在这里**：取得对应审计副本，或重新审计新版并调整安装步骤后再继续。校验和只确认文件一致；脚本安装时仍会下载内核等依赖，不能据此宣称所有下载内容均已固定。

### 5.2 上传并安装

**本机执行**：

```bash
scp .audit/sb.sh myvpn:/tmp/myvpn-sb.sh
ssh myvpn 'sudo install -m 700 /tmp/myvpn-sb.sh /root/sb.sh && rm /tmp/myvpn-sb.sh && sudo sha256sum /root/sb.sh'
```

确认远端哈希与本机及上述值一致。进入**服务器 root shell**：

```bash
umask 077
bash /root/sb.sh
```

按照该审计版本的提示选择：

| 提示 | 选择 |
| --- | --- |
| 主菜单 | `1`，安装 |
| 是否开放端口、关闭防火墙 | `2`，跳过，自行处理 |
| sing-box 内核 | `1`，最新正式版 |
| 是否申请域名证书 | `1`，使用自签证书 |
| 端口方案 | `2`，自定义每个协议端口 |
| VLESS-REALITY | `443` |
| VMess | 回车，随机端口，不对外开放 |
| Hysteria2 | `443` |
| TUIC / AnyTLS | 各回车，随机端口，不对外开放 |

TCP 与 UDP 可以各用 443，不冲突。若提示端口占用，检查是否已有 Web 服务或旧节点，先处理实际占用，不要随意覆盖。

不启用 WARP-plus、Psiphon、Argo、GitLab 订阅和脚本菜单中的「本地 IP 订阅」。本项目用第 7 节的独立服务分发订阅。

### 5.3 安装后检查与收口

**服务器 root shell 执行**：

```bash
systemctl is-active sing-box
systemctl is-enabled sing-box
ss -lntup | grep ':443 '
journalctl -u sing-box -n 50 --no-pager
```

预期服务为 `active`、`enabled`，443 同时有 TCP 和 UDP 监听，日志中没有持续启动失败。

脚本会自行下载 `/usr/bin/sb`，用审计副本覆盖后复查：

```bash
install -m 755 /root/sb.sh /usr/bin/sb
sha256sum /usr/bin/sb
```

该脚本还会添加每日 01:00 UTC 的重启任务。先查看 root crontab：

```bash
crontab -l
```

用 `crontab -e` **仅删除下面这条任务**，保留其他任务：

```cron
0 1 * * * systemctl restart sing-box;rc-service sing-box restart
```

再次查看确认已删除。在本机保存配置前，还应在服务器上检查 `/etc/s-box/sb.json` 中的入站端口和 route 规则：Reality 为 TCP 443，Hysteria2 为 UDP 443，未启用 WARP 引流。服务器配置含凭据，检查时不要粘贴到公开渠道。

**本阶段通过标准**：服务开机自启，两种协议均在监听，管理脚本哈希正确，每日自动重启任务已移除。

## 6. 取回配置并制作双节点订阅

### 6.1 通过 SSH 取回配置

节点文件可能只有 root 能读取，因此使用 `sudo cat` 经 SSH 取回，不依赖普通用户直接 scp `/etc/s-box`。

**本机项目根目录执行**：

```bash
umask 077
for file in clmi.yaml sbox.json jhsub.txt vl_reality.txt hy2.txt; do
  ssh myvpn "sudo cat /etc/s-box/$file" > ".secrets/$file" || break
done
```

确认五个文件均已成功取回且不为空。有失败时先查看 SSH 错误，不要继续使用空文件。

`clmi.yaml` 是脚本生成的 Clash / Mihomo 配置；`sbox.json` 是 sing-box 客户端配置；两个 `.txt` 文件是 Reality、Hysteria2 的分享链接。

### 6.2 获取节点参数与证书指纹

在本机私下查看 `.secrets/clmi.yaml`，分别读取 Reality 的 `server`、`uuid`、`servername`、`public-key`、`short-id`，以及 Hysteria2 的 `password` 和 `sni`。

获取 Hysteria2 服务器证书的 SHA-256 指纹，**本机执行**：

```bash
ssh myvpn 'sudo openssl x509 -in /etc/s-box/cert.pem -noout -fingerprint -sha256'
```

复制等号后的指纹并去掉冒号，用于下面的 `fingerprint`。这是完整证书的指纹，不是 Reality 公钥，也不是 `client-fingerprint: chrome`。

审计脚本默认生成的 Clash 配置包含未开放的协议，且自签 Hysteria2 会设置 `skip-cert-verify: true`。直接拿它的自动选择组使用，会混入不可用节点。下面另建一份双节点配置，并用证书指纹校验替代跳过校验。Mihomo 字段说明见[官方 TLS 配置文档](https://wiki.metacubex.one/config/proxies/tls/)。

### 6.3 写入客户端配置

**本机操作**：将下面内容保存为 `.secrets/sub/myvpn.yaml`，替换全部 `<...>` 参数。节点参数从上一步的实际输出复制，不能凭空填值；两个协议的密码 / UUID 分别按生成结果填写。

```yaml
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info

dns:
  enable: true
  listen: 127.0.0.1:1053
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*.lan'
    - '*.local'
  respect-rules: true
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  proxy-server-nameserver:
    - 223.5.5.5
  nameserver:
    - https://1.1.1.1/dns-query
  nameserver-policy:
    'geosite:cn':
      - 223.5.5.5
      - 119.29.29.29

proxies:
  - name: Reality
    type: vless
    server: '<服务器公网IP>'
    port: 443
    uuid: '<UUID>'
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: '<Reality的servername>'
    reality-opts:
      public-key: '<Reality公钥>'
      short-id: '<Reality的short-id>'
    client-fingerprint: chrome

  - name: Hysteria2
    type: hysteria2
    server: '<服务器公网IP>'
    port: 443
    password: '<Hysteria2密码>'
    sni: '<Hysteria2的sni>'
    alpn:
      - h3
    skip-cert-verify: false
    fingerprint: '<证书SHA256指纹，无冒号>'

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - Reality
      - Hysteria2

rules:
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - GEOSITE,cn,DIRECT
  - GEOIP,CN,DIRECT,no-resolve
  - MATCH,PROXY
```

这份配置使用国内域名 / IP 直连、其余走 `PROXY` 的规则，并使用客户端的 geosite / geoip 数据。导入时若提示数据文件缺失，先通过客户端更新地理数据；初次下载困难时可借助现有可用线路完成下载。

证书指纹由支持该功能的 Mihomo 内核验证，自签证书无需加入系统信任库。若客户端不支持或报字段错误，先升级到支持的版本，不要通过移除指纹或改成跳过校验来绕过。

**本阶段通过标准**：配置中无未替换占位符，只包含两个已开放节点，凭据与服务器匹配，Hysteria2 已填写证书指纹。

## 7. 部署订阅分发服务

订阅服务只提供 `/<token>/myvpn.yaml`，默认监听 TCP 8443，由 systemd 以 `nobody` 运行。OCI 的 TCP 8443 入站规则应已在第 2 节放行。

**本机项目根目录执行，首次部署时**生成并保存 token：

```bash
umask 077
openssl rand -hex 16 > .secrets/sub-token.txt
bash server/deploy-sub.sh "$(cat .secrets/sub-token.txt)"
chmod 600 .secrets/sub/myvpn.yaml .secrets/sub-url.txt .secrets/sub-token.txt
```

这里生成 32 位随机十六进制 token。已有部署时应复用原 token，**不要重新运行生成命令**。更新 `.secrets/sub/myvpn.yaml` 后只运行部署命令即可。

脚本会上传文件、安装服务、放行主机 iptables 的 8443、持久化规则并检查监听；它不会替你配置 OCI 安全列表。脚本依赖第 4 节中带 REJECT 的 INPUT 链布局。

订阅 URL 写入 `.secrets/sub-url.txt`，形如：

```text
http://<服务器公网IP>:8443/<token>/myvpn.yaml
```

**本机验证**，绕开已有本地代理，避免将旧节点的线路误当成直连测试结果：

```bash
subscription_url=$(cat .secrets/sub-url.txt)
curl --noproxy '*' --connect-timeout 10 --max-time 30 --fail \
  "$subscription_url" -o .secrets/sub/downloaded.yaml
sha256sum .secrets/sub/myvpn.yaml .secrets/sub/downloaded.yaml
curl --noproxy '*' --connect-timeout 10 --max-time 15 \
  -s -o /dev/null -w '%{http_code}\n' "${subscription_url%/*}/not-a-file.yaml"
```

预期有效地址下载成功，两个文件哈希一致，错误路径返回 `404`。订阅服务也支持 HEAD，但测试配置内容时使用 GET。

**订阅 HTTP 未加密，完整 URL 相当于口令，文件中含节点凭据。** Token 可以限制猜测路径，无法防止链路嗅探。这是现有方案的取舍，不能把 8443 端口号当作 HTTPS。若不接受这一取舍，可直接在客户端本地导入第 6 节的文件。

换 IP、端口或 token 时，需要更新客户端保存的订阅 URL；仅修改同一 URL 下的节点配置，才可以依靠自动订阅更新同步。

**本阶段通过标准**：`myvpn-sub` 服务运行，有效 URL 返回一致的配置内容，错误路径返回 404。

## 8. 导入并激活客户端

### 8.1 电脑：Clash Verge Rev

1. 在订阅 / 配置页添加远程订阅，粘贴 `.secrets/sub-url.txt` 中的地址，下载配置。
2. 也可选择本地导入 `.secrets/sub/myvpn.yaml`，这种方式不会自动更新。
3. 激活新配置，确认出现 `Reality`、`Hysteria2` 和 `PROXY` 选择组。
4. 选择**规则模式**，先手动选择 `Reality`。
5. 打开系统代理，核对客户端当前 HTTP / Mixed 端口。模板写的是 7890，桌面客户端可能有全局端口覆盖。

需要接管不遵循系统代理的应用时，再启用 TUN 并授予客户端相应权限。首次测试可先使用系统代理和下一节的显式 curl 代理，便于定位问题。

### 8.2 Android：FlClash

1. 添加远程配置，粘贴订阅 URL，下载并激活。
2. 使用规则模式，在 `PROXY` 组选择 `Reality`。
3. 启动代理，接受 Android 的 VPN 权限提示。
4. 关闭 Wi-Fi，先用蜂窝网络完成节点测试，再测试 Wi-Fi。

Android 的 VPN 权限是客户端接管流量的方式，本项目服务器仍是代理节点。

其他平台先确认客户端支持协议和配置格式。Windows 可使用 Clash Verge Rev；iPhone 可用支持这两种协议及证书校验的客户端，例如 Karing，并按其支持的格式导入，不能假定任意客户端都能读取同一份 Mihomo YAML。

**本阶段通过标准**：配置已激活，规则模式已启用，能手动切换两种节点，客户端无配置解析错误。

## 9. 分层测试节点

不要只看「订阅下载成功」或一个延迟数值。订阅分发、端口连通和协议代理是不同层面的验证。

### 9.1 服务器服务和监听

**本机执行**：

```bash
ssh myvpn 'systemctl is-active sing-box myvpn-sub'
ssh myvpn 'sudo ss -lntup'
ssh myvpn 'sudo journalctl -u sing-box -u myvpn-sub -n 50 --no-pager'
```

两个服务均应为 `active`；sing-box 监听 TCP / UDP 443，订阅服务监听 TCP 8443。

本机如已安装 `nc`，可额外检查 Reality 的 TCP 端口：

```bash
server_ip=$(ssh -G myvpn | awk '/^hostname /{print $2}')
nc -vz -w 5 "$server_ip" 443
```

TCP 建连成功只能证明端口可达。普通 HTTPS 请求或 TLS 握手不能验证 Reality 的 UUID、公钥和 short-id；UDP 端口扫描也不能代替 Hysteria2 的实际协议连接。

### 9.2 分别验证 Reality 与 Hysteria2

先在客户端 `PROXY` 组**固定选择 Reality**，然后在**本机**通过客户端代理端口请求测试地址。若实际端口不是 7890，替换下列端口：

```bash
curl --noproxy '' --proxy http://127.0.0.1:7890 \
  --connect-timeout 10 --max-time 30 -sS -o /dev/null \
  -w 'HTTP=%{http_code} connect=%{time_connect}s total=%{time_total}s\n' \
  https://www.gstatic.com/generate_204

curl --noproxy '' --proxy http://127.0.0.1:7890 \
  --connect-timeout 10 --max-time 30 -4 -sS https://api.ipify.org
```

第一条预期 `HTTP=204`，第二条返回代理出口 IP。`--noproxy ''` 防止本机 `NO_PROXY` 设置绕过显式代理。

可在服务器查询 IPv4 出口作对照：

```bash
ssh myvpn "curl --noproxy '*' -4 --connect-timeout 10 --max-time 30 -sS https://api.ipify.org"
```

第二条测试所得 IPv4 应与服务器出口一致。客户端连接页面应显示请求由 `PROXY → Reality` 处理。

接着**固定选择 Hysteria2，重新执行同样的两个请求**。确认日志 / 连接页面显示 `PROXY → Hysteria2`，而非自动回退到 Reality。相同测试请求经 Hysteria2 成功，可以验证客户端到服务器之间的 UDP 协议通道。

如果网站测试失败，先看客户端和服务器日志；单个外部测试服务自身不可用时，可换 Google / YouTube 实际访问作补充，不能仅据一次失败判定节点故障。

### 9.3 验证浏览器和手机实际使用

在电脑浏览器和 Android 蜂窝网络上，分别选择两种节点进行：

1. 打开 Google，完成搜索并进入一个结果页。
2. 打开 YouTube，播放视频，观察是否持续加载。
3. 连续使用约 10 分钟，记录延迟、播放分辨率、缓冲与断连情况。
4. 换 Wi-Fi 再测一次，比较 UDP 是否只在某个网络受限。

客户端延迟测试通常是经节点访问测试 URL 的耗时，curl 的 `connect` 在这里是连接本地代理的耗时，都不能直接等同于本机到服务器的网络 RTT。记录测试网络、所选协议和时间，速度没有统一合格数值，以实际用途是否满足为准。

### 9.4 验证国内分流和重启持久化

访问一个国内站点，在客户端连接页面查看命中的规则和出站：国内流量应为 `DIRECT`，Google / YouTube 应通过所选节点。

之后在维护窗口重启服务器，**本机执行**：

```bash
ssh myvpn 'sudo reboot'
```

服务器恢复后重新连接，核对公网 IP 和 SSH 别名，重复 9.1 和 9.2，并重新下载订阅。若公网 IP 已变化，先更新 SSH 配置、YAML 中的服务器地址、订阅部署及各客户端订阅 URL。

最终验收：

| 检查项 | 通过标准 |
| --- | --- |
| SSH | 密钥登录成功，密码登录关闭 |
| 节点服务 | sing-box 开机自启，TCP / UDP 443 均监听 |
| 订阅 | 有效 URL 下载成功且内容一致，错误路径 404 |
| Reality | 固定选中后，代理请求成功，出口与服务器相符 |
| Hysteria2 | 固定选中后，同样成功，连接页面确认使用该协议 |
| 真实使用 | 电脑和手机可搜索、播放视频并持续使用 |
| 分流 | 国内站点 DIRECT，境外目标通过所选节点 |
| 持久化 | 重启后服务、规则和节点测试仍通过 |

## 10. 可选：配置防闲置负载

这是已有项目的运维措施，不影响前面节点功能验收。闲置回收按 OCI 当前政策和监控指标判定，负载脚本不代表免回收保证，也会消耗实例资源。保持 Oracle Cloud Agent 的监控插件启用，在控制台查看实际指标。

### E2.1.Micro

当前实例采用每小时第 7 分运行 300 秒 CPU 负载、nice 19 的 cron。**本机项目根目录执行**：

```bash
bash server/deploy-cpuload.sh myvpn 7 300
ssh myvpn 'sudo cat /etc/cron.d/myvpn-cpuload'
ssh myvpn 'tail -n 20 /var/log/myvpn-cpuload.log'
```

部署会先做 5 秒负载自检，再由 cron 按计划运行。检查日志有成对的 `start` / `done`，并通过 OCI 控制台 CPU 曲线确认实际负载；也要在负载期间检查节点使用是否受影响。

### A1.Flex

本项目的 A1 预案为 12 GB 内存实例使用 3 GiB 常驻内存服务。**本机执行**：

```bash
scp server/oci-keepalive.py server/oci-keepalive.service myvpn:/tmp/
ssh myvpn 'sudo install -d /opt/oci-keepalive && sudo install -m 755 /tmp/oci-keepalive.py /opt/oci-keepalive/oci-keepalive.py && sudo install -m 644 /tmp/oci-keepalive.service /etc/systemd/system/oci-keepalive.service && sudo systemctl daemon-reload && sudo systemctl enable --now oci-keepalive.service'
ssh myvpn 'systemctl is-active oci-keepalive.service'
```

这个默认占用不适用于 1 GB 的 Micro；其他 A1 内存规格需要重新核算占用比例、可用内存与服务的 `MemoryMax`。两种措施的依据及取舍见[CPU 负载决策](adr/0003-cpu-load-cron-anti-reclaim.md)。

## 11. 常见故障与后续维护

| 现象 | 优先检查 |
| --- | --- |
| 创建实例容量不足 | 可用性域、机型容量；按第 1 节切换备用机型 |
| 公网 IP 开关不可选 | 子网公网 IP 限制、Internet 网关、子网所关联的路由表 |
| SSH 超时 | 公网 IP、路由、OCI TCP 22 规则、主机防火墙 |
| `Permission denied (publickey)` | `ubuntu` 用户、所选私钥、创建实例时粘贴的公钥 |
| 上传 `/root` 失败 | 使用第 5 节的 `/tmp` 上传 + sudo install |
| sing-box 启动失败 | journal 日志、端口冲突、配置与内核版本匹配情况 |
| 订阅超时 | 两层 TCP 8443 防火墙、myvpn-sub 状态、SSH 别名中的 IP |
| 订阅 404 | URL 中 token 和文件名是否正确，是否仍使用旧 URL |
| 客户端配置报错 | 占位符、YAML 缩进、Mihomo 版本、geosite / geoip 数据 |
| Reality 不通 | TCP 443、UUID、SNI、公钥、short-id、系统时间 |
| Hysteria2 不通 | UDP 443、网络是否限制 UDP、密码、SNI、证书指纹、系统时间 |
| 只有 Hysteria2 证书错误 | 指纹是否取自当前证书，重装后证书是否已变化 |
| curl 成功但浏览器失败 | 系统代理 / TUN、浏览器代理设置、客户端 DNS 和连接日志 |
| 迁移后订阅无法更新 | 新服务器地址、SSH 配置和客户端订阅 URL 是否已同步 |

订阅内容更新时复用 token：

```bash
bash server/deploy-sub.sh "$(cat .secrets/sub-token.txt)"
```

更换证书后更新 Hysteria2 指纹；迁移实例后更新所有服务器地址。节点脚本和内核升级前重新审计，不使用自动升级。

详细操作记录和回滚入口见[服务器部署手册](02-deploy-runbook.md)，订阅维护见[订阅分发说明](03-subscription.md)。卸载可通过审计副本的 `sb` 菜单操作；终止实例是删除云资源的独立操作，执行前先备份需要保留的配置并核对引导卷处理选项。
