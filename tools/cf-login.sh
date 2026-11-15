#!/bin/bash
# Cloudflare One 团队登录：从浏览器 Activity 里抓新鲜 deep link，直接投递给 App。
# 用途：绕开「打开方式」对话框的点击，把 60 秒 JWT 窗口压到最短。
#
# 用法: bash cf-login.sh <团队名>         例: bash cf-login.sh zhijiankele
# 坐标基于 1080x2412 屏幕，换设备请用 uiautomator dump 重新取 bounds。
ADB="${ADB:-/c/Program Files/coloros-assist/adb.exe}"
ORG="${1:?用法: bash cf-login.sh <团队名>}"
export MSYS_NO_PATHCONV=1

echo "[1] 回到 App"
"$ADB" shell "input keyevent 4" >/dev/null 2>&1
sleep 1
"$ADB" shell "monkey -p com.cloudflare.cloudflareoneagent -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1
sleep 3

echo "[2] 填入团队名: $ORG"
"$ADB" shell "input tap 540 1385"
sleep 1
"$ADB" shell "input text $ORG"
sleep 1

echo "[3] 提交，等待浏览器出现 Success 页"
"$ADB" shell "input keyevent 66"
sleep 7

echo "[4] 抓 deep link（只打印长度，不打印 token 内容）"
URL=$("$ADB" shell "dumpsys activity activities" 2>/dev/null \
  | grep -oE "dat=com\.cloudflare\.zt://[^ ]+" | head -1 | sed 's/^dat=//')
LEN=${#URL}
echo "URL 长度: $LEN"

if [ "$LEN" -lt 50 ]; then
  echo "!! 没抓到 deep link —— 检查团队名、Access 认证是否成功、JWT 是否已过期"
  exit 1
fi

echo "[5] 立即投递给 App"
"$ADB" shell "am start -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d '$URL'" 2>&1 | tail -3
sleep 4

echo "[6] 当前前台"
"$ADB" shell "dumpsys activity activities | grep -E 'topResumedActivity'" | head -1
