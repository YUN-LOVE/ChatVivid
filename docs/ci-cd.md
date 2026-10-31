# CI / CD 与发布

## 分支与触发

| 分支/事件 | 触发 | 说明 |
|---|---|---|
| push `dev` / `main` / `feature/**` / `fix/**` / `chore/**` | CI | 后端全平台构建 + 测试；app 有 `pubspec.yaml` 时再跑 Flutter |
| PR → `dev` / `main` | CI | 合并前必须绿 |
| tag `v*` | Release | 构建 server 包 + Android APK/AAB，创建 GitHub Release |

- `main`：稳定/发行；只从 `dev` 合入。
- `dev`：集成；feature 从 `dev` 开，PR 回 `dev`。
- 详细规则见 [CONTRIBUTING.md](../CONTRIBUTING.md)。

## CI（`.github/workflows/ci.yml`）

- 后端：
  - Linux x64：`ubuntu-latest`
  - Linux arm64：`ubuntu-24.04-arm`（若套餐不支持，改成 `arm64-cross` + qemu/自托管）
  - macOS arm64：`macos-14`
  - Windows x64：`windows-latest` + vcpkg manifest
  - 每个 job 跑 configure/build/ctest。
- App：
  - 先跑 `detect-app` 检查 `app/pubspec.yaml`；不存在则跳过（当前就是这种情况）。
  - 存在时：Java 17 + Flutter stable + Android SDK/NDK/CMake →
    `pub get` / `analyze` / `test`（有 test 目录才跑）/ `build apk --debug`。
- 并发：同一 ref 的新 push 取消旧 CI。

## Release（`.github/workflows/release.yml`）

触发：在 `main` 上打 tag，例如：

```bash
git switch main
git pull --ff-only
git tag -a v0.1.0 -m "chatvv v0.1.0"
git push origin v0.1.0
```

产物：

- `chatvv-server-linux-x64.tar.gz` + `.sha256`
- `chatvv-server-linux-arm64.tar.gz` + `.sha256`
- `chatvv-server-macos-arm64.tar.gz` + `.sha256`
- `chatvv-server-windows-x64.zip` + `.sha256`
- `chatvv-app-android.apk` / `.aab`（当 `app/pubspec.yaml` 存在）
- `SHA256SUMS`（release job 统一生成）

Release job 的规则：

- 四个后端的 job 都成功才发 Release。
- app job 可以是 `success` 或 `skipped`（例如未 scaffold 的分支）。
- tag 含 `-`（如 `v0.1.0-rc.1`）自动标为 prerelease。
- 自动生成 release notes。

## App 构建/签名

- app 已在 Pixel 8 Pro 真机验证；CI 会跑 `flutter analyze/test` + debug APK；Live2D 尚未合入。
- app 已 scaffold；release 默认用 Flutter 的 debug signing（只适合内测）。
- 正式 Android 签名后续加 secrets：
  - `ANDROID_KEYSTORE_BASE64`
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`
- iOS 需要 macOS runner + Apple 证书/描述文件；未配置前只出 Android。
- `flutter_live2d` 依赖 NDK + CMake；CI 已经装 `ndk;27.2.12479018` / `cmake;3.22.1`，
  版本要随 Flutter/插件升级调整。

## Arch 包

`packaging/arch/PKGBUILD` 是模板：

1. 把 `OWNER` 换成 GitHub 用户名。
2. 填 `sha256sums`（AUR 不允许 `SKIP`）。
3. `makepkg -si`。

它构建 `chatvvd` 到 `/usr/bin`、示例配置到 `/usr/share/chatvv`，并复制到 `/etc/chatvv/config.toml`。
详见 [packaging/arch/README.md](../packaging/arch/README.md)。

## 保护建议

在 GitHub 仓库设置里：

- `main` / `dev`：Require a pull request；Require status checks；
  Dismiss stale approvals；禁止 force push/删除。
- 必选 checks：四个 backend job；再加 `app / analyze & build`。
- Tag `v*` 仅 maintainer 可创建。
- Release 使用 `GITHUB_TOKEN`（`contents: write`），不需要 PAT。

## 本地预检

```bash
# 后端
cmake --preset dev && cmake --build --preset dev && ctest --preset dev

# app（scaffold 后）
cd app && flutter analyze && flutter test
```

安装依赖见 [install-arch.md](install-arch.md)。
