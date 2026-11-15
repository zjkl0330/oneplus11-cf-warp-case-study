# 一加 11 恢复 WARP / Cloudflare One 全流程复盘

> 设备：OnePlus 11 `PHB110`（ColorOS / Android 16，KernelSU LKM root，序列号在日志中记为 `c72992cc`）
> 时间：2026-11-14 22:37 → 2026-11-15 02:47（GMT+8）
> 性质：一次真机排障的完整记录，包含**结论、登录链路、排查证据、解决方法、最终结果**，以及**被实测推翻的错误推断**

## 一句话结论

`1.1.1.1:443` 被定向阻断，导致两个 Cloudflare App 都无法完成初始化和团队登录；先用消费级 WARP WireGuard 隧道恢复可达性后，Cloudflare One 登录**一次通过**并建立了 Zero Trust 隧道，但 Gateway 开启了 TLS 解密，设备不信任其根证书，HTTPS 因此全线失败。根证书已从真实 TLS 握手中抓出并验证有效，**最后一步（安装时输入 6 位锁屏 PIN）尚未完成**。

## TL;DR

| 项目 | 结论 |
|---|---|
| 表层症状 | WARP 转圈 / `CF_REGISTRATION_MISSING` / 团队登录跳转后卡住 / `Authentication Expired` |
| 根因 ①（网络层） | `1.1.1.1:443` TCP 握手不成立，家宽、中国移动流量、中国联通流量下**均不通**；同 IP 的 UDP 53、ICMP 有时通 |
| 根因 ②（应用层） | Zero Trust Gateway 开启 TLS 解密，HTTPS 被 `Gateway CA - Cloudflare Managed G1` 重签，设备无该 CA |
| 登录怎么打通的 | 先跑外部 WARP WireGuard 隧道（ClashMeta）让 `1.1.1.1` 可达 → 再走团队登录流程 → 一次成功 |
| 现在能用吗 | **One：能连、不能正常上网；WARP App：不能用**。详见 [04-results](docs/04-results.md) |
| 最干净的解法 | 后台关闭 TLS 解密（无需任何证书）；或装用户 CA（需本人输 PIN）；或 root 装系统 CA（需 KSU 模块 + 重启） |
| 尚未解决 | CA 安装卡在锁屏 PIN；Zero Trust 侧 DNS 解析异常；同网下「别人能登录、本机会失败」未做对照实验 |

## 目录

| 文档 | 内容 |
|---|---|
| [01-login-flow.md](docs/01-login-flow.md) | **我们是怎么登录的**：完整链路、JWT 60 秒窗口、失败点与突破点 |
| [02-diagnosis.md](docs/02-diagnosis.md) | 排查时间线、逐项证据表、被推翻的错误推断 |
| [03-solutions.md](docs/03-solutions.md) | 三条解法 + 抓 Gateway 根证书的可复现配方与坑 |
| [04-results.md](docs/04-results.md) | 最终状态逐项核对、遗留问题、下一步 |
| [tools/](tools/) | 现场用过的脚本（已脱敏、参数化） |
| [examples/](examples/) | 配置模板（私钥全部占位） |
| [artifacts/](artifacts/) | 从真实握手抓到的 Gateway 根证书与原始证书链 |

## 1. 登录链路（摘要）

```
Cloudflare One App
  └─ 输入团队名 zhijiankele
      └─ 系统浏览器 → https://zhijiankele.cloudflareaccess.com
          └─ Cloudflare Access 身份认证（Edge 密码填充）
              └─ Success 页 → com.cloudflare.zt://…/auth?token=<JWT>   ← 有效期仅 60s
                  └─ Android「打开方式」对话框 → 选 Cloudflare One
                      └─ App 消费 JWT → Zero Trust 设备 enrollment
                          └─ 下发配置 → VpnService：tun0 = 100.96.0.4/32，出口 LAX
```

JWT payload 关键字段：`email`、`warp=true`、`country=CN`、**`exp - iat = 60s`**。
App 拿到 token 后仍需连 `1.1.1.1:443` 做初始化；链路被封 → 一直转圈 → 超过 60 秒 → `Authentication Expired` / `CF_REGISTRATION_MISSING`。**所以「先修网络、再登录」是这次突破的关键顺序。**

## 2. 排查结论（摘要）

`1.1.1.1` 是**硬编码的 Anycast IP**，不是域名 —— 改 DNS、换私人 DNS、换 APN 都绕不开；能通的是 `engage.cloudflareclient.com:2408`，这正是外部 WireGuard 隧道能跑通的原因。

排除项：系统时间偏差、Private DNS、VPN 槽位被占、App 网络权限、后台冻结、GMS 缺失、浏览器设置。
关键实测：`1.1.1.1:443` 三种网络全 `000`；`api.cloudflareclient.com`、`www.cloudflare.com`、`engage.cloudflareclient.com` 均通。

## 3. 解法（摘要）

1. **绕过阻断**：`tools/warp-gen.py` 生成 X25519 密钥 → POST `api.cloudflareclient.com/v0a2158/reg` → 组装 WireGuard / ClashMeta 配置。关键是 `reserved = base64decode(client_id)` → `[78, 175, 11]`，缺了握手必失败。
2. **修证书**：三选一 —— 关 TLS 解密 / 装用户 CA / root 装系统 CA。API 下载证书被 403 挡住，于是改为**从设备真实 TLS 握手里抓根证书**（完整配方见 [03-solutions.md](docs/03-solutions.md)）。
3. **拿权限**：KernelSU 超级用户页搜索 `shell` → `Shell / com.android.shell` (UID 2000) → 打开「超级用户」，`adb shell su -c id` 得到 `uid=0(root)`。KSU 是主动授权制，shell 不会自动弹窗。

## 4. 结果（摘要，如实）

| 项 | 状态 |
|---|---|
| Cloudflare One 隧道 | ✅ `tun0 100.96.0.4/32`，出口 `colo=LAX`、`loc=CN` |
| Zero Trust 注册数据 | ✅ `warp_registration_id` / `warp_token` / `warp_account` / `warp_tunnel_config` 齐全 |
| HTTPS（跳过证书校验） | ✅ Google `204`、`1.1.1.1` `301`、trace `200` |
| HTTPS（严格校验） | ❌ `curl (60) / ssl_verify=19` |
| Gateway 根证书 | ✅ 已抓到，`curl --cacert` 验证 `ssl=0`，有效期 2025-02-09 → 2030-02-09 |
| 用户 CA 登记 | ❌ 系统「信任的证书 → 用户」显示**无证书**，卡在锁屏 PIN |
| WARP（1.1.1.1 App） | ❌ 原生链路仍封，且 Android 单 `VpnService` 槽位与 One 互斥 |
| DNS | ⚠️ `1.1.1.1` 直连正常，但域名解析失败（VPN DNS `192.0.2.3`） |

**最后一次现场实测为 02:47；此后设备断开 USB，未再复核，以上状态不保证仍然成立。**

## 5. 安全与脱敏声明

- 本仓库**不含**任何 GitHub / Cloudflare API Token、WireGuard 私钥、设备完整 JWT、锁屏 PIN。
- `examples/` 内所有私钥均为 `<YOUR_PRIVATE_KEY>` 占位；`tools/warp-gen.py` 运行时生成密钥，只写本地文件、不提交。
- `artifacts/` 内是**公开的 CA 公钥证书**（不含私钥），其 CN 含本人 Cloudflare Account ID，仅作为流程证据；其他组织请用自己抓到的证书。
- 团队名、包名、域名、IP 属于公开可观察信息，保留以便复现。

## 6. 复现前提

- 一台已开启 USB 调试的 Android 设备；本机用 OPPO 互联自带的 `C:\Program Files\coloros-assist\adb.exe`，无需另装 platform-tools。
- Git Bash 下执行 adb 需 `export MSYS_NO_PATHCONV=1`，否则 `/sdcard/...` 会被转换成 Windows 路径。
- 手机自带 `/system/bin/curl` 可用来做 TLS / HTTP 验证；抓证书需要 root（KernelSU）与 busybox。
- 所有脚本里的坐标基于 **1080×2412** 屏幕，换设备需重新用 `uiautomator dump` 取 bounds。

## License

个人排障记录，供参考。涉及第三方产品（Cloudflare、ClashMeta、KernelSU）的行为以其官方文档为准。
