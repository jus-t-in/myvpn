# 控制台操作清单（你在浏览器里做）

> 私钥在本机 `~/.ssh/oci_myvpn`，绝不外传；下面是公钥，建实例时粘贴。

## 0. 网络前置（2026-10-11 已在控制台补好）

现有 VCN 在控制台里显示名为 **`1`**（DNS 域名 `vcn1.oraclevcn.com`，10.0.0.0/16），子网也叫 `1`（10.0.0.0/24，区域性）。它建好时**没有 Internet 网关、路由表为空**，所以建实例时"自动分配公共 IPv4 地址"开关是灰的（提示"必须选择公共子网"）——这就是之前卡在公网 IP 的原因。已补：

- Internet 网关 `igw1`；
- 默认路由表 `Default Route Table for 1` 加规则 `0.0.0.0/0 → igw1`。

补完后建实例向导里子网会显示为"公共子网 1（区域）"，公网 IPv4 开关自动打开。

## 1. 创建实例（A1.Flex，Phoenix）

1. 计算 → 实例 → 创建实例；名称 `myvpn`。
2. 配置（形状）：更改配置 → 配置系列选 Ampere → 选中 `VM.Standard.A1.Flex` 行 → 点该行的「展开」按钮才会出现「OCPU 数 / 内存量 (GB)」微调框，填 **2 / 12** → 选择配置（Always Free 的 A1 额度：每月 1500 OCPU 小时 ≈ 2 核常开、9000 GB 小时 ≈ 12 GB；超出会被拒绝或计费）。
   - 报"容量不足"是常态：换可用性域 AD-1/2/3 或换个时间重试；都不行就停，改用 `VM.Standard.E2.1.Micro`（1 核 1G，Ubuntu 24.04 x86 镜像，只在 AD-3 可建）。
3. 映像：更改映像 → Ubuntu → Canonical Ubuntu 24.04（非 Minimal）→ 选择映像（arm64 会自动匹配）。
4. 网络步骤：主要网络选「选择现有虚拟云网络」→ VCN `1` → 子网 `1`（应显示为"公共子网"）；「自动分配公共 IPv4 地址」开关会自动打开，灰的就是子网不是公共子网（见第 0 节）。临时 IP 即可。
5. "添加 SSH 密钥" → 选**粘贴公钥**，粘贴：

   ```
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFW563qxDHjOwznOfJCWmvb20VePQPpxN47Dn6Yi2Lfn myvpn-oracle-phoenix
   ```

6. 引导卷：默认（≤200 GB 免费额度内）。其余默认 → 创建。
7. 建好后记录**公共 IP 地址**并发出。

## 2. 安全列表（VCN 级防火墙）入站规则

路径：网络 → 虚拟云网络 → `1`（就是 vcn1）→「安全」页签 → 安全列表 → 默认安全列表（Default Security List for 1）→「安全规则」页签 → 添加入站规则（会打开规则抽屉）。
三条规则（源类型 CIDR，源 CIDR `0.0.0.0/0`，"无状态"不勾选）：

| 用途 | IP 协议 | 目标端口范围 |
|---|---|---|
| SSH（默认一般已存在，确认即可） | TCP | 22 |
| Reality | TCP | 443 |
| Hysteria2 | UDP | 443 |
| 订阅分发（Clash 订阅文件，见 docs/03-subscription.md） | TCP | 8443 |

除上表外不要加其它端口：脚本顺带装出的另外三个协议（Vmess/Tuic/AnyTLS）落在随机高位端口，故意不放行；8443 只跑订阅分发（myvpn-sub 静态服务，见 docs/03-subscription.md）。

✅ 2026-10-11 已完成（Claude 经浏览器操作，控制台表格已核对）：22/TCP 默认就有（IPv4+IPv6 各一条，未动）；已新增 443/TCP 和 443/UDP，源 CIDR 均为 `0.0.0.0/0`、有状态。说明栏分别写的是 "Reality TCP 443" 和 "Hysteria2 UDP 443"。

## 3. 实际结果（2026-10-11）

- A1.Flex 在 AD-1/2/3 全部"容量不足"（2 OCPU/12 GB 与 1 OCPU/6 GB 各试一轮，共 6 次）。
- 已按预案创建 **`myvpn`：VM.Standard.E2.1.Micro（1 核 1 GB，x86_64）**，AD-3，Canonical Ubuntu 24.04（2026.09.18-0），VCN `1` / 子网 `1`，用户名 `ubuntu`。
  - 公共 IP：**<服务器公网IP>**（临时 IP，停机再开可能变）
  - OCID：`ocid1.instance.oc1.phx.anyhqljt2p2n45yciflpu7rzaxl66ggcjfpjxk5bhcbck5u53li6wdnhx5iq`
- A1 重试已停止（2026-10-11 下午，按用户要求）：账户先升级 Pay-As-You-Go，之后再手动抢。届时创建向导要按第 1 节重新走一遍（停在向导页的浏览器标签已被导航到升级付款页）。
- 第 2 节的安全列表规则已由 Claude 通过浏览器添加并核对完成（22/TCP 原有；443/TCP、443/UDP 新增，见第 2 节末）。
- 2026-10-11 下午再补一条入站规则：TCP 8443（源 0.0.0.0/0，说明 "myVPN subscription 8443"），用于订阅文件分发，见 docs/03-subscription.md。
- 部署与收口已完成：服务器上 sing-box 已运行（Reality TCP 443 + Hysteria2 UDP 443），客户端配置在 `./.secrets/`；详见 docs/02-deploy-runbook.md 第 7 节。
