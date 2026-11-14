#!/usr/bin/env bash
# Shared helpers for chatvv platform build/package scripts.
#
# This file is *sourced* by scripts under platforms/<platform>/, it is not meant
# to be executed directly. Platform-agnostic build logic stays in the root
# CMakeLists.txt; only platform adaptation lives here.
#
# shellcheck shell=bash

# Populate CHATVV_VERSION / CHATVV_BUILD_NUMBER / CHATVV_COMMIT_SHA from git.
# Usage: chatvv_versions "$ROOT"
chatvv_versions() {
  local root="$1"
  CHATVV_BUILD_NUMBER="$(git -C "$root" rev-list --count HEAD)"
  CHATVV_COMMIT_SHA="$(git -C "$root" rev-parse --short HEAD)"
  CHATVV_VERSION="0.1.${CHATVV_BUILD_NUMBER}"
}

# Resolve the Vulkan mode for a configure step.
# Usage: chatvv_vulkan_mode AUTO   -> prints AUTO/ON/OFF (CHATVV_VULKAN wins)
chatvv_vulkan_mode() {
  printf '%s' "${CHATVV_VULKAN:-${1:-AUTO}}"
}

# Print the CMake configure argument for CHATVV_VULKAN.
# Usage: chatvv_vulkan_configure_arg AUTO
chatvv_vulkan_configure_arg() {
  printf -- '-DCHATVV_VULKAN=%s' "$(chatvv_vulkan_mode "${1:-AUTO}")"
}

# Find a read-aloud (Rust) build artifact.
# The tts-readaloud CMake integration stages artifacts in
# ${CMAKE_BINARY_DIR}/read_aloud/; older/local cargo builds may live elsewhere.
# Usage: chatvv_find_read_aloud <build-dir> <repo-root> <file-name>
chatvv_find_read_aloud() {
  local build_dir="$1" root="$2" name="$3" hit=""

  if [[ -d "$build_dir/read_aloud" ]]; then
    hit="$(find "$build_dir/read_aloud" -maxdepth 2 -name "$name" -type f 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$hit" ]]; then
    hit="$(find "$build_dir" -maxdepth 6 -name "$name" -type f 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$hit" && -d "$root/third_party/read_aloud/target" ]]; then
    hit="$(find "$root/third_party/read_aloud/target" -name "$name" -type f 2>/dev/null | head -n 1 || true)"
  fi

  if [[ -z "$hit" ]]; then
    {
      echo "read_aloud: '$name' not found. Searched:"
      echo "  - $build_dir/read_aloud/lib/"
      echo "  - $build_dir/**/$name"
      echo "  - $root/third_party/read_aloud/target/**/$name"
      echo "Rebuild the FFI target (cmake/readaloud.cmake stages it into"
      echo "\$CMAKE_BINARY_DIR/read_aloud/lib/) or set CHATVV_SKIP_READ_ALOUD=1 to skip."
    } >&2
    return 1
  fi
  printf '%s\n' "$hit"
}

# Print the first PT_LOAD alignment of an ELF file.
# Usage: chatvv_elf_load_align <elf> <llvm-readelf>
chatvv_elf_load_align() {
  local elf="$1" readelf="$2"
  # Consume the whole readelf output instead of exiting awk early: with
  # `set -o pipefail` an early awk exit makes readelf die with SIGPIPE and the
  # pipeline fails even though the alignment was read (CI saw exit 74 here).
  "$readelf" -l "$elf" 2>/dev/null \
    | awk '/LOAD/ && !align {align=$NF} END {if (align == "") exit 1; print align}'
}

# Verify an ELF is 16 KB page-size compatible (Android 15+/17 requirement).
# Usage: chatvv_require_16k_align <elf> <llvm-readelf> <label>
chatvv_require_16k_align() {
  local align
  align="$(chatvv_elf_load_align "$1" "$2")"
  case "$align" in
    0x4000|0x10000)
      printf '%-32s LOAD align %s\n' "$3" "$align"
      ;;
    *)
      {
        echo "ERROR: $3 has LOAD align '${align:-unknown}', expected 0x4000 or 0x10000 (16 KB page size)."
        echo "For Rust cdylibs add e.g. CARGO_TARGET_<TRIPLE>_RUSTFLAGS=-C link-arg=-Wl,-z,max-page-size=16384"
      } >&2
      return 1
      ;;
  esac
}
