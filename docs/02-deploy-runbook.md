# 部署记录与维护

首次搭建见[完整教程](tutorial.md)，手机订阅见[订阅说明](03-subscription.md)。

## 本次操作（2026-10-14）

- 通过有窗口的 Chrome 登录 OCI，从创建向导新建 `myvpn-new`：Phoenix AD-1，A1.Flex 1 OCPU / 6 GB，Ubuntu 24.04 ARM64，独立 SSH 公钥。
- 核对公共子网 `1`、Internet 网关 `igw1`、默认路由及云端 TCP 22/443/8443。创建前有一个 47 GB 引导卷、无块卷，新实例使用默认卷大小。
- 通过官方 APT 仓库安装 sing-box 1.14.3，使用 `sing-box` 服务用户；SSH 已禁密码登录，安全更新已启用。核心包 hold，未安装多协议脚本或负载任务。
- `server/setup-reality.sh` 已在新机执行验证：单个 Reality / TCP 443，配置检查成功，服务 active / enabled，主机规则持久化。
- 初始公网地址及第一次重分配地址在电脑和手机上均直连超时；经现有代理可访问。再次分配到另一网段后，电脑和手机的直接 HTTP 请求约 0.35–0.39 秒返回响应。原因定位为旧公网地址的线路可达性，不以此断言平台或运营商的具体封锁机制。
- 新地址的实际 Reality 请求返回 HTTP 204，代理出口与服务器出口一致；国内请求 HTTP 200，日志命中 DIRECT。独立测试核心确认请求经过 `myvpn-new-Reality`，当前桌面 TUN 未启用。
- 手机关闭 Wi-Fi、开启移动数据，订阅直连下载 HTTP 200、约 0.36 秒，文件哈希与源配置一致；此前 FlClash 一直加载对应的是连接超时。FlClash 已激活新配置，`PROXY` 仅含 `myvpn-new-Reality`；手机实际出口匹配服务器，Google 连通性请求 HTTP 204、约 0.94 秒。
- 有窗口浏览器已通过新节点完成 Google 搜索，并完整播放 MDN WebM 样片（5.059 秒，960×540，无播放错误）。一次独立样片下载为 554,058 字节 / 约 47 秒，持续吞吐与长视频体验未验收。YouTube 搜索页可达，播放要求登录确认非机器人；W3C MP4 样片在 Chrome 中报解码错误，均未记为播放通过。
- 已实际重启新实例，前后 boot ID 不同。两项服务均 active / enabled，TCP 443/8443 监听及主机放行规则恢复，本次启动无服务错误日志。重启后订阅直连 HTTP 200、约 0.78 秒，哈希一致，错误路径 404；实际代理请求 HTTP 204、约 4.92 秒，出口仍匹配，国内请求 HTTP 200、约 0.13 秒。

最小部署和连通性验收已完成。手机重启后的再次测试、Wi-Fi 场景及持续视频体验未验证；手机 USB 在蜂窝网络验收后断开。

真实 IP、token、完整订阅地址及节点参数仅保存在 `.secrets/`，不写入文档。

## 查询与更新

本机 Git Bash，项目根目录：

```bash
ssh -F .secrets/ssh/config myvpn-new 'systemctl is-active sing-box myvpn-sub'
ssh -F .secrets/ssh/config myvpn-new 'systemctl is-enabled sing-box myvpn-sub'
ssh -F .secrets/ssh/config myvpn-new 'sudo ss -lntup'
ssh -F .secrets/ssh/config myvpn-new 'sudo journalctl -u sing-box -n 30 --no-pager'
ssh -F .secrets/ssh/config myvpn-new 'sudo iptables -L INPUT -n --line-numbers'
```

订阅日志可能包含完整 URL，查看后对外引用时先隐藏 token。更新复用现有 token：

```bash
MYVPN_SSH_CONFIG=.secrets/ssh/config \
  bash server/deploy-sub.sh "$(cat .secrets/sub-token.txt)" myvpn-new
```

## 迁移与回滚

- 先备份 `/etc/sing-box/config.json`、`/root/myvpn-reality-credentials.json`、`/root/myvpn-client.json` 和本地 YAML。
- 升级前检查配置兼容性；核心包当前 hold，手动升级后重做代理、出口和持久化验证。
- 迁移或换 IP：更新 SSH、YAML、服务器订阅副本和客户端保存的 URL，完成新节点验证后再处理旧资源。
- 配置回滚：恢复备份，`sing-box check` 成功后重启服务。停服务、卸载节点和终止实例是不同操作，终止前另行核对备份和卷处理。

## 历史记录

2026-10-11 曾在 Phoenix AD-3 创建 E2.1.Micro / Ubuntu 24.04，采用 sing-box-yg 安装 Reality + Hysteria2、HTTP 订阅及 CPU 负载任务。旧配置位于 `/etc/s-box/`，与本次官方包的 `/etc/sing-box/` 不同，命令不能混用。相关取舍见 [ADR](adr)。历史服务状态未在本次复核。
