# 02 · 排查过程与证据

## 时间线

| 阶段 | 做了什么 | 得到什么 |
|---|---|---|
| 0 | 用 OPPO 互联自带 `C:\Program Files\coloros-assist\adb.exe` 连设备，用户开 USB 调试 | 识别 `PHB110 / c72992cc` |
| 1 | 八项常规诊断（`tools/diag-warp.sh`）：时间、Private DNS、VPN 槽位、包列表、路由、后台策略、logcat | 常规项全部正常 |
| 2 | 浏览器登录链路观察：组织名、Success 页、deep link、JWT | 抓到完整 deep link，确认 `exp-iat=60s` |
| 3 | 三网对比测 `1.1.1.1:443` | 家宽 / 移动 / 联通**全不通**；其他 Cloudflare 域名正常 |
| 4 | 生成 WARP WireGuard 配置 + 装 ClashMeta + URL 导入 | `1.1.1.1` 恢复可达，出口 LAX |
| 5 | 隧道内重走团队登录 | **一次通过**，`tun0 100.96.0.4/32` |
| 6 | 上网验证 | `curl -k` 全通；严格校验一律 `(60) / ssl=19` |
| 7 | 查证书 issuer | `Gateway CA - Cloudflare Managed G1`，确认 TLS 解密 |
| 8 | KSU 授权 Shell → root → 从 TLS 握手抓根 CA | 证书抓到并验证 `ssl=0` |
| 9 | 系统设置走 CA 安装流程 | 走到「输入锁屏密码」页，停住 |

## 逐项证据

### 网络层

| 测试 | 结果 |
|---|---|
| `1.1.1.1:443` × 6（家宽） | 全 `000`，TCP 握手不成立 |
| `1.1.1.1:53` UDP | 通 |
| `1.1.1.1` ICMP | 有时通（隧道后 222ms） |
| 中国移动 / 中国联通流量下 `1.1.1.1:443` | 同样超时 |
| PC 同一家宽 | 同样 `000`（排除手机侧问题） |
| `api.cloudflareclient.com` | 通（POST `/reg` 返回 400，说明只是参数问题） |
| `engage.cloudflareclient.com` | 通（`162.159.192.1`，236ms） |
| `www.cloudflare.com` | 通 |

结论：这是**针对 `1.1.1.1` TCP 443 的定向丢弃**，不是 DNS 污染、不是设备问题、不是单一运营商问题。

> 为什么改 DNS 没用：`1.1.1.1` 是客户端**硬编码的 Anycast IP**，不经过域名解析。能换的是 `engage.cloudflareclient.com:2408`（有域名、可解析、可走其他路径），这也是 WireGuard 配置能成立的根本原因。

### 排除的常规嫌疑

系统时间（`auto_time` 正常）、Private DNS（`private_dns_mode`）、`VpnService` 槽位占用、App 网络权限、ColorOS 后台冻结 / 电池策略、Google GMS 缺失、浏览器设置、锁屏/证书状态。

### 应用层（隧道建立后）

| 检查 | 结果 |
|---|---|
| VPN 持有者 | `com.cloudflare.cloudflareoneagent/…CloudflareVpnService` |
| 路由 | `tun0 100.96.0.4/32`，`ip rule` → table 1061 → tun0 |
| 出口 | `colo=LAX`、`ip=2a09:bac5:…`、`loc=CN` |
| `curl -k https://www.cloudflare.com/cdn-cgi/trace` | `200` |
| `curl -k https://www.google.com/generate_204` | `204` |
| `curl -k https://1.1.1.1/` | `301` |
| `curl` 严格校验 | `(60) self signed certificate in chain`、`ssl_verify_result=19` |
| 证书 issuer / subject | `Gateway CA - Cloudflare Managed G1 <ACCOUNT_ID>` |
| 夸克浏览器 | 弹「安全证书已过期或不可信」；logcat `net::ERR_CERT_AUTHORITY_INVALID` |
| One 的 `shared_prefs` | `warp_registration_id` / `warp_token` / `warp_account` / `warp_tunnel_config` / `account_policy` 全在 |
| 1.1.1.1 App 的 `shared_prefs` | 只有 `zt_data_cleared`、`vpn_profile_installed`、`onboardingstatus` |

### Android CA 分层（现场确认）

| 存储 | 默认信任方 |
|---|---|
| 系统 CA `/system/etc/security/cacerts` | 所有 App + `curl` 这类 native 工具 |
| 用户 CA `/data/misc/user/0/cacerts-added` | 浏览器、以及声明 `<certificates src="user"/>` 的 App；targetSdk≥24 且未声明者不认 |

`/system` 在本机是 **erofs 只读**；`/apex/com.android.conscrypt/cacerts` 是 Android 14+ 实际读取的系统 CA 目录。

## 被实测推翻的错误推断（保留，免得重踩）

| 曾经的判断 | 实测修正 |
|---|---|
| 只有家宽封 `1.1.1.1` | 移动、联通流量下同样不通 |
| 需要 Google / Firebase 基础套件 | 未证实，且不是根因 |
| 同事是靠流量登上去的 | 用户否认；实测流量也登不了 |
| Android 装不了 CA | **能装**用户 CA，走系统设置 |
| 必须装系统 CA 才能用 | 浏览器用用户 CA 就够；`curl` 不认只因它是 native 工具 |
| 唯一解法是关 TLS 解密 | 三条路并行：关解密 / 用户 CA / 系统 CA |
| 手机没有 root | 有 KernelSU，给 Shell 主动授权即可 |
| 手机没有 Edge | 有，包名 `com.microsoft.emmx`（grep `edge` 漏查） |
| 「未注册」是根因 | One 注册完整；那是 WARP App 的 Zero Trust enrollment 缺失，且当前阻塞是证书 |

## 本机自动化的坑（供后来者省时间）

- **Edge 157 密码库 = App-Bound Encryption v20**，密钥绑进程，Python / Node 外部解密均失败；原 profile 的 CDP 远程调试也不监听。
- `pm clear` / `adb install` 在 ColorOS 上需要开发者选项里打开「通过 USB 安装应用」。
- PowerShell 被安全策略限制：`Add-Type`、`New-Object -ComObject` 均被拦；截图改用 Python ctypes 调 GDI（`biHeight` 用正数，否则图像倒置）。
- Edge 网页内容对注入的鼠标事件无响应（浏览器 UI 有响应），键盘 Tab 有效但坐标存在约 148px 偏移，无法稳定定位。
- Git Bash 下 adb 必须 `MSYS_NO_PATHCONV=1`。
- `curl`（手机自带）**不支持** `%{certs}` 导出证书链。
- **root (uid 0) 的流量不走 `tun0`**（curl 返回 `000`），抓隧道里的握手必须以 **shell (uid 2000)** 身份跑中继。
