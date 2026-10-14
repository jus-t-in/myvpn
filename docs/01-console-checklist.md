# OCI 控制台清单

完整步骤见[搭建教程](tutorial.md)。本次从创建新实例 `myvpn-new` 开始；创建前先检查现有实例和卷所占的免费额度。

## 创建前

- 登录 [OCI 控制台](https://cloud.oracle.com/)，确认主区域（Home region）及 compartment。历史部署在 Phoenix，免费计算资源应建在账号主区域。
- 在「计算 → 实例」检查现有实例，在「存储 → 块存储」核对引导卷和块卷总量，包括已终止实例遗留的卷。
- 准备自己的 SSH 公钥。已有私钥时勿覆盖；公钥来自对应的 `.pub` 文件，不照抄他人的公钥。

## 网络

选择或通过 Internet 连接向导创建 VCN，核对以下四项：

| 检查项 | 要求 |
| --- | --- |
| 子网 | 公共子网，允许 VNIC 分配公共 IPv4 |
| Internet 网关 | 已启用，属于该 VCN |
| 子网关联路由表 | `0.0.0.0/0 → Internet 网关` |
| 实例 VNIC | 已分配公共 IPv4 |

**添加网关和路由不会把私有子网变为公共子网。** 子网类型在创建时决定；选错时应选择或新建公共子网。公网开关灰色时，先检查子网限制，再检查路由。[Oracle 子网说明](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/Overview_of_VCNs_and_Subnets.htm)

历史账号的 VCN、子网均名为 `1`，网关名为 `igw1`；这些名称不适用于其他账号，也不代表当前配置已经正确。

## 创建实例

| 字段 | 填写 |
| --- | --- |
| 名称 | `myvpn-new`，或能与现有实例区分的名称 |
| 首选形状 | `VM.Standard.A1.Flex`，1 OCPU / 6 GB，ARM64，满足单节点最小部署 |
| 备用形状 | `VM.Standard.E2.1.Micro`，AMD / x86_64，1 GB；CPU 基线为 1/8 OCPU，可突发 |
| 映像 | Canonical Ubuntu 24.04，标准版，架构与形状匹配 |
| 网络 | 已核对的 VCN、公共子网，自动分配公共 IPv4 |
| SSH | 粘贴自己的整行公钥 |
| 引导卷 | 保留默认大小、性能；核对所有引导卷和块卷合计额度 |

A1 行若未显示 CPU / 内存输入，展开形状详情。容量不足时换主区域内的可用性域或稍后重试；Micro 仅在区域中的一个可用性域提供，不能把历史 AD-3 当作通用规则。不要误选名称相近的付费形状。提交前核对账号剩余额度、免费资格和费用提示；账号升级不属于本流程。

创建成功后记录状态 `Running`、形状、映像、公共 IPv4。不要把文档中的历史部署记录当作本次创建结果。

## 云端入站规则

路径：实例 → 网络 / 主 VNIC → 子网 → 关联的安全列表。若使用 NSG，同时核对 VNIC 的 NSG 关联。

| 用途 | 协议 | 目标端口 | 源 CIDR |
| --- | --- | --- | --- |
| SSH | TCP | 22 | 本机公网出口 `/32`，动态网络按需调整 |
| Reality | TCP | 443 | `0.0.0.0/0` |
| 远程订阅（可选） | TCP | 8443 | `0.0.0.0/0` |

源端口保留全部，「无状态」不勾选，保留必要的出站规则。仅本地导入配置时无需开放 8443。安全列表与 NSG 的允许规则取并集；主机防火墙仍需单独放行。[Oracle 安全规则说明](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/securityrules.htm)

## 本次与历史记录

2026-10-14 已通过有窗口的 Chrome 创建 `myvpn-new`：Phoenix AD-1、A1.Flex 1 OCPU / 6 GB、Canonical Ubuntu 24.04 ARM64，使用独立 SSH 公钥。现有公共子网 `1`、默认路由与 22/TCP、443/TCP、8443/TCP 云端规则已逐项核对。新卷使用默认大小；创建前另有一个 47 GB 引导卷，无额外块卷。公网地址仅记入 `.secrets/`。

向导中引导卷曾显示 $2.76/月的估算，此估算不体现套餐单位价格；仍需核对账号所有卷的总量与免费资格，不能只凭估算框判断最终费用。

仓库记录：2026-10-11 曾在 Phoenix AD-3 创建 `myvpn`（E2.1.Micro / Ubuntu 24.04），A1 当时无容量，并添加过 443/TCP、443/UDP、8443/TCP 规则。以上是历史记录，本次须重新查看控制台及服务器验证。

规格和额度核对日期：2026-10-14，来源为 [Oracle Always Free 文档](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)。实时容量与剩余额度以账号控制台为准。
