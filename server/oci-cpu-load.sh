#!/usr/bin/env bash
# 防闲置回收（E2.1.Micro 专用）：Oracle 判定 Always Free 实例闲置的条件之一是
# 7 天内 CPU 利用率 95 分位 < 20%。本脚本满负载跑 DURATION 秒；每小时一次即可让
# 95 分位远高于 20%（5 分钟/小时 ≈ 8.3% 的时间满载，超过判定所需的 5%），该条件
# 不再成立（各条件为"同时成立"才回收，破坏其一即可）。nice 19 保证节点转发优先。
# A1 不用本脚本——用 oci-keepalive（常驻内存）方案，见 docs/02-deploy-runbook.md §3。
# 用法: oci-cpu-load.sh [duration-seconds] [workers]   （默认 300 秒、nproc 个）
set -euo pipefail

DURATION="${1:-300}"
WORKERS="${2:-$(nproc)}"
NICE="${NICE:-19}"

echo "[oci-cpu-load] start $(date -Is) duration=${DURATION}s workers=${WORKERS} nice=${NICE}"
pids=()
for _ in $(seq "$WORKERS"); do
  nice -n "$NICE" timeout "$DURATION" sha256sum /dev/zero >/dev/null 2>&1 &
  pids+=("$!")
done
wait "${pids[@]}" || true  # timeout 到点会以 124 退出，属正常
echo "[oci-cpu-load] done  $(date -Is)"
