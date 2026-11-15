# 01 · 我们是怎么登录的

## 1. 先分清两件被混淆的事

一开始最容易踩的坑，是把「**团队账号登录**」和「**设备建立 WARP 隧道**」当成一件事。实际上：

| | 谁负责 | 依赖什么 |
|---|---|---|
| 团队登录 / enrollment | Cloudflare Access + One App | 浏览器认证、JWT 回跳、服务端下发配置 |
| 隧道初始化 | WARP 客户端（App 内） | 能否连到 Cloudflare 边缘，尤其是 `1.1.1.1:443` |

登录页面转圈，看起来像「账号没登进去」，实际是 **JWT 已经被消费、App 卡在隧道初始化**。这也是为什么换浏览器、清 Edge 设置都没用。

## 2. 完整链路（逐步）

### Step 1 · App 内输入团队名

打开 `com.cloudflare.cloudflareoneagent`，输入组织名 `zhijiankele`。
> 现场坑：曾误输成 `zhijiankeles`，Access 直接 404。团队名必须和 `*.cloudflareaccess.com` 的子域完全一致。

### Step 2 · 跳系统浏览器做 Access 认证

App 拉起浏览器访问 `https://zhijiankele.cloudflareaccess.com`。
认证用 **Edge 保存的密码自动填充**完成（不导出、不解密密码库）—— 本机 Edge 157 的密码库是 App-Bound Encryption v20，密钥绑定进程，外部程序无法解密，所以「用密码填充」比「读密码库」可靠得多。

### Step 3 · Success 页生成 deep link

认证成功后页面发起自定义 scheme：

```
com.cloudflare.zt://zhijiankele.cloudflareaccess.com/auth?token=<JWT>
```

JWT 解码后的关键字段（只记字段名，值不入库）：

| 字段 | 含义 |
|---|---|
| `email` | 团队登录邮箱 |
| `warp` | `true` |
| `country` | `CN` |
| `iat` / `exp` | **`exp - iat = 60` 秒** |

**60 秒是整条链路最紧的时间窗**：从 Success 页出现，到 App 消费完 token，超过就报 `Authentication Expired`。

### Step 4 · Android「打开方式」对话框 → 选 Cloudflare One

这一步常被系统对话框卡住。自动化做法是等对话框出现后点击「Cloudflare One / 仅此一次」，再确认。脚本 `tools/cf-fast.sh` 把全程压到 15 秒内；`tools/cf-login.sh` 则直接从 `dumpsys activity activities` 里 grep `dat=com.cloudflare.zt://...` 抓出完整 URL，用 `am start -a VIEW -d '<URL>'` 立刻投递，绕过点击。

### Step 5 · App 消费 JWT → enrollment → 建隧道

成功后 `shared_prefs` 里出现：

```
warp_registration_id
warp_token
warp_account
warp_tunnel_config
account_policy
```

VPN 由 `com.cloudflare.app.vpnservice.CloudflareVpnService` 持有：

```
tun0 = 100.96.0.4/32        # WARP 地址段
ip rule → table 1061 → tun0 # 默认路由
出口 colo = LAX, loc = CN
```

UI 显示「已连接 / 受保护」。

## 3. 为什么一开始登不进去

```
JWT 已被消费
   ↓
App 初始化 WARP → 连 1.1.1.1:443
   ↓
TCP 握手被丢包 → 一直重试 / 转圈
   ↓
超过 60s → Authentication Expired / CF_REGISTRATION_MISSING
   ↓
「您的设备无法建立连接。请联系您的管理员寻求帮助。」
```

三网实测（家宽 WiFi、中国移动流量、中国联通流量）下 `1.1.1.1:443` 全部超时，而 `api.cloudflareclient.com`、`engage.cloudflareclient.com` 都通。`1.1.1.1` 是硬编码 Anycast IP，改 DNS / 私人 DNS 都绕不开。

> **注意**：用户提到「同卡同网、别人设备（小米 / vivo）能正常登录」。若 `1.1.1.1:443` 对大家都封，登录流程未必强依赖它，因此可能还存在设备侧因素（App 残留注册数据、跨大版本升级遗留、root 触发设备姿态检查）。**这一条没有做对照实验，不能下结论**，验证方法见 [04-results.md](04-results.md)。

## 4. 突破点：先修网络，再登录

关键不是换登录方式，而是**调换顺序**：

1. 用 `tools/warp-gen.py` 注册一个消费级 WARP 身份，生成 WireGuard 配置；
2. 手机装 ClashMeta for Android（`com.github.metacubex.clash.meta`），导入 `examples/warp-clash.yaml.example`（模板）；
3. 隧道起来后，`1.1.1.1` 从「6 次全断」变成 `400 / 3.7s`，出口 `104.28.208.136 (LAX)`；
4. **此时再走一遍 Step 1–5，登录一次通过**，甚至跳过了 2FA 设置页。

外部 WARP 隧道只提供「网络可达性」，**不提供 Zero Trust 注册**；注册仍由团队 JWT 完成。两者不是一回事，也不能互相替代：

- 消费级 `/reg` 随机注册出来的身份（给 ClashMeta 用）无法喂进官方 App 当成 Zero Trust 设备；
- WARP App 报的「未注册」是 **Zero Trust 设备 enrollment 缺失**，不是消费级注册缺失。

现场验证：One 的 `shared_prefs` 注册字段齐全；反倒是 `com.cloudflare.onedotonedotonedotone`（1.1.1.1 App）只有 `zt_data_cleared`、`vpn_profile_installed`、`onboardingstatus` 这类 UI 标记。

## 5. 登录成功后的新阻塞

隧道一通，立刻暴露第二层问题：Gateway 开了 **TLS 解密**，所有 HTTPS 被 `Gateway CA - Cloudflare Managed G1` 重签。设备没有这张根证书，`curl` 报 `(60) self signed certificate in chain (19)`，夸克报 `net::ERR_CERT_AUTHORITY_INVALID`。

也就是说：**登录成功了，但网页打不开。** 后续处理见 [03-solutions.md](03-solutions.md)。

## 6. 一个值得记住的判断顺序

遇到「登录转圈」，先问自己：这是**认证没过**，还是**认证过了、后续初始化卡住**？

- 浏览器出现 Success 页 / 抓得到 deep link → 认证已过，去查网络和客户端初始化；
- 浏览器就 404 / 认证失败 → 查团队名、账号、时间偏差；
- 报 `Authentication Expired` → 大概率是「60 秒窗口被后续步骤耗光」，而不是 token 本身没发。

这三条能把排查范围砍掉一大半。你觉得如果 `1.1.1.1:443` 从一开始就通，这次的登录会卡在哪一步？
