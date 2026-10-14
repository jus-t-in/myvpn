#!/usr/bin/env python3
"""Hold a few GiB of resident memory so the Always Free A1 instance never
satisfies Oracle's idle definition (memory utilization < 20% for 7 days).
Costs almost no CPU. Size via KEEPALIVE_GIB (default 3)."""
import os
import time

gib = float(os.environ.get("KEEPALIVE_GIB", "3"))
size = int(gib * 1024 ** 3)
page = 4096

buf = bytearray(size)
for i in range(0, size, page):  # touch every page so it becomes resident
    buf[i] = 1
print(f"holding {gib} GiB resident", flush=True)

while True:
    time.sleep(3600)
    for i in range(0, size, page * 64):  # light hourly re-touch
        buf[i] = 2
