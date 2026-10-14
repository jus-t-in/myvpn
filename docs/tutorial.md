# 从新建 OCI 实例到验证 Reality 节点

最小方案：**一个 Ubuntu 实例、官方 sing-box、一个 Reality / TCP 443 节点**。先本地导入验证；需要 FlClash 远程更新时再启用订阅。不安装多协议脚本、面板或负载任务。

本机示例为 Windows + Git Bash，项目在 `F:\tool\myvpn`。下面的本机命令在 **Git Bash** 执行；`<...>` 必须替换。浏览器使用有窗口模式，账号登录、验证码在网页完成。

## 1. 准备独立 SSH 密钥

本机：

```bash
cd /f/tool/myvpn
mkdir -p .secrets/ssh .secrets/sub
chmod 700 .secrets
test -f .secrets/ssh/oci_myvpn_new || \
  ssh-keygen -t ed25519 -f .secrets/ssh/oci_myvpn_new -C myvpn-new
cat .secrets/ssh/oci_myvpn_new.pub
```

创建向导只填写 `.pub` 的整行公钥，私钥留在本机。已有密钥不覆盖。本次操作实际使用的密钥文件名带 `20261014`，位置记录在本机 SSH 配置中。

## 2. 新建实例

登录 [OCI 控制台](https://cloud.oracle.com/)，确认账号**主区域**及 compartment，进入「计算 → 实例 → 创建实例」。本次主区域为 Phoenix；已有的旧实例另外保留。

当前向导顺序是：**基本信息 → 安全 → 网络 → 存储 → 复查**。

| 步骤 | 填写 |
| --- | --- |
| 基本信息 | 名称 `myvpn-new`；按需容量；更改配置，选 Ampere → `VM.Standard.A1.Flex`，1 OCPU / 6 GB |
| 映像 | Ubuntu → Canonical Ubuntu 24.04，标准版；A1 自动匹配 ARM64，复查时确认 |
| 安全 | 使用默认设置 |
| 网络 | 选择已有 VCN 与公共子网；自动分配公共 IPv4；SSH 选「粘贴公共密钥」 |
| 存储 | 默认引导卷大小、性能与加密，不额外附加卷 |
| 复查 | 核对形状、架构、公网 IPv4、公钥及剩余免费额度，再点创建 |

默认 E5.Flex 不是本流程的免费形状。A1 容量不足时换主区域内其他可用性域或稍后重试；备用 `VM.Standard.E2.1.Micro` 在「专业和上一代」系列，AMD / x86_64、1 GB，CPU 基线为 1/8 OCPU、可突发。Micro 只在该区域的一个可用性域提供，不照搬旧记录的 AD。

创建前核对**所有引导卷与块卷合计**额度，包括遗留卷。向导的引导卷估算可能未体现免费套餐，需结合账号剩余额度判断。[Oracle 免费资源说明](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)

**通过标准**：实例 `Running`，详情页显示公共 IPv4、正确形状与 Ubuntu 架构。

## 3. 核对网络与 SSH

### 公网网络

在所选子网核对：公共子网、允许公共 IP、已启用的 Internet 网关、关联路由表有 `0.0.0.0/0 → Internet 网关`。没有 VCN 时用 Internet 连接向导创建。

私有子网不能靠添加网关和路由变成公共子网；选错时应改选或新建公共子网。[Oracle 子网说明](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/Overview_of_VCNs_and_Subnets.htm)

进入实例主 VNIC → 子网 → 关联安全列表，确认有状态入站规则，源端口保留全部：

| 用途 | 协议 / 目标端口 | 源 CIDR |
| --- | --- | --- |
| SSH | TCP 22 | 本机公网出口 `/32`；动态网络按需调整 |
| Reality | TCP 443 | `0.0.0.0/0` |
| 订阅（需要时） | TCP 8443 | `0.0.0.0/0` |

保留必要出站规则。若 VNIC 使用 NSG，一并核对；安全列表与 NSG 的允许规则取并集，服务器主机防火墙需单独配置。[Oracle 安全规则](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/securityrules.htm)

### 本机 SSH 配置

保存到 `.secrets/ssh/config`，替换 IP 和私钥实际路径：

```sshconfig
Host myvpn-new
    HostName <服务器公网IP>
    User ubuntu
    IdentityFile F:/tool/myvpn/.secrets/ssh/oci_myvpn_new
    IdentitiesOnly yes
    UserKnownHostsFile F:/tool/myvpn/.secrets/known_hosts
```

本机连接，首次核对 IP 并记录主机指纹，后续指纹意外变化时先查原因：

```bash
ssh -F .secrets/ssh/config myvpn-new
```

服务器执行：

```bash
whoami
uname -m
sudo -n true
cloud-init status
sudo sshd -T | grep -E '^(pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication) '
```

预期 `ubuntu`、A1 的 `aarch64`，sudo 成功、初始化 `done`；SSH 生效值为 `yes / no / no`。本次 Ubuntu 映像已禁用密码登录。

若直连 SSH 超时，但通过现有代理可连接，可临时在该 Host 下加以下管理路径（按实际安装路径和代理端口修改）：

```sshconfig
    ProxyCommand F:/tool/git/Git/mingw64/bin/connect.exe -H 127.0.0.1:7897 %h %p
```

这只解决 SSH 管理连接；新节点仍需单独做直连验收。

## 4. 安装单个 Reality

项目的 [setup-reality.sh](../server/setup-reality.sh) 按本次实际操作安装官方 APT 包，生成随机 UUID / Reality 密钥，配置 TCP 443，放行主机防火墙并启用 systemd。仅用于新建的 OCI Ubuntu 实例，要求默认 INPUT 链已有 SSH 放行和兜底 REJECT。

本机上传后在服务器运行：

```bash
scp -F .secrets/ssh/config server/setup-reality.sh myvpn-new:/tmp/setup-reality.sh
ssh -F .secrets/ssh/config myvpn-new 'sudo bash /tmp/setup-reality.sh'
```

脚本使用 [sing-box 官方仓库](https://sing-box.sagernet.org/installation/package-manager/)，不运行上游多协议安装脚本；核心包设为 hold，升级前手动检查。脚本保持 LF 换行，避免 Windows CRLF 造成 Bash 语法错误。

| 服务器文件 | 用途 |
| --- | --- |
| `/etc/sing-box/config.json` | 服务端配置，root:sing-box、0640 |
| `/root/myvpn-reality-credentials.json` | 原始凭据，含服务器私钥，0600 |
| `/root/myvpn-client.json` | 客户端所需参数，不含服务器私钥，0600 |

本机检查：

```bash
ssh -F .secrets/ssh/config myvpn-new 'systemctl is-active sing-box; systemctl is-enabled sing-box; sudo ss -lntp'
ssh -F .secrets/ssh/config myvpn-new 'sudo journalctl -u sing-box -n 20 --no-pager'
```

**通过标准**：`active / enabled`，sing-box 监听 TCP 443，无持续启动错误。当前官方包使用 `sing-box` 用户运行；配置权限需让该用户可读。

## 5. 制作客户端配置

本机经 SSH 取回参数：

```bash
umask 077
ssh -F .secrets/ssh/config myvpn-new 'sudo cat /root/myvpn-client.json' > .secrets/myvpn-client.json
```

确认文件非空。将以下 YAML 保存为 `.secrets/sub/myvpn.yaml`，从 JSON 复制 UUID、公钥、short-id、servername，填入当前公网 IP。只复制到本地文件，不公开凭据。

```yaml
mixed-port: 7897
allow-lan: false
mode: rule
log-level: info
ipv6: false

dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-filter: ['*.lan', '*.local']
  respect-rules: true
  default-nameserver: [223.5.5.5, 119.29.29.29]
  proxy-server-nameserver: [223.5.5.5]
  nameserver: [https://1.1.1.1/dns-query]
  nameserver-policy:
    'geosite:cn': [223.5.5.5, 119.29.29.29]

proxies:
  - name: myvpn-new-Reality
    type: vless
    server: '<服务器公网IP>'
    port: 443
    uuid: '<uuid>'
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: '<servername>'
    reality-opts:
      public-key: '<public_key>'
      short-id: '<short_id>'
    client-fingerprint: chrome

proxy-groups:
  - name: PROXY
    type: select
    proxies: [myvpn-new-Reality]

rules:
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - GEOSITE,cn,DIRECT
  - GEOIP,CN,DIRECT,no-resolve
  - MATCH,PROXY
```

客户端需有 geosite / geoip 数据，首次缺失时先更新。端口 7897 是本次 Clash Verge 的实际端口，按客户端设置调整。字段见 [Mihomo VLESS](https://wiki.metacubex.one/config/proxies/vless/)。

## 6. 导入并验证

电脑在 Clash Verge Rev 本地导入并激活 YAML，使用规则模式，选择 `myvpn-new-Reality`。FlClash 可本地导入；需要远程订阅时按[订阅说明](03-subscription.md)部署。

FlClash 的实际操作：

1. 在「配置」添加完整订阅 URL，确认下载。默认名称可能是一串时间戳，可自行改名。
2. 点选新配置，使其高亮；进入「代理」，确认 `PROXY` 中只有 `myvpn-new-Reality`。
3. 在「仪表盘」启动服务，首次按系统提示允许 VPN；使用规则模式。运行计时和网络检测出口出现后，再做下面的实际请求。

**订阅 HTTP 200 只证明配置下载成功，不证明节点通过。** 手机先关闭 Wi-Fi，用蜂窝网络测；需要在 Wi-Fi 使用时再单独验证该网络。

电脑在本机 Bash 中通过实际代理端口请求：

```bash
curl --noproxy '' --proxy http://127.0.0.1:7897 \
  --connect-timeout 10 --max-time 30 -sS -o /dev/null \
  -w 'HTTP=%{http_code} total=%{time_total}s\n' https://www.gstatic.com/generate_204
curl --noproxy '' --proxy http://127.0.0.1:7897 \
  --connect-timeout 10 --max-time 30 -4 -sS https://api.ipify.org
ssh -F .secrets/ssh/config myvpn-new "curl --noproxy '*' -4 -sS https://api.ipify.org"
```

第一项预期 204，后两项出口 IPv4 相同；连接页应显示选中的新节点。再用浏览器 Google 搜索；访问国内站点应命中 `DIRECT`。单个延迟值、TCP 建连或普通 TLS 握手不能代替这些验证。

需要视频时补测实际播放，记录时长、缓冲及平台限制。[MDN WebM 样片](https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.webm)可用于基础播放检查，但只有约 5 秒，不能证明持续吞吐；按实际用途再连续播放至少 30 秒。YouTube 要求登录确认非机器人时，只能记录页面可达，不能写成播放成功。

在维护窗口重启，恢复后复查服务、订阅及实际代理：

```bash
ssh -F .secrets/ssh/config myvpn-new 'sudo reboot'
```

**最小通过标准**：密钥登录、服务自启、正确出口、实际搜索、国内直连、手机蜂窝网络和重启验证。视频、Wi-Fi 等使用场景单独记录结果；未测试的项标记「待验证」。

## 7. 直连失败怎么处理

| 现象 | 下一步 |
| --- | --- |
| 订阅一直加载 | 先从同一手机直接下载 URL，区分 TCP 超时、HTTP 404 和 YAML 错误 |
| 国内站点正常，新 IP 的 22/443/8443 均超时 | 核对两层防火墙；再对比经已有代理访问，判断公网线路可达性 |
| 订阅能下载，Reality 不通 | 核对 TCP 443、UUID、SNI、公钥、short-id 与客户端日志 |
| 换公网 IP | 更新 SSH HostName、YAML 的 server、服务器订阅副本，以及每台客户端的订阅 URL |

更换临时 IP 的实际路径：实例 → 网络 → 附加的主 VNIC → IP 管理 → 主 IPv4 行「操作 → 编辑」；先选「没有公共 IP」并更新，等完成，再编辑选「临时公共 IP」并更新。仅对可中断的新实例操作；停止 / 重启本身不会自动换 IP。[Oracle 公网 IP 说明](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/managingpublicIPs.htm)

普通 Cloudflare 橙云代理支持 HTTP(S) / WebSocket，不能直接承载当前 Reality 握手。需要 CDN 中转时改用兼容的 WebSocket + TLS 节点并配置域名；只代理订阅文件不能修复节点数据线路。[代理限制](https://developers.cloudflare.com/dns/proxy-status/limitations/)、[WebSocket 支持](https://developers.cloudflare.com/network/websockets/)

本次操作状态与后续维护见[维护手册](02-deploy-runbook.md)。
