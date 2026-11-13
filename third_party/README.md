# third_party

Vendored, pinned third-party code. The single-header dependencies need no package
manager; the larger native libraries (llama.cpp, whisper.cpp, read_aloud, the Live2D
Flutter plugin) are pinned snapshots too — see each directory's own notes. Rust
(`cargo`) is required to build `read_aloud`; network access is only needed the first
time cargo fetches its registry dependencies (CI caches them).

| Header | Version | Source | SHA-256 |
|---|---|---|---|
| `nlohmann/json.hpp` | v3.12.0 | https://github.com/nlohmann/json | `aaf127c04cb31c406e5b04a63f1ae89369fccde6d8fa7cdda1ed4f32dfc5de63` |
| `toml++/toml.hpp` | v3.4.0 | https://github.com/marzer/tomlplusplus | `6b5172ad4dd6519aec67b919181fa7a38a2234131e5b2afa232dfe444819783e` |
| `httplib.h` | v0.63.0 | https://github.com/yhirose/cpp-httplib | `9021001a719768893a8a6e4051c56107690e8b8e49b41e5f903534fa19ae9afb` |

Licenses: MIT (nlohmann, httplib), MIT (toml++).

## Native / multi-file dependencies

| Directory | Upstream | Version | License | Notes |
|---|---|---|---|---|
| `llama.cpp/` | https://github.com/ggml-org/llama.cpp | vendored snapshot (ggml 0.28.0) | MIT | local RAG embedding + ASR ggml backend |
| `whisper.cpp/` | https://github.com/ggml-org/whisper.cpp | commit `cfcacb9b35fdbed31f521cab39bc0431509e2761` | MIT | ASR; reuses llama.cpp's ggml (trimmed tree, no ggml) |
| `read_aloud/` | https://github.com/naskopw/read_aloud | v0.3.3 | GPL-3.0 | Rust TTS backend with C ABI; built with cargo |
| `live2d_flutter/` | https://github.com/hunmer/flutter_live2d | 1.0.3 | BSD-3-Clause + Live2D Cubism Core (proprietary) | vendored Flutter plugin with local packaging fixes; see `PATCHES.md` |

Provenance, pinned hashes and update procedures are documented next to each
directory (`whisper.cpp/UPSTREAM.md`, `read_aloud/VENDORED.chatvv.md`,
`live2d_flutter/PATCHES.md`) and in `docs/asr.md` / `docs/read-aloud.md`.

Updating: download the same paths from a newer tag, replace the file, update the hash
here, and rebuild.
