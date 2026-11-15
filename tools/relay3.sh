#!/system/bin/sh
# 手机侧中继：由 busybox nc -lk -e 在每个连接上来执行。
# 目标必须写 IP（1.1.1.1），因为 Zero Trust 下域名解析可能失败。
exec /data/local/tmp/busybox nc 1.1.1.1 443
