# third_party

Vendored, pinned single-header dependencies. No package manager or network access is
required to build.

| Header | Version | Source | SHA-256 |
|---|---|---|---|
| `nlohmann/json.hpp` | v3.12.0 | https://github.com/nlohmann/json | `aaf127c04cb31c406e5b04a63f1ae89369fccde6d8fa7cdda1ed4f32dfc5de63` |
| `toml++/toml.hpp` | v3.4.0 | https://github.com/marzer/tomlplusplus | `6b5172ad4dd6519aec67b919181fa7a38a2234131e5b2afa232dfe444819783e` |
| `httplib.h` | v0.63.0 | https://github.com/yhirose/cpp-httplib | `9021001a719768893a8a6e4051c56107690e8b8e49b41e5f903534fa19ae9afb` |

Licenses: MIT (nlohmann, httplib), MIT (toml++).

Updating: download the same paths from a newer tag, replace the file, update the hash
here, and rebuild.
