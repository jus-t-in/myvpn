# 节点线路：直连优先（Reality + Hysteria2），CDN 仅作后补

起点是 linux.do 帖子《甲骨文vps自建vpn节点速度稳定》（作者 Digital_Observer）：甲骨文服务器 + Cloudflare CDN 中转 + 优选 IP 的 VMess+WS+TLS 方案，实测速度很高，用户最初想 1:1 复刻。讨论后决定：第一版只建直连协议 VLESS-REALITY（TCP 443）与 Hysteria2（UDP），不引入域名与 Cloudflare 依赖——步骤最少、最快可用，直连凤凰城的实际质量先实测再判断。若服务器 IP 被墙或直连速度不达预期，再叠加 CDN 中转作为补充通道；两套方案不冲突，客户端可并存切换。
