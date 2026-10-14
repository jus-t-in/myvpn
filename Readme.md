# myVPN

在 Oracle Cloud 自建个人代理节点，客户端按规则分流：国内直连，境外走节点。项目口语中的「VPN」指代理节点。

从[完整教程](docs/tutorial.md)开始，使用有窗口浏览器创建新实例，再完成 SSH、安装、导入和节点验证。

## 当前方案

| 项目 | 方案 |
| --- | --- |
| 实例 | `myvpn-new`，Phoenix AD-1，A1.Flex，1 OCPU / 6 GB |
| 系统 | Canonical Ubuntu 24.04，ARM64 |
| 节点 | 官方 sing-box 1.14.3，单个 VLESS-REALITY / TCP 443 |
| 配置 | 国内规则 DIRECT，其余走手选节点 |
| 手机订阅 | 项目 HTTP 服务 + systemd，TCP 8443；URL 保存在本机 `.secrets/sub-url.txt` |
| 线路 | 直连；本次换到可达公网 IP 后恢复，不要求接入 Cloudflare |

2026-10-14 实测：手机 FlClash 已激活，蜂窝网络请求返回 204，出口与新服务器相同；电脑 Google 搜索及国内 DIRECT 已验证。实例重启后两项服务、端口规则、订阅下载和代理请求均恢复。公开视频短片完整播放，但一次样片下载较慢，持续视频体验未验收；YouTube 播放触发登录验证。详细结果见[维护记录](docs/02-deploy-runbook.md)。历史 Micro 实例的记录不作为当前状态。

## 文档

| 文档 | 内容 |
| --- | --- |
| [完整教程](docs/tutorial.md) | 从新建实例到实际节点验收的最小流程 |
| [控制台清单](docs/01-console-checklist.md) | 机型、公共网络、费用与端口复核 |
| [维护手册](docs/02-deploy-runbook.md) | 当前操作记录、日常查询与迁移回滚 |
| [订阅说明](docs/03-subscription.md) | 手机导入、下载校验和换 IP 后更新 |
| [项目术语](CONTEXT.md) | 节点、客户端、分流、订阅等约定 |
| [历史架构决策](docs/adr) | 旧多协议脚本、线路与负载措施的选择依据 |

## 脚本与私密文件

- `server/setup-reality.sh`：在新建 OCI Ubuntu 上安装官方 sing-box、生成凭据、配置单个 Reality、持久化 TCP 443 规则。详细使用方法见教程。
- `server/deploy-sub.sh`、`myvpn-sub.py`、`myvpn-sub.service`：部署 / 更新订阅服务。使用项目内 SSH 配置时：

```bash
MYVPN_SSH_CONFIG=.secrets/ssh/config \
  bash server/deploy-sub.sh "$(cat .secrets/sub-token.txt)" myvpn-new
```

- `server/99-bbr.conf` 与负载脚本是可选运维工具，不属于当前最小安装步骤。
- `.secrets/` 保存私钥、SSH 配置、节点参数、YAML、订阅 token / URL；`.audit/` 保存旧审计副本，两者不入库。Shell 脚本通过 `.gitattributes` 保持 LF 换行。

**订阅为 HTTP，8443 不代表 HTTPS。** URL 相当于口令，YAML 内含节点凭据；token 不提供传输加密。需要保密传输时使用经 SSH 取回后的本地导入，或另行配置 HTTPS。

换公网 IP 后必须同步更新 SSH、YAML、服务器订阅副本和每台客户端保存的订阅 URL。停止 / 重启不会自动更换 OCI 临时公网 IP；已部署成功也需用实际代理和出口 IP 验证，不能只看订阅下载或端口握手。
