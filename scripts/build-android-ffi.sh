#!/usr/bin/env bash
# Compatibility shim: canonical script moved to platforms/android/build-ffi.sh.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/platforms/android/build-ffi.sh" "$@"
