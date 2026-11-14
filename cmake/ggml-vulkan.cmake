# Vulkan backend selection for the vendored ggml (shared by llama.cpp and
# whisper.cpp: whisper reuses llama.cpp's ggml target, so this switch controls
# both at once).
#
# Values:
#   AUTO (default) - enable Vulkan when the toolchain looks usable, otherwise
#                    fall back to the CPU backend with a warning.
#   ON             - require Vulkan. Configure fails with instructions when the
#                    SDK / shader compiler is missing (used by CI).
#   OFF            - force CPU.
#
# Apple targets currently build with CPU (Metal stays available through ggml's
# own Metal backend when enabled); MoltenVK is not wired up yet.

set(CHATVV_VULKAN "AUTO" CACHE STRING "Build ggml with the Vulkan backend (AUTO/ON/OFF)")
set_property(CACHE CHATVV_VULKAN PROPERTY STRINGS AUTO ON OFF)
string(TOUPPER "${CHATVV_VULKAN}" _chatvv_vulkan_mode)

function(_chatvv_vulkan_require_failure message)
  if(_chatvv_vulkan_mode STREQUAL "ON")
    message(FATAL_ERROR "${message}")
  else()
    message(WARNING "${message} Falling back to the CPU backend; pass -DCHATVV_VULKAN=OFF to silence this.")
  endif()
endfunction()

set(_chatvv_vulkan_enabled FALSE)

if(_chatvv_vulkan_mode STREQUAL "OFF")
  message(STATUS "ggml: Vulkan backend disabled by CHATVV_VULKAN=OFF")
elseif(APPLE)
  if(_chatvv_vulkan_mode STREQUAL "ON")
    message(FATAL_ERROR
      "CHATVV_VULKAN=ON is not supported on Apple targets yet: ggml's Vulkan "
      "backend would need MoltenVK. Build with the CPU/Metal backend instead, "
      "or extend this module with MoltenVK support.")
  endif()
  message(STATUS "ggml: Vulkan backend skipped on Apple (CPU/Metal backend)")
else()
  if(ANDROID)
    # The NDK sysroot provides the target Vulkan headers and libvulkan.so; the
    # shader compiler (glslc) and SPIRV-Headers must come from a host Vulkan
    # SDK, which CI installs and exposes through VULKAN_SDK.
    if(DEFINED ENV{VULKAN_SDK})
      list(APPEND CMAKE_PREFIX_PATH "$ENV{VULKAN_SDK}")
    endif()
    find_program(CHATVV_VULKAN_GLSLC
      NAMES glslc
      HINTS ENV VULKAN_SDK
      PATH_SUFFIXES bin
      NO_CMAKE_FIND_ROOT_PATH)
    if(CHATVV_VULKAN_GLSLC)
      set(_chatvv_vulkan_enabled TRUE)
      if(NOT DEFINED Vulkan_GLSLC_EXECUTABLE)
        set(Vulkan_GLSLC_EXECUTABLE "${CHATVV_VULKAN_GLSLC}")
      endif()
    else()
      _chatvv_vulkan_require_failure(
        "Vulkan backend for Android requires the host shader compiler 'glslc'. "
        "Install the LunarG Vulkan SDK and set VULKAN_SDK.")
    endif()
  else()
    find_package(Vulkan QUIET COMPONENTS glslc)
    if(Vulkan_FOUND)
      set(_chatvv_vulkan_enabled TRUE)
    else()
      _chatvv_vulkan_require_failure(
        "Vulkan backend requested but the Vulkan SDK (headers, loader, glslc) "
        "was not found. Install the LunarG Vulkan SDK and set VULKAN_SDK.")
    endif()
  endif()
endif()

if(_chatvv_vulkan_enabled)
  message(STATUS "ggml: Vulkan backend enabled")
  set(GGML_VULKAN ON CACHE BOOL "" FORCE)
else()
  set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
endif()
