# 03 · 解决方法

## 第一层：让 `1.1.1.1` 可达（已跑通）

### 1. 注册消费级 WARP 身份

`tools/warp-gen.py`：openssl 生成 X25519 密钥对 → POST `https://api.cloudflareclient.com/v0a2158/reg` → 输出 WireGuard 配置。

请求必须带 `CF-Client-Version: a-6.30-3596`、`User-Agent: okhttp/3.12.1` 等客户端头，否则返回 400。

### 2. 关键字段：`reserved`

```python
import base64
client_id = resp["config"]["client_id"]      # 形如 "Tq8L"
reserved = list(base64.b64decode(client_id)) # → [78, 175, 11]
```

**少了 `reserved` 握手必失败**。WireGuard 原生配置没有这个字段，所以这一步更适合用 ClashMeta / sing-box 这类支持 `reserved` 的客户端。

### 3. 配置模板

- `examples/warp.conf.example` —— 原生 WireGuard
- `examples/warp-clash.yaml.example` —— ClashMeta WireGuard 出站

Endpoint 用 `engage.cloudflareclient.com:2408`（曾经误写成 `…:2408:2408`，导致连不上）。
DNS 不要用 `tls://1.1.1.1:853` 做 fallback —— 正是这个 IP 被封，会把 DNS 一起拖死；改用 `119.29.29.29` / `223.5.5.5` / `https://cloudflare-dns.com/dns-query`。

### 4. 手机侧导入

装 ClashMeta for Android v2.11.37（`com.github.metacubex.clash.meta`），把 yaml 推到 `/sdcard/Download/` 后系统文件选择器不显示它，**改成 URL 导入**最省事：

```bash
python -m http.server 8000 --bind 192.168.10.10
# 手机浏览器导入 http://192.168.10.10:8000/warp-clash.yaml
```

验证：`1.1.1.1` 从 6 次全断 → `400 / 3.7s`，出口 `104.28.208.136 / LAX`。**然后立刻重走团队登录**（见 [01-login-flow.md](01-login-flow.md)）。

---

## 第二层：解决 Gateway TLS 解密证书

### 三条路径与取舍

| | 做法 | 优点 | 代价 / 现状 |
|---|---|---|---|
| **A（最干净）** | 后台 `Zero Trust → 流量策略 / Traffic settings → Proxy and inspection` 关闭 TLS decryption / HTTPS inspection，或停用解密规则、加 bypass | 完全不需要任何证书，所有 App 立即恢复，也不用 root | 需要后台登录权限。本机没打通：Edge ABE v20 挡 CDP、现有 `cfat_` token 对 `gateway/settings` 返回 403、还撞上 429 限流 |
| **B（最省事）** | 装**用户 CA**：`设置 → 凭据存储 → 从存储设备安装 → CA 证书` | 不用 root，浏览器即可恢复 | 部分 App / `curl` 不认；Android 7+ 用户 CA 需走系统安装器；**本次卡在锁屏 PIN** |
| **C（最彻底）** | root 装**系统 CA**：KSU 模块 / overlay 把 `<hash>.0` 放进系统 CA 目录 | 覆盖所有 App + native 工具 | 需要 root + 模块 + 重启；`/system` 是 erofs 只读，不能硬改 |

官方依据（developers.cloudflare.com/cloudflare-one/…/user-side-certificates/）：

- 「**Mobile devices require manual installations**」——桌面端 One Client 会自动把证书装进系统存储（`installed_certs/<id>.pem`），**Android / iOS / ChromeOS 在 System Availability 表里均为 ❌**。实测翻遍 One 的「设置 / 高级 / 连接选项」，Android 版确实没有装 CA 入口。
- 自动下发需要后台 `Settings → WARP Client → Install CA to system certificate store` 打开，且证书状态为 `Available and In-Use`（先 Activate，再 Confirm and turn on certificate）。
- 官方把「**Turn off TLS Decryption**」列为证书问题的快速解法。
- 证书官方下载位置：`Zero Trust → Traffic policies → Traffic settings → Certificates`（`.pem` / `.crt`）。

### 拿不到证书时：从真实 TLS 握手里抓（本次成功方案）

后台 API 被 403 挡住、公开端点 404、`cdn-cgi/access/certs` 返回的是 JWKS 不是 CA。于是直接从设备当前正在用的链路上把根证书抓出来。

**前提**：设备已连 One 隧道；KSU 已给 Shell 授权（见下）；PC 有 openssl。

```bash
export MSYS_NO_PATHCONV=1
ADB="/c/Program Files/coloros-assist/adb.exe"

# 1) 把 busybox 复制到 shell 可读的位置，并放好中继脚本
"$ADB" push tools/relay3.sh /data/local/tmp/relay3.sh
"$ADB" shell su -c 'cp /data/adb/ksu/bin/busybox /data/local/tmp/busybox; \
                     chmod 755 /data/local/tmp/busybox /data/local/tmp/relay3.sh'

# 2) 端口转发 + 以 shell(uid 2000) 身份起持久中继（注意：不要用 su 跑）
"$ADB" forward --remove-all
"$ADB" forward tcp:9443 tcp:8443
"$ADB" shell "/data/local/tmp/busybox nc -lk -p 8443 -e /data/local/tmp/relay3.sh" &

# 3) PC 侧发起 TLS 握手，导出完整链
openssl s_client -connect 127.0.0.1:9443 \
  -servername www.cloudflare.com -showcerts </dev/null > chain.txt
```

`tools/relay3.sh` 内容只有一行：

```sh
#!/system/bin/sh
exec /data/local/tmp/busybox nc 1.1.1.1 443
```

**链里最后一张就是自签根 CA**，提取并命名：

```bash
# 取最后一个 PEM 块 → gateway-root.pem
openssl x509 -in gateway-root.pem -outform DER -out gateway-root.crt
openssl x509 -in gateway-root.pem -noout -subject_hash_old   # → 07a3c9b4
cp gateway-root.pem 07a3c9b4.0        # 系统 CA 目录要求的 <hash>.0 命名
```

**验证证书本身是否正确**：

```bash
adb shell "curl --cacert /sdcard/Download/gateway-root.pem \
  -o /dev/null -w '%{http_code} %{ssl_verify_result}' https://1.1.1.1/"
# → 301 0   (ssl_verify_result=0 表示校验通过)
```

本次抓到的证书：`CN = Gateway CA - Cloudflare Managed G1 <ACCOUNT_ID>`，有效期 2025-02-09 → 2030-02-09，`subject_hash_old = 07a3c9b4`。

### 抓证书踩过的坑（都很关键）

| 坑 | 说明 |
|---|---|
| **root 不走隧道** | `su -c curl https://…` 返回 `000`；uid 0 的流量不进 `tun0`。中继必须以 **shell (uid 2000)** 身份启动 |
| **目标必须用 IP** | 域名解析在 Zero Trust DNS 下会失败（`DnsAddresses: [192.0.2.3]`），中继目标写 `1.1.1.1 443` 而不是域名 |
| `curl %{certs}` | 手机自带 curl 不支持该变量 |
| PC 直连 | PC 的 openssl 不走手机隧道，看不到 Gateway 重签证书 |
| `android.credentials.INSTALL` 直接 intent | ColorOS 明确提示「必须通过设置安装」，被拦 |
| 直接写 `/data/misc/user/0/cacerts-added/` | 即使 `chmod` + `chcon user_cacerts_file` 也不生效，Android 16 需要走安装器登记 |
| 写 `/data/misc/apexdata/com.android.conscrypt/cacerts/` | 不生效 |
| `mount --bind` 覆盖 `/apex/com.android.conscrypt/cacerts` | 含全部系统 CA + 新证书、全局命名空间挂载 rc=0 且 `/proc/mounts` 可见，但 curl 仍 `ssl=19`（应用进程 mount ns / conscrypt 缓存未刷新）。**重启即失效，未改系统分区**；要永久生效需做 KSU 模块并重启 |

### KernelSU 给 Shell 授权（root 怎么拿到的）

KSU 是**主动授权制**，adb shell 不会自动弹授权框，默认超级用户列表里也没有 shell：

1. 打开 KernelSU → 底部「超级用户」；
2. 点搜索，输入 `shell` → 出现 `Shell / com.android.shell`（UID 2000）；
3. 进入 App Profile → 打开「超级用户」开关；
4. 验证 `adb shell su -c id` → `uid=0(root) gid=0(root)`。

`adb root` 在 production build 上直接被拒，不要浪费时间。

### 系统设置装 CA 的完整点击路径（走到 PIN 为止）

```
android.settings.SECURITY_SETTINGS
  → 凭据存储
    → 从存储设备安装证书
      → CA 证书
        → 「仍然安装」（隐私警告页）
          → 文件选择器搜索 Cloudflare-Gateway-CA.crt
            → 为此证书输入名称（名称为空时「确定」是灰的）
              → 确定
                → 【输入锁屏密码】← 唯一必须本人操作的一步
```

安装是否真的落地，用 `设置 → 凭据存储 → 信任的证书 → 用户` 核对；**不要**只看浏览器有没有弹证书错误（强杀浏览器后曾出现「不弹窗」的假阳性）。

## 剩下的两件事

若要彻底覆盖所有 App（含 native 工具），需要写一个 KSU 模块：把 `07a3c9b4.0` 挂进系统 CA 目录并重启，使 conscrypt 重新加载信任库。或者更简单 —— 走路径 A 关掉 TLS 解密，那时连证书都不用装。
