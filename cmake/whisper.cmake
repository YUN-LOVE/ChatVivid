# Whisper.cpp ASR integration for the ChatVivid native core.
#
# Usage (root CMakeLists.txt), AFTER third_party/llama.cpp has been added:
#
#   include(cmake/whisper.cmake)   # auto-invokes chatvv_add_whisper()
#
# or explicitly, with the same effect:
#
#   include(cmake/whisper.cmake)
#   chatvv_add_whisper()
#
# This defines the upstream-named static target `whisper` (plus its upstream
# dependency targets). Link it into the core with:
#
#   target_link_libraries(chatvv_core PUBLIC whisper)
#
# Matching the repo's fragment convention (see cmake/readaloud.cmake), including
# this file automatically runs chatvv_add_whisper() when the parent already
# provides the `ggml` target (i.e. after llama.cpp). The explicit call is
# idempotent and supported for callers that need control over ordering.
#
# Design constraints (see docs/asr.md for the full rationale):
#
#   * Single ggml. whisper.cpp's own CMakeLists.txt skips its in-tree
#     `add_subdirectory(ggml)` when the parent project already defines the
#     `ggml` target. We require that (llama.cpp provides ggml/ggml-base/
#     ggml-cpu and, via cmake/ggml-vulkan.cmake, the Vulkan backend), so PRIVATE
#     ggml sources are never compiled twice and there is exactly one set of
#     ggml symbols. Never add the vendored `third_party/whisper.cpp/ggml`
#     directory (it is not vendored on purpose).
#
#   * Backends are owned by the llama.cpp ggml build. This fragment deliberately
#     does not touch GGML_* options (GGML_VULKAN, GGML_OPENMP, ...); whisper only
#     links the existing `ggml` target. That keeps CPU/Vulkan behaviour identical
#     for the LLM and ASR paths, and it means macOS does not need Vulkan.
#
#   * Requires the parent `ggml` target (Vulkan/CPU choice included). It is
#     meaningless before llama.cpp is added, hence the hard check below.
#
#   * WHISPER_USE_SYSTEM_GGML is set for documentation/future upstream
#     compatibility: in the pinned whisper.cpp it is only consulted when
#     `TARGET ggml` does not exist, so with the parent-provided target the
#     branch is already skipped.
#
#   * EXCLUDE_FROM_ALL keeps the vendored third-party targets out of the default
#     `all` target AND — as CMake does for excluded subdirectories — out of the
#     install rules. Only `whisper` itself is compiled, because chatvv_core links
#     it. The `parakeet` library upstream adds alongside whisper (an unrelated
#     speech model) is therefore neither built nor installed.
#
#   * Build settings shared with llama/ggml: no LTO (the repo release preset
#     enables IPO globally, which is not worth the CI time for this vendored
#     code) and C++17 instead of the repo-wide C++23 (upstream requires >= 11).

function(chatvv_add_whisper)
  if(TARGET whisper)
    return()
  endif()

  if(NOT TARGET ggml)
    message(FATAL_ERROR
      "chatvv_add_whisper() requires the parent ggml target from "
      "third_party/llama.cpp. Include cmake/whisper.cmake only after "
      "add_subdirectory(third_party/llama.cpp).")
  endif()

  # CMAKE_CURRENT_FUNCTION_LIST_DIR is this file's directory (cmake/), i.e. the
  # definition site — CMAKE_CURRENT_LIST_DIR would point at the caller's root
  # CMakeLists.txt while the function body runs.
  set(_whisper_src "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../third_party/whisper.cpp")
  if(NOT EXISTS "${_whisper_src}/CMakeLists.txt")
    message(FATAL_ERROR
      "Vendored whisper.cpp not found at '${_whisper_src}'. See "
      "third_party/whisper.cpp/UPSTREAM.md.")
  endif()

  # Build only the library: no examples, no tests, no server, no standalone
  # helpers. Values are CACHE FORCE for the same reason the llama.cpp options
  # are set that way in the root CMakeLists.txt: the third-party option() calls
  # must see them before they run.
  set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
  set(WHISPER_USE_SYSTEM_GGML ON CACHE BOOL "" FORCE)
  set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
  # Third-party code: keep the repo's warning policy for our own targets only.
  set(WHISPER_ALL_WARNINGS OFF CACHE BOOL "" FORCE)
  set(WHISPER_FATAL_WARNINGS OFF CACHE BOOL "" FORCE)

  message(STATUS "chatvv: whisper.cpp (vendored, reusing parent ggml target)")
  add_subdirectory(
    "${_whisper_src}"
    "${CMAKE_BINARY_DIR}/third_party/whisper.cpp"
    EXCLUDE_FROM_ALL)

  if(NOT TARGET whisper)
    message(FATAL_ERROR
      "whisper.cpp was added but did not define the 'whisper' target")
  endif()

  set_target_properties(whisper PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    INTERPROCEDURAL_OPTIMIZATION OFF
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF)

  # The public include dir (third_party/whisper.cpp/include) and the ggml usage
  # requirements propagate through the `whisper` link interface, so consumers
  # (chatvv_core/chatvv_ffi) only need `target_link_libraries(... whisper)`.
endfunction()

# Fragment convention: including this file from the root CMakeLists.txt (after
# llama.cpp) configures whisper automatically. Only does something when the
# parent ggml target exists; otherwise a caller can include now and call
# chatvv_add_whisper() later (after llama.cpp) explicitly.
if(TARGET ggml AND NOT TARGET whisper)
  chatvv_add_whisper()
elseif(NOT TARGET ggml)
  message(STATUS "chatvv: cmake/whisper.cmake included before the ggml target; "
                 "call chatvv_add_whisper() after add_subdirectory(third_party/llama.cpp)")
endif()
