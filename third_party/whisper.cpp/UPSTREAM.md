# whisper.cpp (vendored)

Speech-to-text (Whisper) engine used by `chatvv_core`'s ASR layer
(`src/asr/`). This is a **trimmed, pinned snapshot** of upstream
[ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp); it is built as
part of the ChatVivid CMake tree by `cmake/whisper.cmake` and is never built
standalone here.

## Pinned version

| | |
|---|---|
| Upstream repository | https://github.com/ggml-org/whisper.cpp |
| Pinned commit | `cfcacb9b35fdbed31f521cab39bc0431509e2761` (upstream `master`) |
| Commit date | 2026-11-05T22:38:49+08:00 |
| `WHISPER_VERSION` | 1.9.5 (-dev; the last release tag `v1.9.5` predates this) |
| Bundled upstream ggml | **0.28.0** (`ggml/CMakeLists.txt` in the pinned tree) |
| Upstream tarball | `https://codeload.github.com/ggml-org/whisper.cpp/tar.gz/cfcacb9b35fdbed31f521cab39bc0431509e2761` |
| Tarball SHA-256 | `d727f0fdbd040ea9a8b48dc44daf650c5ef4b2b7bc831eff0e846227a1876410` |
| License | MIT, Copyright (c) 2023-2026 The ggml authors (`LICENSE`) |

## Why this commit

ChatVivid vendors `third_party/llama.cpp` whose ggml is **0.28.0**. Whisper and
llama must share exactly one ggml build (duplicate `ggml` targets/Ggml symbols
would break the link and double-compile the backends). whisper.cpp decides at
configure time: if the parent project already provides a `ggml` target it uses
it as-is (`if (NOT TARGET ggml)` in its top-level `CMakeLists.txt`), otherwise it
adds its own copy.

The pinned commit is the last upstream `master` commit whose in-tree ggml is
0.28.0; the next commit (`826098654f6b`, "ggml : bump version to 0.29.0",
2026-11-05) starts upstream's ggml 0.29 cycle. The latest release tag `v1.9.5`
was cut while upstream still bundled ggml 0.26.0, so it is **not** the version
match (and was rejected to avoid building whisper against a ggml three minor
versions newer than the one it was written for).

Verified locally (see `docs/asr.md`): this whisper snapshot compiles and links
against ChatVivid's vendored `ggml` 0.28.0 from `third_party/llama.cpp` with the
CPU backend (`whisper`, `llama`, `ggml`, `ggml-base`, `ggml-cpu` targets), using
`WHISPER_USE_SYSTEM_GGML=ON`.

## What is kept / stripped

Kept (everything needed by the CMake build):

- `CMakeLists.txt`
- `include/` (`whisper.h`, `parakeet.h`)
- `src/` (`whisper.cpp`, `whisper-arch.h`, `parakeet.cpp`, `parakeet-arch.h`,
  and the optional CoreML/OpenVINO/VitisAI/ANEForge backend sources used only
  when their CMake options are enabled)
- `cmake/` (package config templates, `build-info.cmake`, toolchains)
- `LICENSE`, `AUTHORS`, `README.md` (upstream documentation)

Stripped (not needed to build the library, and would bloat the repository):

- `ggml/` — **do not vendor a second ggml**. whisper reuses the `ggml` target
  from `third_party/llama.cpp` (see above). Do not restore this directory.
- `examples/`, `tests/`, `models/`, `samples/`, `bindings/`, `grammars/`,
  `scripts/`, `ci/`, `media/`, `.github/`, `.devops/`, `.dockerignore`,
  `CMakePresets.json`, `Makefile`, `build-xcframework.sh`, `README_sycl.md`.

Because `ggml/` is stripped, this copy can only be used as a subdirectory of a
parent project that already defines `ggml` (`cmake/whisper.cmake` enforces
that). Upstream's standalone build (including the `bindings/`-based config file)
does not work from this directory.

## Updating

1. Pick an upstream commit whose `ggml/CMakeLists.txt` `GGML_VERSION_*` matches
   the `third_party/llama.cpp` ggml version (check with
   `git log --oneline -- ggml/CMakeLists.txt` upstream).
2. Download the tarball:
   `curl -L https://codeload.github.com/ggml-org/whisper.cpp/tar.gz/<commit>`
3. Copy `CMakeLists.txt`, `LICENSE`, `AUTHORS`, `README.md`, `include/`, `src/`,
   `cmake/` here; verify `ggml/` was not copied.
4. Update this file and `docs/asr.md`, then rebuild and re-run the ASR smoke
   check in `docs/asr.md`.
