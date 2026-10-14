# 订阅分发（2026-10-11 起）

目标：客户端不再依赖本机临时服务（早期做法是 PC 上 `python3 -m http.server` 127.0.0.1:18080 + 手机 `adb reverse`），
任何设备直接粘一条 URL 即可导入，且订阅能自动更新（IP 变化时无需逐台重导）。

## 形态

- 服务器 `/opt/myvpn-sub/<token>/myvpn.yaml`（即 `.secrets/sub/myvpn.yaml` 的副本），
  由 systemd 服务 `myvpn-sub.service` 用 `server/myvpn-sub.py` 分发：只响应
  `GET /<token>/myvpn.yaml`，其余路径一律 404，无目录列表；服务以 `nobody` 运行。
- 端口 **8443/tcp**。服务器 iptables 已放行并持久化；OCI 安全列表已加入站规则（源 `0.0.0.0/0`），见 docs/01 第 2 节。
- `<token>` 为 32 位随机十六进制，URL 即口令。订阅地址保存在 `.secrets/sub-url.txt`（不入库），形如
  `http://<公网IP>:8443/<token>/myvpn.yaml`。

## 部署 / 更新

- 更新订阅：改完 `.secrets/sub/myvpn.yaml` 后跑 `server/deploy-sub.sh <token>`（幂等）。
  脚本做四件事：上传文件、装 systemd 单元、插 iptables 规则并 `netfilter-persistent save`、自检后把 URL 写回 `.secrets/sub-url.txt`。
- 换 token：用新 token 重跑脚本，再手动删旧目录 `ssh myvpn 'sudo rm -rf /opt/myvpn-sub/<旧token>'`。
- 换 IP（如迁到 A1）：按 docs/02 部署新机，重跑一次 `deploy-sub.sh` 即可；各客户端在自动更新周期内自行拉到新配置。
- 只有换端口才需要再动安全列表：控制台 → 网络 → 虚拟云网络 `1` → 安全列表 → 默认安全列表 → 添加入站规则（TCP 8443，源 `0.0.0.0/0`）。

## 各客户端导入

- 通用：把 `.secrets/sub-url.txt` 里的 URL 粘进客户端「订阅」框。
- 一条链接（发到手机聊天窗点开即导入）：`clash://install-config?url=<URL 的 percent 编码>`。
  Linux 上 `xdg-open "<deep link>"` 实测 Clash Verge Rev 直接下载为 remote profile。
- FlClash（Android）：同一条 `clash://` 链接（adb 或点击）即可，也可粘 URL。
- 本地文件：`.secrets/sub/myvpn.yaml` 直接「导入本地文件」也可以，但不会自动更新。

## 验证记录（2026-10-11）

- 本机（国内宽带）`curl --noproxy '*'`：HTTP 200，connect 1.4 s；内容 sha256 与源文件一致；错误路径 404。
- 手机独立网络 curl：HTTP 200（0.6 s）。
- Clash Verge Rev：deep link 导入为 remote profile（`allow_auto_update: true`）；旧的本机 profile（url 指向 127.0.0.1:18080）可在 UI 删除。
- FlClash：deep link 导入即出现新 profile（FlClash 用 epoch 毫秒命名，如 `1791702971491`，标注「刚刚」）；是否切换激活由用户在手机上点选。
- 旧的本机分发服务（127.0.0.1:18080）已停用。

## 安全取舍

- 明文 HTTP：token 防「猜」，但链路上可被嗅探（YAML 内含节点密钥）。自用、低价值目标，可接受；
  如要 HTTPS 需要域名 + 证书（自签证书对 Clash 订阅器不友好），暂不做。