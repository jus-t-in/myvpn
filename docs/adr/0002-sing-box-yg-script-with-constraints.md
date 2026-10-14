# 部署方式：使用甬哥 sing-box-yg 脚本，但按我们的安全约束运行

备选是官方 sing-box/Xray 手动配置，或 3x-ui 面板。选脚本的原因：与用户跟随的甬哥教程生态一致，一条命令得到 Reality + Hysteria2 以及 Clash/sing-box 客户端配置，后续维护有菜单。代价是以 root 运行第三方脚本，所以先审计再用——`sb.sh`（4469 行，sha256 `5961a0d9…6602ba`，2026-10-11 经 GitHub API 取回）：下载源均为 sing-box 官方、MetaCubeX 规则、cloudflared 官方与作者自有仓库，无远程 eval / base64 执行。

## 运行约束

- 安装时"是否关闭防火墙"选 **2 跳过**（脚本默认会 `ufw disable` 并清空 iptables）；主机防火墙由我们自己维护。
- 端口固定：Reality **443/tcp**、Hysteria2 **443/udp**；其余三个协议的 inbound 保留在随机高位端口，但不在安全列表放行。
- 证书用脚本自签 + 客户端证书指纹固定（`pinSHA256`），不走 `insecure`。
- **不启用"本地 IP 订阅"**（busybox httpd 明文 HTTP）；配置文件经 SSH 取回后离线导入设备。
- 不使用 WARP-plus/Psiphon（需下载作者自编译二进制）、Argo、GitLab 订阅功能。
- 脚本与内核不自动更新；升级前重新审计。
- 慎用脚本的"更改端口"菜单：它用行号定位做 `sed` 替换，两个协议同为 443 时有误替换风险。
- 脚本会用 `curl --insecure` 把自己重新下载到 `/usr/bin/sb`：安装后用审计副本覆盖并校验 sha256。
- 脚本添加的每日 01:00 UTC 重启 cron 删除；脚本内的 apt 安装在无终端时可能卡在 debconf，依赖提前以 noninteractive 方式预装。
