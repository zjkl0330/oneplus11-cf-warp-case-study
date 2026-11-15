#!/usr/bin/env python3
"""
注册一个消费级 WARP 身份（api.cloudflareclient.com /v0a2158/reg），
生成 WireGuard 配置与 ClashMeta WireGuard 出站配置。

安全约定：
  * PrivateKey 只写进本地生成的文件，绝不提交到版本库；
  * 本脚本不读取、不输出任何 API Token；
  * 生成的 *.conf / *.yaml 已在 .gitignore 中排除。

用法:
  python warp-gen.py                 # 输出到当前目录
  python warp-gen.py --out-dir DIR  # 指定输出目录

依赖: openssl（Git Bash / Linux / macOS 自带或可安装）
"""

import argparse
import base64
import datetime
import json
import os
import ssl
import subprocess
import sys
import urllib.request

REG_URL = "https://api.cloudflareclient.com/v0a2158/reg"
ENDPOINT_PORT = 2408
LOCAL_DNS = ["119.29.29.29", "223.5.5.5"]


def gen_keys():
    """openssl 生成 X25519 密钥对，取 DER 尾部 32 字节 raw key"""
    priv_der = subprocess.run(
        ["openssl", "genpkey", "-algorithm", "X25519", "-outform", "DER"],
        capture_output=True, check=True,
    ).stdout
    pub_der = subprocess.run(
        ["openssl", "pkey", "-pubout", "-outform", "DER"],
        input=priv_der, capture_output=True, check=True,
    ).stdout
    b64 = lambda b: base64.b64encode(b[-32:]).decode()
    return b64(priv_der), b64(pub_der)


def register(pub_b64):
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    body = {
        "key": pub_b64,
        "install_id": "",
        "fcm_token": "",
        "tos": now,
        "model": "PC",
        "type": "Android",
        "locale": "zh_CN",
    }
    req = urllib.request.Request(
        REG_URL,
        data=json.dumps(body).encode(),
        headers={
            "Content-Type": "application/json",
            "CF-Client-Version": "a-6.30-3596",
            "User-Agent": "okhttp/3.12.1",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30, context=ssl.create_default_context()) as r:
        return json.loads(r.read())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", default=".", help="输出目录（默认当前目录）")
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    priv, pub = gen_keys()
    resp = register(pub)
    cfg = resp.get("config", {})
    peer = cfg.get("peers", [{}])[0]
    iface = cfg.get("interface", {})

    peer_pub = peer.get("public_key", "")
    endpoint = peer.get("endpoint", {}).get("host", "engage.cloudflareclient.com")
    v4 = iface.get("addresses", {}).get("v4", "172.16.0.2")
    v6 = iface.get("addresses", {}).get("v6", "")
    client_id = cfg.get("client_id", "")

    # reserved 来自 client_id 的 base64 解码，缺失会导致 WARP 握手失败
    reserved = list(base64.b64decode(client_id)) if client_id else [0, 0, 0]

    print("peer_public_key =", peer_pub)
    print("endpoint        =", f"{endpoint}:{ENDPOINT_PORT}")
    print("v4              =", v4)
    print("reserved        =", reserved, "  <- 关键，别漏")
    print("account_id      =", resp.get("account", {}).get("id", ""))
    # 注意：不打印 account.license，那属于凭据

    wg = f"""[Interface]
PrivateKey = {priv}
Address = {v4}/32
DNS = 1.1.1.1, 1.0.0.1
MTU = 1280

[Peer]
PublicKey = {peer_pub}
AllowedIPs = 0.0.0.0/0
Endpoint = {endpoint}:{ENDPOINT_PORT}
PersistentKeepalive = 25
"""

    clash = f"""mixed-port: 7890
allow-lan: false
mode: rule
log-level: info

dns:
  enable: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
{chr(10).join('    - ' + d for d in LOCAL_DNS)}
    - https://cloudflare-dns.com/dns-query
  # 不要用 tls://1.1.1.1:853 做 fallback —— 被封的就是这个 IP

proxies:
  - name: "Cloudflare-WARP"
    type: wireguard
    server: {endpoint}
    port: {ENDPOINT_PORT}
    ip: {v4}
{f'    ipv6: "{v6}"' if v6 else ''}
    private-key: "{priv}"
    public-key: "{peer_pub}"
    udp: true
    reserved: {json.dumps(reserved)}
    mtu: 1280

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "Cloudflare-WARP"
      - "DIRECT"

rules:
  - MATCH,PROXY
"""

    for name, content in (("warp.conf", wg), ("warp-clash.yaml", clash)):
        path = os.path.join(args.out_dir, name)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        print("已写出:", path)

    print("\n提醒：这两个文件含明文 PrivateKey，请勿提交到任何版本库。")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("REG FAIL:", type(e).__name__, e, file=sys.stderr)
        sys.exit(1)
