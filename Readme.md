# myVPN

在 Oracle Cloud（甲骨文云）服务器上自建代理节点，供个人访问 Google、YouTube 等服务。项目中的「VPN」指代理节点；客户端按规则分流，国内流量直连，境外流量走节点。

本仓库保存教程、部署记录、维护脚本和架构决策。首次搭建请从[完整教程](docs/tutorial.md)开始，按顺序完成实例申请、SSH 连接、项目部署和节点测试；`server/` 下的脚本负责订阅分发和防闲置负载。

## 方案与部署记录

| 项目 | 方案 |
| --- | --- |
| 云服务器 | Oracle Cloud，Phoenix 区域 |
| 当前实例 | E2.1.Micro，x86_64，1 核 / 1 GB，Ubuntu 24.04 |
| 节点服务 | sing-box，通过审计后的 sing-box-yg 脚本安装 |
| TCP 节点 | VLESS-REALITY，TCP 443 |
| UDP 节点 | Hysteria2，UDP 443 |
| 订阅分发 | Python 静态服务 + systemd，HTTP / TCP 8443 |
| 线路 | 直连优先；CDN 中转留作后补方案 |

按 2026-10-11 的部署记录，节点、订阅分发和 E2.1.Micro 的 CPU 负载 cron 已部署。A1.Flex 当时容量不足，迁移待后续安排；手机和各桌面客户端的实际使用效果仍需按部署手册验证。

## 文档导航

| 文档 | 内容 |
| --- | --- |
| [完整搭建教程](docs/tutorial.md) | 从申请甲骨文实例到节点测试的逐步操作、成功判据与故障排查 |
| [项目术语](CONTEXT.md) | 节点、客户端、分流、订阅等术语约定 |
| [控制台操作清单](docs/01-console-checklist.md) | 创建实例、配置公网网络和 OCI 安全列表 |
| [服务器部署手册](docs/02-deploy-runbook.md) | 系统基线、安装节点、安装后收口、验证和回滚 |
| [订阅分发说明](docs/03-subscription.md) | 订阅服务、配置更新和客户端导入 |
| [直连线路决策](docs/adr/0001-direct-first-reality-hysteria2.md) | Reality + Hysteria2 的选择与 CDN 后补策略 |
| [安装脚本决策](docs/adr/0002-sing-box-yg-script-with-constraints.md) | 第三方脚本的运行约束与审计要求 |
| [CPU 负载决策](docs/adr/0003-cpu-load-cron-anti-reclaim.md) | E2.1.Micro 的防闲置回收措施及取舍 |

## 仓库结构

```text
myVPN/
├── Readme.md
├── CONTEXT.md
├── docs/                       # 操作手册与架构决策
│   ├── tutorial.md             # 从实例申请到节点测试的完整教程
│   └── adr/
├── server/
│   ├── 99-bbr.conf             # BBR + fq 的 sysctl 配置
│   ├── deploy-sub.sh           # 部署 / 更新订阅服务
│   ├── myvpn-sub.py            # 只提供指定订阅文件的 HTTP 服务
│   ├── myvpn-sub.service       # 订阅服务的 systemd 模板
│   ├── deploy-cpuload.sh       # 部署 CPU 负载 cron 与日志轮转
│   ├── oci-cpu-load.sh         # 限时 CPU 负载脚本，供 E2.1.Micro 使用
│   ├── oci-keepalive.py        # 常驻内存脚本，供 A1 使用
│   └── oci-keepalive.service   # A1 常驻内存服务单元
├── .secrets/                   # 本地节点配置与订阅地址，不入库
└── .audit/                     # 第三方脚本的本地审计副本，不入库
```

`.secrets/` 和 `.audit/` 已被 `.gitignore` 排除，复制仓库时需要另外准备这些本地文件。

## 首次部署

详细命令和每阶段的成功判据见[完整教程](docs/tutorial.md)，流程如下：

1. 申请 Oracle Cloud 实例，配置 Internet 网关、默认路由、公网 IP 和 OCI 入站规则。
2. 生成自己的 SSH 密钥，配置别名 `myvpn`，确认密钥登录和远端 `sudo` 可用。
3. 完成 Ubuntu 系统基线，校验 `.audit/sb.sh` 审计副本，再安装 sing-box 并完成安装后收口。
4. 经 SSH 取回配置，制作仅含 Reality / Hysteria2 的 `.secrets/sub/myvpn.yaml`，为 Hysteria2 固定证书指纹，并部署订阅服务。
5. 在客户端激活配置和规则分流，分别固定选择两种节点，验证代理请求、出口 IP、Google / YouTube、国内直连和重启持久化。

新机器缺少审计副本时，按教程先获取并校验；上游版本哈希不一致时需重新审计，不能直接沿用旧版本的安装输入。

OCI 安全列表和服务器防火墙都需要放行对应端口：

| 用途 | 协议 / 端口 |
| --- | --- |
| SSH | TCP 22 |
| VLESS-REALITY | TCP 443 |
| Hysteria2 | UDP 443 |
| 订阅分发 | TCP 8443 |

安装脚本生成的其他协议端口不对外放行。不要用脚本关闭防火墙；其他运行约束见[安装脚本决策](docs/adr/0002-sing-box-yg-script-with-constraints.md)。

## 订阅与客户端

部署前准备好 `.secrets/sub/myvpn.yaml`，并放行 OCI 安全列表中的 TCP 8443。在仓库根目录执行，首次部署使用 32 位随机十六进制 token，更新时复用已有 token：

```bash
# 参数：<token> [ssh-host] [port]；默认主机 myvpn、端口 8443
bash server/deploy-sub.sh '<token>'
```

脚本上传订阅文件、安装并启动 `myvpn-sub.service`、放行服务器防火墙，并将订阅 URL 写入 `.secrets/sub-url.txt`。修改订阅内容后，使用同一个 token 重跑即可更新。

- **远程订阅**：将 `.secrets/sub-url.txt` 中的 URL 粘贴到客户端订阅框；自动更新取决于客户端设置。
- **本地导入**：导入 `.secrets/sub/myvpn.yaml`，后续修改需要重新导入。
- **深链导入**：支持的客户端可使用 `clash://install-config?url=<订阅URL的percent编码>`，详见[订阅分发说明](docs/03-subscription.md)。

部署记录中已验证 Clash Verge Rev（电脑）和 FlClash（Android）的深链导入。Windows / iPhone 的进一步实测见部署手册中的验证顺序。

订阅地址形如 `http://<公网IP>:8443/<token>/myvpn.yaml`。同一地址下的配置变更可通过订阅更新同步；**服务器公网 IP、端口或 token 改变后，需要同步更新客户端保存的订阅 URL**。

订阅 URL 相当于口令，YAML 内含节点凭据。当前订阅服务使用明文 HTTP，token 只用于限制路径访问，不提供传输加密；相关取舍见订阅分发说明。私钥、真实 token、订阅地址和节点配置不要提交或公开。

## 日常维护

以下查询命令在本机执行：

```bash
# 查看节点和订阅服务状态
ssh myvpn 'systemctl is-active sing-box myvpn-sub'

# 查看最近日志
ssh myvpn 'sudo journalctl -u sing-box -u myvpn-sub -n 50 --no-pager'

# 查看监听端口
ssh myvpn 'sudo ss -tunlp'

# 查看 E2.1.Micro 的 CPU 负载任务日志
ssh myvpn 'tail -n 20 /var/log/myvpn-cpuload.log'
```

E2.1.Micro 的 CPU 负载 cron 可用下列命令部署或重置，默认每小时第 7 分运行 300 秒；部署脚本还会执行一次 5 秒负载自检：

```bash
# 参数：[ssh-host] [minute] [duration-seconds]
bash server/deploy-cpuload.sh myvpn 7 300
```

A1 的常驻内存方案使用 `oci-keepalive.py` 与对应服务单元，默认占用 3 GiB 内存，不适用于当前 1 GB 的 Micro 实例。两种措施的依据和限制见[CPU 负载决策](docs/adr/0003-cpu-load-cron-anti-reclaim.md)。

节点脚本与内核不自动更新，升级前重新审计。迁移、卸载和回滚操作见[服务器部署手册](docs/02-deploy-runbook.md)。
