#!/bin/bash
# 一加11 / Android 设备上 WARP / Cloudflare One 故障的现场采集脚本
# 用法: bash diag-warp.sh
# 说明: 全程只读，不修改设备状态。ADB 路径可用环境变量覆盖。
ADB="${ADB:-/c/Program Files/coloros-assist/adb.exe}"
export MSYS_NO_PATHCONV=1

echo "===== 0. 设备 ====="
"$ADB" devices -l
"$ADB" shell getprop ro.product.model
"$ADB" shell getprop ro.build.version.release
"$ADB" shell getprop ro.build.version.ota

echo "===== 1. 系统时间（JWT 失效头号元凶，偏差>20s 必挂） ====="
"$ADB" shell date
"$ADB" shell settings get global auto_time
"$ADB" shell settings get global auto_time_zone

echo "===== 2. 私人 DNS（自定义会顶掉 WARP 的 DNS 接管） ====="
"$ADB" shell settings get global private_dns_mode
"$ADB" shell settings get global private_dns_specifier

echo "===== 3. Cloudflare 相关包（注意 Android Edge = com.microsoft.emmx） ====="
"$ADB" shell "pm list packages -f 2>/dev/null | grep -iE 'cloudflare|warp|1111|oneoneone|emmx'"

echo "===== 4. 当前 VPN 状态 / 槽位占用 ====="
"$ADB" shell "dumpsys connectivity 2>/dev/null | grep -iE 'VPN|tun[0-9]' | head -30"
echo "--- VPN profile ---"
"$ADB" shell "ls /data/misc/vpn/ 2>/dev/null || echo '(需权限，正常)'"

echo "===== 5. 网络与路由 ====="
"$ADB" shell "ip -br addr 2>/dev/null | head -20"
"$ADB" shell "ip route 2>/dev/null | head -10"
"$ADB" shell "ip rule 2>/dev/null | head -20"
"$ADB" shell getprop net.dns1

echo "===== 6. 到 Cloudflare 的实际连通性 ====="
"$ADB" shell "ping -c 2 -W 3 1.1.1.1" 2>&1 | tail -4
"$ADB" shell "ping -c 2 -W 3 engage.cloudflareclient.com" 2>&1 | tail -4
echo "--- 1.1.1.1:443（本案例的关键指标） ---"
"$ADB" shell "curl -sk -m 8 -o /dev/null -w 'http=%{http_code} ip=%{remote_ip}\n' https://1.1.1.1/" 2>&1
echo "--- 严格校验（区分网络不通 / 证书不信任） ---"
"$ADB" shell "curl -sS -m 8 -o /dev/null -w 'http=%{http_code} ssl=%{ssl_verify_result}\n' https://1.1.1.1/" 2>&1

echo "===== 7. 后台策略（ColorOS 冻结） ====="
for p in com.cloudflare.cloudflareoneagent com.cloudflare.onedotonedotonedotone com.github.metacubex.clash.meta; do
  echo "--- $p ---"
  "$ADB" shell "dumpsys deviceidle whitelist 2>/dev/null | grep -i '$p'"
  "$ADB" shell "appops get '$p' RUN_IN_BACKGROUND 2>/dev/null"
done

echo "===== 8. 最近日志 ====="
"$ADB" shell "logcat -d -t 400 2>/dev/null | grep -iE 'cloudflare|warp|wgcf|vpn|ERR_CERT'" | tail -60
