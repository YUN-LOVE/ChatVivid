# platforms/linux/

Linux 桌面适配：Flutter Linux bundle + `libchatvv_ffi.so` 打包。

## 文件

| 文件 | 用途 |
|---|---|
| `package.sh` | 编译 `chatvv_ffi`（含 llama.cpp/whisper.cpp ggml + read-aloud 静态链接）→ `flutter build linux --release` → 组装 bundle → `artifacts/chatvv-linux-x64.tar.gz` |

## 本地构建

```bash
# 依赖（Debian/Ubuntu）
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  libsqlite3-dev libcurl4-openssl-dev libssl-dev \
  libvulkan-dev glslc spirv-headers        # Vulkan 可选，AUTO 时缺 SDK 回退 CPU
# Rust（read-aloud 静态链接进 libchatvv_ffi）
curl https://sh.rustup.rs -sSf | sh

./platforms/linux/package.sh                 # 旧入口 ./scripts/package-desktop-linux.sh 等价
```

## Vulkan

- CI（x86_64 / arm64）传 `CHATVV_VULKAN=ON`，用 `libvulkan-dev` + `glslc` + `spirv-headers`
  （FindVulkan 的 glslc 组件由 shaderc 的 glslc 提供）。
- 打包产物**不内置** Vulkan loader：目标机需要 GPU 驱动自带的 `libvulkan.so.1`。
  没有 Vulkan 的机器可用同一个 bundle，但 ggml Vulkan 后端会初始化失败并回退 CPU
  （若需要完全无 Vulkan 的包，用 `CHATVV_VULKAN=OFF` 重新打包）。
- 本地默认 `AUTO`：有 SDK 就启用，没有就 CPU + warning。

## read-aloud

- 桌面默认 **static** 链接进 `libchatvv_ffi.so`，不需要额外分发 `.so`。
- 若某天改为 shared（`-DCHATVV_READ_ALOUD_LINKAGE=shared`），打包脚本需要把
  `libread_aloud.so` 一并复制进 `bundle/lib/`；届时同步更新本 README 与 CI。

## CI 引用

ci.yml / release.yml 的 `app-package` 矩阵 `linux` 条目 → `./platforms/linux/package.sh`。
产物名 `chatvv-app-linux`。

## 已知限制

- 本机 Arch ARM aarch64 chroot 上 `flutter build linux` 会被 `rive_native` 的 x86_64
  预编译静态库卡住；桌面包请在 x86_64 主机/CI 构建，见
  [docs/install-arch-aarch64-chroot.md](../../docs/install-arch-aarch64-chroot.md)。
