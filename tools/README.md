# tools/ 目录说明

所有脚本均为**现场用过的脚本整理版**，已做参数化与脱敏；坐标基于一加 11 的 **1080×2412** 屏幕，换设备请用 `uiautomator dump` 重新取 bounds。

| 脚本 | 作用 | 是否需要 root |
|---|---|---|
| `diag-warp.sh` | 八项只读现场诊断：设备信息、时间、Private DNS、VPN 槽位、路由、`1.1.1.1:443` 连通性、证书校验、logcat | 否 |
| `warp-gen.py` | 注册消费级 WARP 身份，生成 WireGuard / ClashMeta 配置（含 `reserved`） | 否（PC 侧） |
| `cf-login.sh` | 抓 `com.cloudflare.zt://…/auth?token=…` deep link 并立即投递给 App | 否 |
| `cf-fast.sh` | 极速登录变体，把全程压进 15 秒 JWT 窗口 | 否 |
| `grab-gateway-ca.sh` | 从设备真实 TLS 握手里抓 Gateway 根 CA，转换成 `.crt` / `<hash>.0` 并验证 | **是**（KSU 给 Shell 授权） |
| `relay3.sh` | 手机侧中继，由 `busybox nc -lk -e` 调用 | 否（但需 shell 可读） |
| `open-ca-install.sh` | 把系统设置点到「输入锁屏密码」页 | 否 |

## 通用前提

```bash
export MSYS_NO_PATHCONV=1                       # Git Bash 下必须，否则 /sdcard/... 被转成 Windows 路径
ADB="/c/Program Files/coloros-assist/adb.exe"  # 可用环境变量 ADB 覆盖
```

## 安全

- 脚本**不读取、不输出、不存储**任何 API Token、WireGuard 私钥或完整 JWT。
- `warp-gen.py` 生成的 `warp.conf` / `warp-clash.yaml` 含明文私钥，已由 `.gitignore` 排除，请勿提交。
- `cf-login.sh` 只打印 deep link 的**长度**，不打印 token 内容。
- `grab-gateway-ca.sh` 的中继必须以 **shell (uid 2000)** 身份运行；`su` 下 uid 0 的流量不走 `tun0`，抓不到 Gateway 重签的证书。

## 典型调用顺序

```bash
bash diag-warp.sh                                  # 1. 定位问题
python warp-gen.py --out-dir ./out                 # 2. 生成绕行配置（ClashMeta 导入）
bash cf-login.sh <团队名>                          # 3. 隧道起来后再登录
bash grab-gateway-ca.sh ./artifacts               # 4. 抓根证书
bash open-ca-install.sh                           # 5. 走到 PIN 页，本人输入
```
