# Arch package (template)

`PKGBUILD` 用于把 `chatvvd` 打成 Arch 包。**不是 AUR 现成包**，发布前必须改：

1. `OWNER` → GitHub 用户名 / 仓库地址。
2. `license` → 项目实际许可证（当前仓库还没加 LICENSE）。
3. `sha256sums` → 真实 tarball 哈希（AUR 不允许 `SKIP`）。
4. `pkgver` / `pkgrel` 与 tag 对齐。

本地构建：

```bash
cd packaging/arch
makepkg -si
```

安装后：

- 二进制：`/usr/bin/chatvvd`
- 示例配置：`/usr/share/chatvv/config.example.toml`
- 实际配置：`/etc/chatvv/config.toml`（包内复制了一份，按需改）

运行：

```bash
chatvvd --config /etc/chatvv/config.toml
```

依赖：`sqlite`、`curl`、`openssl`；构建需要 `clang`、`cmake`、`ninja`、`pkgconf`。
systemd 服务不在模板内；如果要开机自启，自行加 unit + 专用用户。
