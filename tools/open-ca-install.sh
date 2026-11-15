#!/bin/bash
# 把系统设置走到「输入锁屏密码」页，剩下的必须由设备主人本人完成。
# 用法: bash open-ca-install.sh
# 前置: 先跑 grab-gateway-ca.sh，确保 /sdcard/Download/Cloudflare-Gateway-CA.crt 存在。
# 坐标基于 1080x2412 / ColorOS；换机型请用 uiautomator dump 重新取 bounds。
ADB="${ADB:-/c/Program Files/coloros-assist/adb.exe}"
export MSYS_NO_PATHCONV=1

"$ADB" shell "am start -a android.settings.SECURITY_SETTINGS" >/dev/null 2>&1; sleep 2
"$ADB" shell "input tap 190 1990" >/dev/null 2>&1; sleep 2   # 凭据存储
"$ADB" shell "input tap 300 670"  >/dev/null 2>&1; sleep 2   # 从存储设备安装证书
"$ADB" shell "input tap 170 400"  >/dev/null 2>&1; sleep 2   # CA 证书
"$ADB" shell "input tap 154 2256" >/dev/null 2>&1; sleep 2   # 仍然安装（隐私警告）

# 文件选择器：展开根目录 → 搜索证书名 → 选中
"$ADB" shell "input tap 864 192"  >/dev/null 2>&1; sleep 1
"$ADB" shell "input text Cloudflare" >/dev/null 2>&1; sleep 2
"$ADB" shell "input keyevent 4"  >/dev/null 2>&1; sleep 1     # 收起键盘
"$ADB" shell "input tap 300 900" >/dev/null 2>&1; sleep 2     # 选中证书

# 命名（名称为空时「确定」是灰的）→ 确定 → 应进入锁屏密码页
"$ADB" shell "input text CloudflareGatewayCA" >/dev/null 2>&1; sleep 1
"$ADB" shell "input tap 786 1350" >/dev/null 2>&1; sleep 2

echo "--- 当前界面文字（应出现输入锁屏密码相关提示） ---"
"$ADB" shell "uiautomator dump /sdcard/ca-state.xml >/dev/null 2>&1; cat /sdcard/ca-state.xml" 2>/dev/null \
  | grep -oE 'text="[^"]{2,80}"' | head -20
echo
echo ">>> 请在手机上输入锁屏 PIN。安装后到「设置 → 凭据存储 → 信任的证书 → 用户」核对是否出现该证书。"
