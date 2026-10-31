# Contributing / Git 工作流

## 分支模型

| 分支 | 用途 | 规则 |
|---|---|---|
| `main` | 稳定/可发布 | 只接受从 `dev` 合入的 release PR；禁止直接 push；每个 release 打 tag |
| `dev` | 集成分支 | feature/fix 合入这里；禁止直接 push；CI 必须绿 |
| `feature/<topic>` | 新功能 | **必须从 `dev` 开**；完成后 PR 到 `dev` |
| `fix/<topic>` | 修 bug | 从 `dev` 开；PR 到 `dev` |
| `hotfix/<topic>` | 线上紧急修复 | 从 `main` 开；PR 到 `main`，再 back-merge 到 `dev` |

- **不要**从 `main` 开 feature（除非 hotfix）。
- **不要**在 `main`/`dev` 上直接提交。
- 分支名用 kebab-case：`feature/live2d-stage`、`fix/sse-reconnect`。
- 开 PR 前先 rebase 到最新 `dev`，解决冲突后再请求 review。

## 提交信息

使用 Conventional Commits：

```
feat(chat): add streaming stop button
fix(api): handle empty SSE frame
chore(ci): cache flutter pub
docs(arch): add install guide
refactor(core): split chatvv_core target
test(store): cover response replay
```

- 标题用祈使句，尽量 ≤ 72 字符。
- 一个提交只做一件事；格式化/重命名单独提交。
- 不在提交里放密钥、token、模型授权文件（除非许可证明确允许）。

## PR 流程

1. 从最新 `dev` 开分支。
2. 开发 + 本地验证；UI 改动附截图/GIF。
3. Push 分支；开 PR 到 `dev`。
4. CI 必须通过（backend + app 若已 scaffold）。
5. 至少 1 个 review；squash merge 到 `dev`。
6. 删除 feature 分支。

## 发布流程

1. `dev` 通过完整 CI。
2. 开 `dev` → `main` 的 release PR；只做版本号/CHANGELOG（后续加）。
3. Merge（`--no-ff`，保留 release 记录）。
4. 在 `main` 打 tag：`v0.1.0`（预发布用 `v0.1.0-rc.1`）。
5. `.github/workflows/release.yml` 自动构建并创建 GitHub Release。
6. 发布后把 `main` back-merge 到 `dev`（保持同步）。

## 当前分支

- `main`：稳定/发行。
- `dev`：集成。
- `feature/ci-cd-arch`：本次 CI/CD + Arch 文档（从 `dev` 开）。

## 保护建议（GitHub 设置）

- `main` / `dev`：Require PR、Require status checks、Dismiss stale approvals、
  Require linear history（或允许 merge commit）、禁止 force push/删除。
- 必选 checks：`backend / linux x64`、`backend / linux arm64`、`backend / macos arm64`、
  `backend / windows x64`；app scaffold 后加 `app / analyze & build`。
- Tag `v*` 只允许 maintainer 创建。

## 许可

- 大肥鱼/Live2D 模型：CC BY-NC-SA 4.0，非商业；提交/分发前读
  `reference/avatar-tech/LIVE2D.md` 与 `reference/deepseek-mascot/ATTRIBUTION.md`。
- 不要在 PR 里加入未授权的 3D/VRM 模型、RikkaHub 代码或截图。
