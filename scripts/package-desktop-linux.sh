#!/usr/bin/env bash
# Compatibility shim: canonical script moved to platforms/linux/package.sh.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/platforms/linux/package.sh" "$@"
