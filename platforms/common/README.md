# platforms/common/

平台无关的共享工具：

```
common/
├── build-lib.sh          # 平台构建脚本 source 的共享函数（版本号、Vulkan 参数、
│                         #   read-aloud 产物查找、16 KB ELF 对齐校验）
└── ci/
    ├── lib.py            # 平台注册表 + 路径分类 + 动态 app matrix 生成（CI 与本地共用）
    ├── detect-changes.py # push/PR 改动 → 触发的平台/矩阵
    ├── parse-tag.py      # release tag / workflow_dispatch → 平台矩阵
    └── lint-workflows.py # workflow YAML + shell 脚本静态检查（lint job）
```

## 为什么是 Python + shell 混合

- 构建/打包脚本是 shell：直接调用本机工具链，方便本地复现。
- CI 分类逻辑（`ci/*.py`）用 Python：JSON 矩阵序列化、GitHub Actions
  `needs` 输出都是字符串，Python 的 `json` 标准库让输出可验证、可本地跑，
  比在 YAML 里写复杂 `git diff` shell 更不容易出错。
- `ci/*.py` 只用标准库，本地无需装包即可模拟 CI。

## 本地模拟 CI

```bash
# 模拟某个手动 workflow_dispatch 平台选择
DISPATCH_PLATFORMS=android,linux python3 platforms/common/ci/detect-changes.py

# 模拟一次 tag 解析（会打印平台矩阵）
python3 platforms/common/ci/parse-tag.py v0.2.0
python3 platforms/common/ci/parse-tag.py v0.2.0-android-linux
python3 platforms/common/ci/parse-tag.py v0.2.0-ios   # 未启用时 fail 并给提示

# workflow/脚本静态检查（需要 PyYAML）
python3 -m pip install --user pyyaml
python3 platforms/common/ci/lint-workflows.py
```

设置 `GITHUB_OUTPUT=<file>` 时脚本写入 GitHub Actions 输出文件，不设置则打印
`name=value`，便于本地 diff。

## 路径分类规则（摘要）

| 改动路径 | 结果 |
|---|---|
| `platforms/<p>/**` | 只构建 `<p>` |
| `platforms/common/**`、`src/**`、`app/**`、`cmake/**`、`include/**`、`config/**`、`tests/**`、`third_party/**`、`scripts/**`、根 `CMakeLists.txt`/`CMakePresets.json`/`vcpkg.json`、`.github/workflows/**` | 全部启用平台 |
| `docs/**`、`reference/**`、`archive/**`、`packaging/**`、`*.md` 等 | 只跑 lint（`light_only=true`） |
| 未知路径 | 保守当作共享路径（宁可多构建，不漏构建） |

tag 规则与 Vulkan/Rust 依赖细节见 [docs/ci-cd.md](../../docs/ci-cd.md)。
