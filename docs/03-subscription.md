# 订阅分发与更新

先按[搭建教程](tutorial.md)制作仅含当前 Reality 节点的 `.secrets/sub/myvpn.yaml`。可直接本地导入；本次按用户要求另外部署 FlClash 远程订阅。

## 部署

本机项目根目录，使用 Bash。首次生成 token；已有 token 时跳过生成：

```bash
umask 077
test -s .secrets/sub-token.txt || openssl rand -hex 16 > .secrets/sub-token.txt
MYVPN_SSH_CONFIG=.secrets/ssh/config \
  bash server/deploy-sub.sh "$(cat .secrets/sub-token.txt)" myvpn-new
```

参数为 `<token> [ssh-host] [port]`，默认主机 `myvpn`、端口 `8443`；本次主机为 `myvpn-new`，通过 `MYVPN_SSH_CONFIG` 指定项目内 SSH 配置。脚本上传配置，安装并重启 `myvpn-sub.service`，添加主机 iptables 规则并持久化，等待监听后将 URL 写入 `.secrets/sub-url.txt`。脚本要求 INPUT 链有兜底 REJECT；OCI TCP 8443 规则需另行配置。

服务以 `nobody` 运行，只提供 `/<token>/myvpn.yaml` 的 GET / HEAD，其他路径返回 404，无目录列表。文件位于 `/opt/myvpn-sub/<token>/myvpn.yaml`。

## 导入和验证

- 远程导入：在客户端订阅页粘贴 `.secrets/sub-url.txt` 中的地址，下载后点选新配置；FlClash 还须在仪表盘启动服务、允许系统 VPN。自动更新需在客户端启用。
- 本地导入：导入 `.secrets/sub/myvpn.yaml`，修改后重新导入。
- 支持 `clash://` 的客户端也可用 `clash://install-config?url=<完整订阅URL的percent编码>`；先确认目标客户端支持，导入后仍需激活。

本机验证，避免经已有代理访问：

```bash
subscription_url=$(cat .secrets/sub-url.txt)
curl --noproxy '*' --fail --connect-timeout 10 --max-time 30 \
  "$subscription_url" -o .secrets/sub/downloaded.yaml
sha256sum .secrets/sub/myvpn.yaml .secrets/sub/downloaded.yaml
curl --noproxy '*' --connect-timeout 10 --max-time 15 \
  -sS -o /dev/null -w '%{http_code}\n' "${subscription_url%/*}/not-a-file.yaml"
```

有效地址应下载成功、两个哈希一致，错误路径应为 `404`。这只验证配置分发；协议连接还须按教程固定选择新节点测试。

## 更新和迁移

| 变更 | 操作 |
| --- | --- |
| 同一 URL 下修改节点配置 | 修改本机 YAML，复用原 token 重跑部署脚本，再在客户端更新订阅 |
| 轮换节点凭据 | 同步更新服务器与客户端的 UUID / Reality 公钥等参数，再部署 / 更新订阅 |
| 换服务器 IP | 更新 SSH 地址和 YAML 的 `server`，部署到新机；**逐台更新客户端保存的订阅 URL** |
| 换端口或 token | 重跑部署，调整两层端口规则，逐台更新客户端 URL |

当前 URL 直接使用 IP。服务器换 IP 后，客户端仍请求旧 IP，不会自动发现新地址。只有订阅地址始终不变且仍能访问时，才可靠订阅更新同步配置。停机 / 重启通常保留 OCI 临时公网 IP；终止重建、删除或重新分配公网 IP 才可能改变地址。[Oracle 公网 IP 说明](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/managingpublicIPs.htm)

更换 token 后服务只匹配新路径，旧路径返回 404；确认迁移成功后再清理旧目录。节点凭据也被泄露时，应同时轮换凭据，仅换 URL token 不够。

## 传输方式

地址为 `http://<公网IP>:8443/<token>/myvpn.yaml`。**8443 在本项目中是 HTTP，不是 HTTPS。** URL 相当于口令，YAML 内含节点凭据；随机 token 不能防链路嗅探。需要保密传输时使用 SSH 取回后的本地导入，或另行配置受客户端信任的 HTTPS 服务。

2026-10-14 本次实测：手机蜂窝网络直连下载 HTTP 200、约 0.36 秒，配置哈希一致；FlClash 已激活新配置，代理组仅含新节点，手机实际出口与服务器相同，Google 连通性请求返回 204、约 0.94 秒。实例重启后，电脑直连订阅仍为 200、哈希一致，错误路径 404。初始地址直连超时导致 FlClash 一直加载，换到可达公网 IP 后恢复。当前 URL 在 `.secrets/sub-url.txt`，不要使用更换 IP 前的旧链接。
