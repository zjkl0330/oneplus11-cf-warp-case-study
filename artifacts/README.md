# artifacts/ 说明

这里是 **从设备真实 TLS 握手中抓到的 Cloudflare Gateway 根证书**及其原始证书链，都是**公钥材料，不含任何私钥、Token 或设备凭据**。

| 文件 | 说明 |
|---|---|
| `chain.txt` | `openssl s_client -showcerts` 导出的完整链（含 Gateway 重签的叶证书与根 CA） |
| `gateway-root.pem` | 链中最后一张、自签的根 CA（PEM） |
| `gateway-root.crt` | 同一张证书的 DER 格式，供 Android 系统设置安装 |
| `07a3c9b4.0` | 按 `openssl x509 -subject_hash_old` 命名的系统 CA 文件（PEM） |

## 证书信息

```
subject / issuer : CN = Gateway CA - Cloudflare Managed G1 <ACCOUNT_ID>
有效期           : 2025-02-09 → 2030-02-09
subject_hash_old : 07a3c9b4
验证             : curl --cacert gateway-root.pem https://1.1.1.1/ → 301 / ssl_verify_result=0
```

## 重要

- 证书 CN 含本人 Cloudflare Account ID，仅作为**流程证据**保留；**其他组织不能直接用这张证书**，因为 Gateway 的 TLS 解密用的是你自己账号那张。请按 [docs/03-solutions.md](../docs/03-solutions.md) 的配方抓自己的。
- 仅当后台 `Zero Trust → Traffic policies → Traffic settings` 启用了 TLS 解密时才会出现这种重签证书。最干净的做法是关掉解密，那样根本不需要这些文件。
