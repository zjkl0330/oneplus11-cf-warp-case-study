# 04 · 结果

## 逐项核对（最后一次现场实测：2026-11-15 02:47 GMT+8）

| 项 | 状态 | 证据 |
|---|---|---|
| Cloudflare One 团队登录 | ✅ 成功 | 一次通过，跳过 2FA 设置页；`shared_prefs` 注册字段齐全 |
| Zero Trust 隧道 | ✅ 已建立 | `CloudflareVpnService`、`tun0 100.96.0.4/32`、默认路由 table 1061 |
| 隧道出口 | ✅ | `colo=LAX`、`loc=CN`、WARP 地址段 |
| 上网（忽略证书校验） | ✅ | trace `200`、Google `/generate_204` `204`、`https://1.1.1.1/` `301` |
| 上网（严格校验） | ❌ | `curl (60) self signed certificate in chain`、`ssl_verify_result=19`；夸克 `ERR_CERT_AUTHORITY_INVALID` |
| 根因定位 | ✅ | 两层：`1.1.1.1:443` 定向阻断 + Gateway TLS 解密未信任 |
| WARP 绕行方案 | ✅ 跑通 | WireGuard / ClashMeta 出站，`1.1.1.1` 由全断 → `400`，出口 LAX |
| KernelSU root | ✅ | Shell 授权完成，`su -c id` = `uid=0(root)` |
| Gateway 根证书 | ✅ 已获取并验证 | `curl --cacert` → `301 / ssl=0`；产物在 `artifacts/` |
| 用户 CA 安装 | ❌ **未完成** | 「信任的证书 → 用户」显示**无证书**；流程走到「输入锁屏密码」页停住 |
| 系统 CA / native 工具 | ❌ 未完成 | 直接写目录、写 apexdata、bind mount 均不生效 |
| WARP（1.1.1.1 App） | ❌ 不能独立使用 | 原生 `1.1.1.1:443` 仍封；且 Android 单 `VpnService` 槽位与 One 互斥 |
| 域名解析 | ⚠️ 异常 | `1.1.1.1` 直连 301 / ping 通，但 `www.cloudflare.com`、`www.baidu.com` 报 `Could not resolve host`；VPN DNS 为 `192.0.2.3`；用 `--resolve` 指定 IP 则 `200` |
| 后台关闭 TLS 解密 | ❌ 未办成 | CDP 被 ABE v20 挡、`gateway/settings` 403、429 限流 |

> **状态时效**：10:31 再次尝试复核时设备已断开 USB（`adb devices` 为空），以上为 02:47 的最后实测结果，**不保证此后仍然成立**。

## 一句话回答「哪个能用」

- **Cloudflare One**：能连、能建隧道，但**不能正常上网**（卡在证书信任）。
- **WARP（1.1.1.1 App）**：**不能用**（卡在网络封锁 + VPN 槽位）。
- 但 One 那条隧道本身就是 Zero Trust 版 WARP（`100.96.0.4` 属 WARP 地址段、出口 LAX），所以解除证书阻塞后，「日常用 WARP / One」这个目标实际上已经达成，不必再单独开 1.1.1.1 App。

## 为什么不能宣称「已修好」

有一个矛盾信号值得警惕：强杀夸克后重新打开 `https://1.1.1.1/`，**不再弹**「安全证书已过期或不可信」。但同一时刻：

- `curl` 严格校验仍 `ssl=19`；
- 系统「用户」tab 显示无证书；
- 命名确定后界面退回安装页（典型的 PIN 验证被挡表现）。

浏览器「不弹窗」可能是缓存 / 页面未真正加载 / 用户点了「仍要继续」的残留状态，**不足以证明 CA 已登记**。按现场证据，结论只能是：**未装成**。

## 遗留问题

1. **锁屏 PIN**：唯一需要设备主人本人操作的一步。输完 PIN 后应立刻核对「用户」tab 和浏览器，并复测 `curl` 严格校验（预期 native 仍 `ssl=19`，符合 CA 分层）。
2. **DNS 解析异常**：`192.0.2.3` 是 Zero Trust 保留地址，怀疑与 One 的 DNS 网关 / DoH 设置或 Gateway DNS 策略有关。建议重连 One，或检查 `设置 → 高级 → DoH 网关 / WARP 网关`。
3. **同网对照实验未做**：用户明确说同卡同网下别人的小米 / vivo 能登录。若 `1.1.1.1:443` 对大家都封，登录流程理论上未必强依赖它，可能还有设备侧因素。验证方法：
   - 清 One 与 1.1.1.1 App 数据（ColorOS 拦 `pm clear`，需走系统设置 UI）；
   - 无隧道重试登录 → 记录是否 `CF_REGISTRATION_MISSING`；
   - 开隧道重试 → 对比；
   - 用另一台设备同网做同样两步。
   当时没做，因为会打断已经连上的会话。
4. **系统 CA 永久化**：需要 KSU 模块 + 重启，或直接走路径 A 关 TLS 解密。
5. **后台自动化**：Edge ABE v20 / token 权限 / 429 三个阻塞都没解决；如果拿到有 `Gateway: Edit` 权限的 token，`gateway/configuration` 可以直接关解密，比装证书干净得多。

## 现场留下的临时改动（重启即失效）

- `mount --bind /data/local/tmp/cacerts_new` 覆盖 `/apex/com.android.conscrypt/cacerts`（init 命名空间已挂，`/proc/mounts` 可见）；
- 写入 `/data/misc/apexdata/com.android.conscrypt/cacerts/07a3c9b4.0`；
- 写入 `/data/misc/user/0/cacerts-added/07a3c9b4.0`（已 `chcon`）；
- 手机 `/sdcard/Download/` 下有 `Cloudflare-Gateway-CA.crt`、`07a3c9b4.0`、`gateway-root.pem`；
- `adb forward tcp:9443 tcp:8443` 与手机上的 `busybox nc -lk` 中继进程。

**没有改动系统分区，没有改动 Cloudflare 后台配置。**

## 下次遇到同类问题的判断顺序

1. 浏览器能否出现 Success 页 / 能否抓到 deep link？→ 区分「认证失败」与「初始化卡住」；
2. 用设备自带 `curl` 分别测 `1.1.1.1:443` 与其他 Cloudflare 域名 → 定位是不是 Anycast IP 被定向阻断；
3. 隧道起来后，严格校验 vs `-k` 对比 → 一眼区分「网络不通」和「证书不信任」；
4. 看 `curl -v` 的 issuer → 确认是不是 Gateway TLS 解密；
5. 再决定是关解密、装用户 CA，还是 root 装系统 CA。

如果第 2 步就通、第 3 步也通，那这次的两层问题都不存在 —— 你觉得那时应该先怀疑什么？
