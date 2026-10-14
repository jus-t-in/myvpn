# Micro 的防闲置回收：每小时 CPU 负载 cron（过渡措施，账户升级仍是正路）

Oracle 对 Always Free 实例的回收判定：7 天窗口内 CPU 95 分位 < 20%、网络利用率 < 20%（A1 另加内存 < 20%）**同时成立**才视为闲置。E2.1.Micro 不适用内存条件、也只有 1 GB，破坏条件只能靠 CPU 或网络。选 CPU 方案：每小时满负载 5 分钟 ≈ 8.3% 的时间 CPU 高于 20%，超过把 95 分位抬到 20% 所需的 5%；nice 19 下节点转发优先，不影响日常使用。实现：`/etc/cron.d/myvpn-cpuload` 调 `/opt/myvpn-cpuload/oci-cpu-load.sh`（`server/deploy-cpuload.sh` 幂等部署，日志 `/var/log/myvpn-cpuload.log` 带 logrotate）。A1 的对应方案是 oci-keepalive（常驻占 3 GiB 内存、CPU 几乎为零），按机型二选一部署。

备选与取舍：账户升级 Pay-As-You-Go——官方文档未承诺升级后免回收（仅社区经验如此），但升级本身是 A1 容量问题的既定计划，落地后本 cron 可留（无害）可删。放弃的方案：在 Micro 上占内存（无内存条件，且 1 GB 机占用会伤节点）、依赖真实代理流量撑 CPU（用量不可控，7 天窗口内可能长期低位）。
