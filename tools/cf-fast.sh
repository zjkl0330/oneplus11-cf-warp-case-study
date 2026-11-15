#!/bin/bash
# 极速登录变体：全程压到 15 秒内（适用于 JWT exp-iat=60s 的窗口）。
# 用法: bash cf-fast.sh <团队名>
# 坐标基于 1080x2412 屏幕；前两个 tap 依次是 Success 页按钮与「打开方式」对话框选项。
ADB="${ADB:-/c/Program Files/coloros-assist/adb.exe}"
ORG="${1:?用法: bash cf-fast.sh <团队名>}"
OUT="${OUT:-.}"
export MSYS_NO_PATHCONV=1

"$ADB" shell "input keyevent 4" >/dev/null 2>&1
sleep 1
"$ADB" shell "monkey -p com.cloudflare.cloudflareoneagent -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1
sleep 2

"$ADB" shell "input tap 540 1385"
sleep 1
"$ADB" shell "input text $ORG"
sleep 1
"$ADB" shell "input keyevent 66"

sleep 6
"$ADB" shell "input tap 862 1446"
sleep 1
"$ADB" shell "input tap 538 1452"
sleep 4

echo "--- 状态 ---"
"$ADB" shell "dumpsys activity activities | grep -E 'topResumedActivity'" | head -1
"$ADB" shell "screencap -p /sdcard/f1.png" >/dev/null 2>&1
"$ADB" pull /sdcard/f1.png "$OUT/f1.png" 2>&1 | tail -1
