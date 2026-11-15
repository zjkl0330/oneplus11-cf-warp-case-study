#!/bin/bash
# 从设备当前的 TLS 握手里抓 Cloudflare Gateway 根证书。
#
# 为什么需要它：后台 API 下载证书常被 403 挡住，公开端点 404；
#               而隧道里正在被 Gateway 重签的链，一定包含真正在用的根 CA。
#
# 前提：
#   1. 设备已连 Cloudflare One 隧道（tun0 存在）；
#   2. KernelSU 已给 Shell (com.android.shell, UID 2000) 超级用户授权；
#   3. PC 有 openssl，且设备通过 USB 连着；
#   4. 中继必须以 shell 身份跑 —— root (uid 0) 的流量不进 tun0。
#
# 用法: bash grab-gateway-ca.sh [输出目录]
set -u
ADB="${ADB:-/c/Program Files/coloros-assist/adb.exe}"
OUT="${1:-.}"
HERE="$(cd "$(dirname "$0")" && pwd)"
export MSYS_NO_PATHCONV=1
mkdir -p "$OUT"

cleanup() {
  [ -n "${RELAY_PID:-}" ] && kill "$RELAY_PID" 2>/dev/null
  "$ADB" forward --remove-all >/dev/null 2>&1
  "$ADB" shell "pkill -f 'busybox nc -lk -p 8443'" >/dev/null 2>&1
}
trap cleanup EXIT

echo "[0] 前置检查"
"$ADB" shell "ip addr show tun0 2>/dev/null | grep 'inet '" || {
  echo "!! 没找到 tun0 —— 先连上 Cloudflare One 隧道"; exit 1; }
"$ADB" shell "su -c id" 2>/dev/null | grep -q 'uid=0' || {
  echo "!! shell 没有 root —— 先在 KernelSU 超级用户页搜索 shell 并授权"; exit 1; }

echo "[1] 推送中继脚本、复制 busybox 到 shell 可读位置"
"$ADB" push "$HERE/relay3.sh" /data/local/tmp/relay3.sh >/dev/null
"$ADB" shell "su -c 'cp /data/adb/ksu/bin/busybox /data/local/tmp/busybox; chmod 755 /data/local/tmp/busybox /data/local/tmp/relay3.sh'"

echo "[2] 端口转发 + 以 shell 身份起持久中继"
"$ADB" forward --remove-all >/dev/null 2>&1
"$ADB" forward tcp:9443 tcp:8443 >/dev/null
"$ADB" shell "/data/local/tmp/busybox nc -lk -p 8443 -e /data/local/tmp/relay3.sh" >/dev/null 2>&1 &
RELAY_PID=$!
sleep 2

echo "[3] 发起 TLS 握手，导出证书链"
timeout 25 openssl s_client -connect 127.0.0.1:9443 \
  -servername www.cloudflare.com -showcerts </dev/null > "$OUT/chain.txt" 2>/dev/null
COUNT=$(grep -c 'BEGIN CERTIFICATE' "$OUT/chain.txt" || true)
echo "    链中证书数: $COUNT"
[ "$COUNT" -ge 2 ] || { echo "!! 没抓到完整证书链"; exit 1; }

echo "[4] 提取最后一张（自签根 CA）"
python3 - "$OUT/chain.txt" "$OUT/gateway-root.pem" <<'PY'
import re, sys
s = open(sys.argv[1], errors="ignore").read()
blocks = re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", s, re.S)
open(sys.argv[2], "w").write(blocks[-1] + "\n")
print("    根证书已写出:", sys.argv[2])
PY
openssl x509 -in "$OUT/gateway-root.pem" -outform DER -out "$OUT/gateway-root.crt"
HASH=$(openssl x509 -in "$OUT/gateway-root.pem" -noout -subject_hash_old)
cp "$OUT/gateway-root.pem" "$OUT/${HASH}.0"
echo "    subject_hash_old = $HASH  → ${HASH}.0"
openssl x509 -in "$OUT/gateway-root.pem" -noout -subject -issuer -dates

echo "[5] 推到手机 Download，供系统设置安装"
"$ADB" push "$OUT/gateway-root.crt" /sdcard/Download/Cloudflare-Gateway-CA.crt >/dev/null
"$ADB" push "$OUT/gateway-root.pem" /sdcard/Download/gateway-root.pem >/dev/null

echo "[6] 验证证书本身（应为 http=301 / ssl=0）"
"$ADB" shell "curl --cacert /sdcard/Download/gateway-root.pem -m 10 \
  -o /dev/null -w 'http=%{http_code} ssl=%{ssl_verify_result}\n' https://1.1.1.1/" 2>&1

echo "完成。下一步：bash open-ca-install.sh 走系统安装流程（最后需本人输入锁屏 PIN）。"
