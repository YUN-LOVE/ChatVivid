# Android 统一签名

> 目标：**一份 keystore，签所有 chatvv Android 产物**——debug 和 release、本机和 CI、
> 所有构建机都用同一张证书。这样同一个 `applicationId` 的包可以互相覆盖安装、
> 保留用户数据，也不会出现「这台机器编的 APK 装不上那台机器编的」。
>
> 签名相关脚本：`platforms/android/make-keystore.sh`、`platforms/android/setup-signing.sh`。

## 0. 为什么必须签

- Android 安装/更新时会校验「包名 + 签名证书」：证书不同就不能覆盖安装（只能卸载重装，
  数据丢失）；Play/分发渠道也要求固定签名。
- **只靠 debug 签名不是统一签名**：Gradle 的 debug key 是每台机器（每个 CI runner）
  首次构建时随机生成的（`~/.android/debug.keystore`），所以 CI 上每次 runner 重建都会换证书。
  想「debug 也统一」，就必须显式给 debug 构建类型也指定同一个 keystore（本仓库已这样做）。
- 代价：release keystore 同时用于 debug 构建，开发机泄露风险更高。如果以后上架 Google Play，
  建议改为 Play App Signing（上传密钥 upload key 可以轮换，应用签名密钥由 Google 保管），
  见第 6 节。

## 1. 生成 keystore（只做一次）

```bash
# 依赖 JDK 17（keytool）
. /home/YUN/development/flutter-env.sh   # 或自己 export JAVA_HOME
./platforms/android/make-keystore.sh
```

输出示例（密码默认随机生成并打印一次）：

```
keystore          : /path/chatvv/app/android/chatvv-release.jks
password          : <随机密码>
alias             : chatvv
cert SHA-256      : 1a2b3c...（64 位 hex）
base64 file       : app/android/chatvv-release.jks.b64
```

- `app/android/chatvv-release.jks`、`app/android/key.properties`、`*.jks.b64`
  全部在 `.gitignore` 里，**不要提交**。
- **备份 keystore + 密码**（离线/密码管理器）。丢了就无法更新已安装的 app。
- 重新生成（`--force`）会让你之前发出去的包无法被覆盖升级，除非改 `applicationId`。
- 可用环境变量覆盖：`CHATVV_KEY_ALIAS`、`CHATVV_KEYSTORE_PASSWORD`、
  `CHATVV_KEYSTORE_PATH`、`CHATVV_KEY_DNAME`、`CHATVV_KEY_VALIDITY_DAYS`。
- 密码建议只用字母、数字、`-_`（不要有前导/尾随空格或反斜杠），避免
  `key.properties` 的转义/裁剪问题；`make-keystore.sh` 生成的随机密码满足这一点。
- PKCS12 keystore 的 key password 必须等于 store password；`make-keystore.sh`
  和 CI 的 `ANDROID_KEY_PASSWORD` 都按这个规则写。

## 2. 本地构建

生成一次之后，`platforms/android/setup-signing.sh` 会优先使用已有的
`app/android/key.properties`；也可以手动写（相对 Gradle 模块目录 `app/android/app/` 解析）：

```properties
# app/android/key.properties（gitignored）
storeFile=../chatvv-release.jks
storePassword=...
keyAlias=chatvv
keyPassword=...
```

然后：

```bash
CHATVV_APK_MODE=debug   ./platforms/android/package-apk.sh
CHATVV_APK_MODE=release ./platforms/android/package-apk.sh
```

`package-apk.sh` 会先调用 `setup-signing.sh`（本地缺失只警告，用 throwaway debug key；
CI 里是 `--required`，缺失直接失败）。

## 3. 把签名传给 GitHub Actions

用 `make-keystore.sh` 打印的命令（或 Settings → Secrets and variables → Actions 手动填）：

```bash
gh secret set ANDROID_KEYSTORE_BASE64 < app/android/chatvv-release.jks.b64
gh secret set ANDROID_KEYSTORE_PASSWORD --body '<password>'
gh secret set ANDROID_KEY_ALIAS          --body 'chatvv'
gh secret set ANDROID_KEY_PASSWORD       --body '<password>'
gh secret set ANDROID_CERT_SHA256        --body '<cert SHA-256 hex>'
```

| Secret | 必填 | 说明 |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | ✅ | keystore 的 base64 单行（`base64 -w0`） |
| `ANDROID_KEYSTORE_PASSWORD` | ✅ | keystore 密码 |
| `ANDROID_KEY_ALIAS` | ✅ | 默认 `chatvv` |
| `ANDROID_KEY_PASSWORD` | ✅ | key 密码（PKCS12 keystore 与 store 密码相同） |
| `ANDROID_CERT_SHA256` | 建议 | 期望的签名证书 SHA-256（hex，可带冒号）；CI 构建后校验，防用错 key |

注意：**fork 的 PR 拿不到 secrets**，Android job 会按设计失败（并提示如何配置）。
如果要在 fork PR 上跑 Android 构建，可以把 `setup-signing.sh` 改成非必需（会产出
debug-key 签名的包，仅用于编译验证，不可分发）。

## 4. CI 流程

```
push / tag
  └─ app-package (android)
       ├─ Configure Android signing (unified key)
       │    setup-signing.sh --required
       │    ANDROID_KEYSTORE_BASE64 → app/android/chatvv-release.jks
       │    ANDROID_*_PASSWORD/ALIAS  → app/android/key.properties
       │    打印证书 SHA-256；与 ANDROID_CERT_SHA256 不一致则失败
       ├─ flutter build apk --debug|--release（Gradle 用统一 key 签 debug+release）
       ├─ verify-apk.sh
       │    zipalign 16 KB + apksigner verify + 证书指纹比对 + native ELF 对齐
       └─ upload-artifact artifacts/*
```

- `ci.yml`：debug APK（`chatvv-app-android-debug.apk`）。
- `release.yml`：release APK + AAB（`chatvv-app-android.apk/.aab`）。
- debug 和 release 都带同一张证书：已装的 debug 包可以直接被 release 包覆盖（反之亦然），
  不会因为签名不同而要求卸载。

## 5. 验证签名

```bash
# APK 证书指纹
$ANDROID_HOME/build-tools/36.0.0/apksigner verify --print-certs \
  artifacts/chatvv-app-android.apk | grep 'SHA-256'

# 和 keystore 里的证书比对
keytool -list -v -keystore app/android/chatvv-release.jks -alias chatvv \
  | grep 'SHA256:'

# 真机覆盖安装（同包名同签名会保留数据）
adb install -r artifacts/chatvv-app-android.apk
```

## 6. 安全与运维

- keystore / `key.properties` / `*.jks.b64` 一律不进 git；CI 里只在 job 临时目录生成，
  不随 artifact 上传（artifact 只有 `artifacts/*`）。
- 密码用 GitHub Secrets，不要写进 workflow 或脚本。
- 只在需要发布时让 `ANDROID_KEYSTORE_BASE64` 进入 release job；日常 PR 可以不配 android job
  （或接受它失败）。
- 将来上架 Google Play：建议启用 Play App Signing，CI 只持有 upload key；应用签名密钥由
  Google 托管，upload key 泄露时可申请轮换。
- 轮换 keystore 的后果：已安装用户无法直接覆盖升级（需要改包名/卸载重装），所以务必先备份。

## 7. 相关文件

| 文件 | 作用 |
|---|---|
| `platforms/android/make-keystore.sh` | 生成统一 keystore，打印 base64 / 指纹 / `gh secret set` 命令 |
| `platforms/android/setup-signing.sh` | 本地复用 key.properties；CI 从 secrets 还原 keystore + key.properties |
| `platforms/android/package-apk.sh` | 打包前自动配置签名，debug/release 共用 |
| `platforms/android/verify-apk.sh` | 校验签名与 `ANDROID_CERT_SHA256` 指纹 |
| `app/android/app/build.gradle.kts` | debug + release `signingConfig` 都指向统一 key |
| `app/android/key.properties.example` | key.properties 模板 |
