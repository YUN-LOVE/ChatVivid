# chatvv read-aloud TTS backend (Rust C ABI, vendored)
# =============================================================================
#
# The TTS backend is the vendored `read_aloud` crate in third_party/read_aloud
# (pinned v0.3.3, GPL-3.0; see third_party/read_aloud/VENDORED.chatvv.md). It is
# built with cargo and exposed to the C++ core as the imported target:
#
#   chatvv::read_aloud
#
# Usage (root CMakeLists.txt):
#
#   include(cmake/readaloud.cmake)        # must be after project()
#   add_library(chatvv_core STATIC ... src/tts/synthesize.cpp)
#   if(TARGET chatvv::read_aloud)
#     target_link_libraries(chatvv_core PUBLIC chatvv::read_aloud)
#   endif()
#
# Including this file invokes chatvv_add_read_aloud() automatically (idempotent);
# calling chatvv_add_read_aloud() explicitly is also supported.
#
# An exported target exists only when the backend could be configured. When
# CHATVV_ENABLE_READ_ALOUD=OFF (or no cargo is available and the caller opted
# out) src/tts/synthesize.cpp compiles a stub that returns a clear error, so the
# rest of the project keeps building. The real wrapper is compiled with
# -DCHATVV_HAVE_READ_ALOUD=1, which this target adds as an INTERFACE compile
# definition.
#
# -----------------------------------------------------------------------------
# Cached options / variables
# -----------------------------------------------------------------------------
#   CHATVV_ENABLE_READ_ALOUD       ON        build the real Rust TTS backend
#   CHATVV_READ_ALOUD_LINKAGE      auto      auto | static | shared
#                                            auto: shared on Android and
#                                            static everywhere else (iOS must be
#                                            static; Linux/Windows/macOS static
#                                            means only libchatvv_ffi has to be
#                                            shipped).
#   READ_ALOUD_TARGET              ""        override the cargo target triple,
#                                            e.g. aarch64-linux-android. When
#                                            empty the triple is derived from
#                                            the CMake toolchain (host native
#                                            builds pass no --target).
#   CHATVV_READ_ALOUD_PROFILE     auto      auto | release | debug
#                                            auto: debug for CMAKE_BUILD_TYPE =
#                                            Debug, release otherwise. Cargo's
#                                            dev profile is named "debug".
#   CHATVV_READ_ALOUD_CARGO        ""        explicit cargo executable; found on
#                                            PATH / in $CARGO_HOME/bin otherwise.
#   CHATVV_READ_ALOUD_OFFLINE      OFF       pass --offline to cargo.
#   CHATVV_READ_ALOUD_OPENSSL_DIR  ""        OpenSSL prefix for cross builds
#                                            (native-tls uses OpenSSL on
#                                            Linux/Android). Auto-detected from
#                                            $OPENSSL_DIR and the vcpkg
#                                            install root when possible.
#   CHATVV_READ_ALOUD_STAGING_DIR  ${CMAKE_BINARY_DIR}/read_aloud
#                                            stable artifact staging directory
#                                            (see the layout below).
#   CHATVV_READ_ALOUD_CARGO_TARGET_DIR
#                                  ${CMAKE_BINARY_DIR}/read_aloud/cargo
#                                            CARGO_TARGET_DIR for the build.
#
# -----------------------------------------------------------------------------
# Artifact staging (stable paths for CI/packaging)
# -----------------------------------------------------------------------------
#   ${CHATVV_READ_ALOUD_STAGING_DIR}/include/read_aloud.h   cbindgen C header
#   ${CHATVV_READ_ALOUD_STAGING_DIR}/lib/libread_aloud.a    staticlib (all
#                                                           non-MSVC platforms)
#   ${CHATVV_READ_ALOUD_STAGING_DIR}/lib/libread_aloud.so   Linux/Android
#   ${CHATVV_READ_ALOUD_STAGING_DIR}/lib/libread_aloud.dylib macOS (if built)
#   ${CHATVV_READ_ALOUD_STAGING_DIR}/lib/read_aloud.lib     MSVC staticlib
#   ${CHATVV_READ_ALOUD_STAGING_DIR}/lib/read_aloud.dll     MSVC cdylib
#   ${CHATVV_READ_ALOUD_STAGING_DIR}/lib/read_aloud.dll.lib MSVC import lib
#
# Cargo always produces both the cdylib and the staticlib (the crate-type in
# third_party/read_aloud/Cargo.toml lists cdylib, staticlib and rlib), so a
# single build stages every artifact; only the one selected by
# CHATVV_READ_ALOUD_LINKAGE is linked into chatvv.
#
# Android packaging: when CHATVV_READ_ALOUD_LINKAGE=shared, copy
#   ${CHATVV_READ_ALOUD_STAGING_DIR}/lib/libread_aloud.so
# next to libchatvv_ffi.so (jniLibs/<abi>/). Android builds add the 16 KB page
# size linker arguments required by Android 15+ devices.
#
# -----------------------------------------------------------------------------
# Cross-compilation environment
# -----------------------------------------------------------------------------
# The fragment sets, for the target triple:
#   CARGO_TARGET_<TRIPLE>_LINKER   the CMake C compiler (NDK clang for Android)
#   CC_/CXX_/AR_/RANLIB_<triple>   the CMake toolchain binaries (for openssl-sys)
#   CARGO_TARGET_<TRIPLE>_RUSTFLAGS
#                                  -C relocation-model=pic on ELF targets (the
#                                  Rust staticlib is linked into a shared
#                                  library), plus Android SONAME/16 KB page
#                                  flags, plus macOS install_name for shared.
#   SDKROOT / *_DEPLOYMENT_TARGET  on Apple targets
#   OPENSSL_DIR / OPENSSL_STATIC / OPENSSL_NO_VENDOR
#                                  when an OpenSSL prefix was detected
# Requirements: `rustup target add <triple>` for every cross triple (verified at
# configure time when rustup is available), and a target OpenSSL for
# Linux/Android cross builds (auto-detected from the vcpkg install root, or set
# CHATVV_READ_ALOUD_OPENSSL_DIR). Windows and Apple platforms use the platform
# TLS stack and need no OpenSSL.
# =============================================================================

include_guard(GLOBAL)

if(NOT DEFINED PROJECT_NAME)
  message(FATAL_ERROR
    "cmake/readaloud.cmake must be included after project(): it relies on the "
    "selected platform, compiler and build directories.")
endif()

set(CHATVV_READ_ALOUD_SOURCE_DIR
    "${CMAKE_CURRENT_LIST_DIR}/../third_party/read_aloud"
    CACHE PATH "Vendored read_aloud crate directory")
option(CHATVV_ENABLE_READ_ALOUD
       "Build the vendored read-aloud Rust TTS backend" ON)
set(CHATVV_READ_ALOUD_LINKAGE "auto" CACHE STRING
    "How chatvv links read_aloud: auto, static or shared")
set_property(CACHE CHATVV_READ_ALOUD_LINKAGE PROPERTY STRINGS auto static shared)
set(READ_ALOUD_TARGET "" CACHE STRING
    "Cargo target triple override (e.g. aarch64-linux-android)")
set(CHATVV_READ_ALOUD_PROFILE "auto" CACHE STRING
    "Cargo profile for read_aloud: auto, release or debug")
set_property(CACHE CHATVV_READ_ALOUD_PROFILE PROPERTY STRINGS auto release debug)
set(CHATVV_READ_ALOUD_CARGO "" CACHE FILEPATH
    "Explicit cargo executable (default: found on PATH)")
option(CHATVV_READ_ALOUD_OFFLINE
       "Pass --offline to cargo (requires a populated cargo registry cache)" OFF)
set(CHATVV_READ_ALOUD_OPENSSL_DIR "" CACHE PATH
    "OpenSSL prefix for Linux/Android builds (include/openssl + lib/libssl*)")
set(CHATVV_READ_ALOUD_STAGING_DIR "${CMAKE_BINARY_DIR}/read_aloud" CACHE PATH
    "Stable directory where read_aloud headers and libraries are staged")
set(CHATVV_READ_ALOUD_CARGO_TARGET_DIR
    "${CMAKE_BINARY_DIR}/read_aloud/cargo" CACHE PATH
    "CARGO_TARGET_DIR used to build read_aloud")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Locate cargo/rustup/rustc. Prefers an explicit override, then PATH, then the
# usual rustup locations.
function(_chatvv_read_aloud_find_tools out_cargo out_rustc out_rustup)
  set(_hints
      "$ENV{CARGO_HOME}/bin"
      "$ENV{HOME}/.cargo/bin"
      "$ENV{USERPROFILE}/.cargo/bin")
  if(CHATVV_READ_ALOUD_CARGO)
    if(NOT EXISTS "${CHATVV_READ_ALOUD_CARGO}")
      message(FATAL_ERROR
        "read_aloud: CHATVV_READ_ALOUD_CARGO='${CHATVV_READ_ALOUD_CARGO}' does "
        "not exist. Point it at the cargo executable, or configure with "
        "-DCHATVV_ENABLE_READ_ALOUD=OFF to build the TTS stub.")
    endif()
    set(_cargo "${CHATVV_READ_ALOUD_CARGO}")
  else()
    find_program(_cargo_found NAMES cargo cargo.exe HINTS ${_hints})
    if(NOT _cargo_found OR _cargo_found MATCHES "-NOTFOUND$")
      set(_cargo "")
    else()
      set(_cargo "${_cargo_found}")
    endif()
  endif()
  set(_rustc "")
  set(_rustup "")
  if(_cargo)
    get_filename_component(_cargo_dir "${_cargo}" DIRECTORY)
    find_program(_rustc_found NAMES rustc rustc.exe HINTS "${_cargo_dir}" ${_hints})
    set(_rustc "${_rustc_found}")
    find_program(_rustup_found NAMES rustup rustup.exe HINTS "${_cargo_dir}" ${_hints})
    set(_rustup "${_rustup_found}")
  endif()
  set(${out_cargo} "${_cargo}" PARENT_SCOPE)
  set(${out_rustc} "${_rustc}" PARENT_SCOPE)
  set(${out_rustup} "${_rustup}" PARENT_SCOPE)
endfunction()

# Host/requested architecture comparison, used to decide whether an Apple build
# with CMAKE_OSX_ARCHITECTURES actually needs cargo --target.
function(_chatvv_read_aloud_normalize_arch out_var value)
  string(TOLOWER "${value}" _value)
  if(_value MATCHES "^(arm64|aarch64)$")
    set(${out_var} "arm64" PARENT_SCOPE)
  elseif(_value MATCHES "^(x86_64|amd64|x64)$")
    set(${out_var} "x86_64" PARENT_SCOPE)
  elseif(_value MATCHES "^(x86|i.86|i386)$")
    set(${out_var} "x86" PARENT_SCOPE)
  elseif(_value MATCHES "^(arm|armv7|armhf)$")
    set(${out_var} "arm" PARENT_SCOPE)
  else()
    set(${out_var} "${_value}" PARENT_SCOPE)
  endif()
endfunction()

# Resolve the cargo target triple for cross builds.
#   out_triple: triple to pass to cargo, or "" for a native build (no --target)
#   out_cross:  TRUE when cargo needs --target
function(_chatvv_read_aloud_resolve_target out_triple out_cross)
  set(_triple "")
  set(_cross FALSE)

  if(READ_ALOUD_TARGET)
    set(_triple "${READ_ALOUD_TARGET}")
    # If the override equals the rustc host triple, build natively: the cbindgen
    # header and library then live directly in the profile directory.
    _chatvv_read_aloud_find_tools(_cargo _rustc _rustup)
    set(_host "")
    if(_rustc)
      execute_process(COMMAND "${_rustc}" -vV
        OUTPUT_VARIABLE _rv OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET RESULT_VARIABLE _rr)
      if(_rr EQUAL 0 AND _rv MATCHES "host: ([A-Za-z0-9_.-]+)")
        set(_host "${CMAKE_MATCH_1}")
      endif()
    endif()
    if(_host AND _triple STREQUAL _host)
      set(_cross FALSE)
    else()
      set(_cross TRUE)
    endif()
  elseif(ANDROID)
    if(ANDROID_ABI STREQUAL "arm64-v8a")
      set(_triple "aarch64-linux-android")
    elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
      set(_triple "armv7-linux-androideabi")
    elseif(ANDROID_ABI STREQUAL "x86_64")
      set(_triple "x86_64-linux-android")
    elseif(ANDROID_ABI STREQUAL "x86")
      set(_triple "i686-linux-android")
    else()
      message(FATAL_ERROR
        "read_aloud: unsupported ANDROID_ABI '${ANDROID_ABI}'. Supported: "
        "arm64-v8a, armeabi-v7a, x86_64, x86 (override with -DREAD_ALOUD_TARGET).")
    endif()
    set(_cross TRUE)
  elseif(APPLE)
    set(_arches "${CMAKE_OSX_ARCHITECTURES}")
    if(NOT _arches)
      if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
        set(_arches "arm64")
      else()
        _chatvv_read_aloud_normalize_arch(_host_arch "${CMAKE_HOST_SYSTEM_PROCESSOR}")
        if(_host_arch STREQUAL "arm64")
          set(_arches "arm64")
        else()
          set(_arches "x86_64")
        endif()
      endif()
    endif()
    if(_arches MATCHES ";")
      message(FATAL_ERROR
        "read_aloud: universal/universal2 Apple builds (CMAKE_OSX_ARCHITECTURES="
        "'${_arches}') are not supported; configure once per architecture "
        "(-DCMAKE_OSX_ARCHITECTURES=arm64 or x86_64).")
    endif()
    _chatvv_read_aloud_normalize_arch(_requested_arch "${_arches}")
    _chatvv_read_aloud_normalize_arch(_host_arch "${CMAKE_HOST_SYSTEM_PROCESSOR}")

    if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
      if(CMAKE_OSX_SYSROOT MATCHES "[Ii]phone[Ss]imulator")
        if(_requested_arch STREQUAL "x86_64")
          set(_triple "x86_64-apple-ios")
        else()
          set(_triple "aarch64-apple-ios-sim")
        endif()
      else()
        if(_requested_arch STREQUAL "x86_64")
          message(FATAL_ERROR
            "read_aloud: x86_64 is not a valid iOS device architecture; use "
            "ARM64 or the iphonesimulator sysroot.")
        endif()
        set(_triple "aarch64-apple-ios")
      endif()
      set(_cross TRUE)
    else()
      if(_requested_arch STREQUAL "arm64")
        set(_triple "aarch64-apple-darwin")
      else()
        set(_triple "x86_64-apple-darwin")
      endif()
      if(NOT _requested_arch STREQUAL _host_arch)
        set(_cross TRUE)
      endif()
    endif()
  elseif(WIN32)
    if(NOT MSVC)
      message(FATAL_ERROR
        "read_aloud: only the MSVC ABI is supported on Windows; MinGW builds "
        "are not wired up. Configure with -DCHATVV_ENABLE_READ_ALOUD=OFF to "
        "build the TTS stub instead.")
    endif()
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|ARM64)$")
      set(_triple "aarch64-pc-windows-msvc")
    elseif(CMAKE_SIZEOF_VOID_P EQUAL 4)
      set(_triple "i686-pc-windows-msvc")
    else()
      set(_triple "x86_64-pc-windows-msvc")
    endif()
    # rustc finds the MSVC toolchain itself; only cross-arch needs --target.
    if(CMAKE_CROSSCOMPILING)
      set(_cross TRUE)
    endif()
  elseif(CMAKE_CROSSCOMPILING)
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
      set(_triple "aarch64-unknown-linux-gnu")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(armv7l|armv7|armhf|arm)$")
      set(_triple "armv7-unknown-linux-gnueabihf")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(i.86|x86)$")
      set(_triple "i686-unknown-linux-gnu")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|x64)$")
      set(_triple "x86_64-unknown-linux-gnu")
    else()
      message(FATAL_ERROR
        "read_aloud: cannot derive a cargo target triple for cross build with "
        "CMAKE_SYSTEM_NAME=${CMAKE_SYSTEM_NAME} and "
        "CMAKE_SYSTEM_PROCESSOR=${CMAKE_SYSTEM_PROCESSOR}. "
        "Set -DREAD_ALOUD_TARGET=<rustc target triple>.")
    endif()
    set(_cross TRUE)
  endif()

  if(NOT _cross)
    # Native build: cargo runs without --target and build.rs writes the header
    # to <CARGO_TARGET_DIR>/<profile>/read_aloud.h.
    set(_triple "")
  endif()
  set(${out_triple} "${_triple}" PARENT_SCOPE)
  set(${out_cross} "${_cross}" PARENT_SCOPE)
endfunction()

# Detect an OpenSSL prefix usable by openssl-sys for Linux/Android builds.
#   out_dir:    prefix containing include/openssl/ssl.h, or "" when unknown
#   out_static: ON when the prefix provides static libraries
function(_chatvv_read_aloud_detect_openssl out_dir out_static)
  set(${out_dir} "" PARENT_SCOPE)
  set(${out_static} "" PARENT_SCOPE)
  if(APPLE OR WIN32)
    return()  # platform TLS stack (SChannel / Security.framework): no OpenSSL
  endif()

  set(_candidates "")
  if(CHATVV_READ_ALOUD_OPENSSL_DIR)
    list(APPEND _candidates "${CHATVV_READ_ALOUD_OPENSSL_DIR}")
  endif()
  if(DEFINED ENV{OPENSSL_DIR} AND NOT "$ENV{OPENSSL_DIR}" STREQUAL "")
    list(APPEND _candidates "$ENV{OPENSSL_DIR}")
  endif()
  if(DEFINED VCPKG_INSTALLED_DIR AND NOT "${VCPKG_INSTALLED_DIR}" STREQUAL ""
     AND DEFINED VCPKG_TARGET_TRIPLET AND NOT "${VCPKG_TARGET_TRIPLET}" STREQUAL "")
    list(APPEND _candidates "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}")
  endif()
  if(DEFINED VCPKG_TARGET_TRIPLET AND NOT "${VCPKG_TARGET_TRIPLET}" STREQUAL "")
    list(APPEND _candidates "${CMAKE_SOURCE_DIR}/.vcpkg_installed/${VCPKG_TARGET_TRIPLET}")
  endif()

  foreach(_candidate IN LISTS _candidates)
    if(EXISTS "${_candidate}/include/openssl/ssl.h")
      set(${out_dir} "${_candidate}" PARENT_SCOPE)
      file(GLOB _openssl_static "${_candidate}/lib/libssl.a"
                                "${_candidate}/lib/libcrypto.a"
                                "${_candidate}/lib/ssl.lib"
                                "${_candidate}/lib/crypto.lib")
      if(_openssl_static)
        set(${out_static} ON PARENT_SCOPE)
      else()
        set(${out_static} OFF PARENT_SCOPE)
      endif()
      return()
    endif()
  endforeach()
endfunction()

# ---------------------------------------------------------------------------
# chatvv_add_read_aloud()
# ---------------------------------------------------------------------------
function(chatvv_add_read_aloud)
  if(TARGET chatvv::read_aloud)
    return()
  endif()
  if(NOT CHATVV_ENABLE_READ_ALOUD)
    message(STATUS
      "read-aloud TTS backend disabled (CHATVV_ENABLE_READ_ALOUD=OFF): "
      "src/tts/synthesize.cpp will build the stub implementation.")
    return()
  endif()

  set(_src "${CHATVV_READ_ALOUD_SOURCE_DIR}")
  if(NOT EXISTS "${_src}/Cargo.toml" OR NOT EXISTS "${_src}/src/ffi.rs")
    message(FATAL_ERROR
      "read_aloud sources are missing from '${_src}'. The vendored crate "
      "should contain Cargo.toml and src/ffi.rs (see "
      "third_party/read_aloud/VENDORED.chatvv.md).")
  endif()

  _chatvv_read_aloud_find_tools(_cargo _rustc _rustup)
  if(NOT _cargo)
    message(FATAL_ERROR
      "read-aloud TTS backend requires cargo, but no cargo executable was "
      "found.\n"
      "  * install Rust (https://rustup.rs) or make cargo available on PATH, or\n"
      "  * set -DCHATVV_READ_ALOUD_CARGO=/path/to/cargo, or\n"
      "  * configure with -DCHATVV_ENABLE_READ_ALOUD=OFF to build without TTS\n"
      "    network synthesis (src/tts/synthesize.cpp then compiles a stub).")
  endif()

  # --- linkage -------------------------------------------------------------
  set(_linkage "${CHATVV_READ_ALOUD_LINKAGE}")
  if(_linkage STREQUAL "auto")
    if(ANDROID)
      set(_linkage "shared")
    else()
      set(_linkage "static")
    endif()
  endif()
  if(NOT _linkage MATCHES "^(static|shared)$")
    message(FATAL_ERROR
      "read_aloud: CHATVV_READ_ALOUD_LINKAGE must be auto, static or shared "
      "(got '${CHATVV_READ_ALOUD_LINKAGE}').")
  endif()
  if(APPLE AND NOT _linkage STREQUAL "static")
    message(WARNING
      "read_aloud: shared linkage on Apple platforms is not recommended "
      "(dylib signing/rpath). iOS builds always use the static library; "
      "prefer -DCHATVV_READ_ALOUD_LINKAGE=static.")
    if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
      set(_linkage "static")
    endif()
  endif()

  # --- cargo profile -------------------------------------------------------
  set(_profile "${CHATVV_READ_ALOUD_PROFILE}")
  if(_profile STREQUAL "auto")
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
      set(_profile "debug")
    else()
      set(_profile "release")
    endif()
  endif()
  if(_profile STREQUAL "release")
    set(_profile_args --release)
    set(_profile_dir "release")
    set(_profile_label "release")
  elseif(_profile STREQUAL "debug")
    set(_profile_args "")
    set(_profile_dir "debug")
    set(_profile_label "dev (debug)")
  else()
    message(FATAL_ERROR
      "read_aloud: CHATVV_READ_ALOUD_PROFILE must be auto, release or debug "
      "(got '${CHATVV_READ_ALOUD_PROFILE}').")
  endif()

  # --- target triple / cross flag -----------------------------------------
  _chatvv_read_aloud_resolve_target(_target _cross)

  # Verify the standard library for the cross target is installed when rustup
  # is available; the raw cargo error is otherwise hard to interpret.
  if(_cross AND _rustup)
    execute_process(COMMAND "${_rustup}" target list --installed
      OUTPUT_VARIABLE _installed_targets
      ERROR_VARIABLE _installed_error
      RESULT_VARIABLE _installed_result
      OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(_installed_result EQUAL 0)
      string(FIND "\n${_installed_targets}\n" "\n${_target}\n" _target_pos)
      if(_target_pos EQUAL -1)
        message(FATAL_ERROR
          "read_aloud: Rust target '${_target}' is not installed.\n"
          "Install it with: rustup target add ${_target}\n"
          "In CI: use e.g. dtolnay/rust-toolchain with targets: ${_target}\n"
          "Or configure -DCHATVV_ENABLE_READ_ALOUD=OFF to build without TTS.")
      endif()
    endif()
  elseif(_cross AND NOT _rustup)
    message(STATUS
      "read_aloud: rustup not found; assuming the standard library for "
      "'${_target}' is installed (cargo will fail with a readable error "
      "otherwise).")
  endif()

  # --- OpenSSL (native-tls on Linux/Android) ------------------------------
  _chatvv_read_aloud_detect_openssl(_openssl_dir _openssl_static)
  set(_openssl_libs "")
  set(_openssl_link_args "")
  if(NOT APPLE AND NOT WIN32)
    if(_openssl_dir)
      file(GLOB _ssl_candidates "${_openssl_dir}/lib/libssl.*")
      file(GLOB _crypto_candidates "${_openssl_dir}/lib/libcrypto.*")
      if(NOT _ssl_candidates OR NOT _crypto_candidates)
        message(FATAL_ERROR
          "read_aloud: OPENSSL_DIR '${_openssl_dir}' has include/openssl but no "
          "libssl/libcrypto under lib/.")
      endif()
      list(GET _ssl_candidates 0 _ssl_lib)
      list(GET _crypto_candidates 0 _crypto_lib)
      list(APPEND _openssl_libs "${_ssl_lib}" "${_crypto_lib}")
    elseif(_cross)
      message(FATAL_ERROR
        "read_aloud: cross-compiling native-tls for '${_target}' needs OpenSSL "
        "built for that target.\n"
        "  * point -DCHATVV_READ_ALOUD_OPENSSL_DIR at a prefix containing "
        "include/openssl and lib/libssl.a|.so (vcpkg triplets usually land in "
        "${CMAKE_SOURCE_DIR}/.vcpkg_installed/<triplet>), or\n"
        "  * configure -DCHATVV_ENABLE_READ_ALOUD=OFF to build the TTS stub.")
    else()
      find_package(OpenSSL REQUIRED)
      if(TARGET OpenSSL::SSL AND TARGET OpenSSL::Crypto)
        list(APPEND _openssl_libs OpenSSL::SSL OpenSSL::Crypto)
      else()
        message(FATAL_ERROR
          "read_aloud: OpenSSL was found but its imported targets are missing.")
      endif()
    endif()
  endif()

  # --- cargo environment ---------------------------------------------------
  set(_env "CARGO_TARGET_DIR=${CHATVV_READ_ALOUD_CARGO_TARGET_DIR}")

  # Target-scoped rustflags (only the target crates, never build scripts).
  set(_rustflags "")
  if(ANDROID)
    list(APPEND _rustflags "-C" "relocation-model=pic")
    list(APPEND _rustflags "-C" "link-arg=-Wl,-soname,libread_aloud.so")
    # Android 15+ devices boot with 16 KB pages; keep the shared library
    # compatible even though the final libchatvv_ffi link also sets these.
    list(APPEND _rustflags "-C" "link-arg=-Wl,-z,max-page-size=16384")
    list(APPEND _rustflags "-C" "link-arg=-Wl,-z,common-page-size=16384")
    if("${_openssl_static}")
      # Some static OpenSSL builds depend on zlib; libz always exists in the NDK.
      list(APPEND _rustflags "-C" "link-arg=-lz")
    endif()
  elseif(APPLE)
    if(_linkage STREQUAL "shared")
      list(APPEND _rustflags "-C"
           "link-arg=-Wl,-install_name,@rpath/libread_aloud.dylib")
    endif()
  elseif(UNIX)
    list(APPEND _rustflags "-C" "relocation-model=pic")
    list(APPEND _rustflags "-C" "link-arg=-Wl,-soname,libread_aloud.so")
  endif()
  if(_rustflags)
    if(DEFINED ENV{RUSTFLAGS} AND NOT "$ENV{RUSTFLAGS}" STREQUAL "")
      set(_rustflags "$ENV{RUSTFLAGS} ${_rustflags}")
    endif()
    string(REPLACE ";" " " _rustflags_string "${_rustflags}")
    if(_target)
      string(TOUPPER "${_target}" _target_upper)
    else()
      # Native build: cargo applies CARGO_TARGET_<host>_RUSTFLAGS.
      set(_host_for_flags "")
      if(_rustc)
        execute_process(COMMAND "${_rustc}" -vV
          OUTPUT_VARIABLE _rv OUTPUT_STRIP_TRAILING_WHITESPACE
          ERROR_QUIET RESULT_VARIABLE _rr)
        if(_rr EQUAL 0 AND _rv MATCHES "host: ([A-Za-z0-9_.-]+)")
          set(_host_for_flags "${CMAKE_MATCH_1}")
        endif()
      endif()
      if(_host_for_flags)
        string(TOUPPER "${_host_for_flags}" _target_upper)
      endif()
    endif()
    if(_target_upper)
      string(REPLACE "-" "_" _target_env "${_target_upper}")
      list(APPEND _env "CARGO_TARGET_${_target_env}_RUSTFLAGS=${_rustflags_string}")
    else()
      list(APPEND _env "RUSTFLAGS=${_rustflags_string}")
    endif()
  endif()

  # Linker and C toolchain for cross builds (openssl-sys uses the C toolchain).
  if(_cross AND _target)
    set(_target_upper "${_target}")
    string(TOUPPER "${_target_upper}" _target_upper)
    string(REPLACE "-" "_" _target_env "${_target_upper}")
    if(CMAKE_C_COMPILER)
      list(APPEND _env "CARGO_TARGET_${_target_env}_LINKER=${CMAKE_C_COMPILER}")
      list(APPEND _env "CC_${_target}=${CMAKE_C_COMPILER}")
      list(APPEND _env "CC_${_target_env}=${CMAKE_C_COMPILER}")
    endif()
    if(CMAKE_CXX_COMPILER)
      list(APPEND _env "CXX_${_target}=${CMAKE_CXX_COMPILER}")
      list(APPEND _env "CXX_${_target_env}=${CMAKE_CXX_COMPILER}")
    endif()
    set(_ar "${CMAKE_AR}")
    if(NOT _ar AND CMAKE_C_COMPILER)
      get_filename_component(_cc_dir "${CMAKE_C_COMPILER}" DIRECTORY)
      if(EXISTS "${_cc_dir}/llvm-ar")
        set(_ar "${_cc_dir}/llvm-ar")
      endif()
    endif()
    if(_ar)
      list(APPEND _env "AR_${_target}=${_ar}")
      list(APPEND _env "AR_${_target_env}=${_ar}")
    endif()
    if(CMAKE_RANLIB)
      list(APPEND _env "RANLIB_${_target}=${CMAKE_RANLIB}")
      list(APPEND _env "RANLIB_${_target_env}=${CMAKE_RANLIB}")
    endif()
  endif()

  if(APPLE)
    if(CMAKE_OSX_SYSROOT)
      list(APPEND _env "SDKROOT=${CMAKE_OSX_SYSROOT}")
    endif()
    if(CMAKE_OSX_DEPLOYMENT_TARGET)
      if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
        list(APPEND _env
             "IPHONEOS_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}")
      else()
        list(APPEND _env
             "MACOSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}")
      endif()
    endif()
  endif()

  if(_openssl_dir)
    list(APPEND _env "OPENSSL_DIR=${_openssl_dir}")
    list(APPEND _env "OPENSSL_NO_VENDOR=1")
    if("${_openssl_static}")
      list(APPEND _env "OPENSSL_STATIC=1")
    else()
      list(APPEND _env "OPENSSL_STATIC=0")
    endif()
  endif()

  if(CHATVV_READ_ALOUD_OFFLINE)
    set(_offline_arg --offline)
  else()
    set(_offline_arg "")
  endif()

  # --- expected cargo outputs and staging paths ---------------------------
  set(_cargo_out "${CHATVV_READ_ALOUD_CARGO_TARGET_DIR}")
  if(_target)
    string(APPEND _cargo_out "/${_target}")
  endif()
  string(APPEND _cargo_out "/${_profile_dir}")

  if(WIN32 AND MSVC)
    set(_cargo_static "${_cargo_out}/read_aloud.lib")
    set(_cargo_shared "${_cargo_out}/read_aloud.dll")
    set(_cargo_implib "${_cargo_out}/read_aloud.dll.lib")
  else()
    set(_cargo_static
        "${_cargo_out}/${CMAKE_STATIC_LIBRARY_PREFIX}read_aloud${CMAKE_STATIC_LIBRARY_SUFFIX}")
    set(_cargo_shared
        "${_cargo_out}/${CMAKE_SHARED_LIBRARY_PREFIX}read_aloud${CMAKE_SHARED_LIBRARY_SUFFIX}")
    set(_cargo_implib "")
  endif()
  set(_cargo_header "${_cargo_out}/read_aloud.h")

  set(_stage "${CHATVV_READ_ALOUD_STAGING_DIR}")
  set(_stage_include "${_stage}/include")
  set(_stage_lib "${_stage}/lib")
  set(_stage_header "${_stage_include}/read_aloud.h")
  if(WIN32 AND MSVC)
    set(_staged_static "${_stage_lib}/read_aloud.lib")
    set(_staged_shared "${_stage_lib}/read_aloud.dll")
    set(_staged_implib "${_stage_lib}/read_aloud.dll.lib")
  else()
    set(_staged_static
        "${_stage_lib}/${CMAKE_STATIC_LIBRARY_PREFIX}read_aloud${CMAKE_STATIC_LIBRARY_SUFFIX}")
    set(_staged_shared
        "${_stage_lib}/${CMAKE_SHARED_LIBRARY_PREFIX}read_aloud${CMAKE_SHARED_LIBRARY_SUFFIX}")
    set(_staged_implib "")
  endif()

  # CMake validates INTERFACE_INCLUDE_DIRECTORIES at generate time, but the
  # cbindgen header only appears after the first build. Create the staging
  # directories now so configuring before building is allowed.
  file(MAKE_DIRECTORY "${_stage_include}" "${_stage_lib}")

  # --- cargo build ---------------------------------------------------------
  set(_target_args "")
  if(_target)
    list(APPEND _target_args --target "${_target}")
    set(_target_label "${_target}")
  else()
    set(_target_label "native")
  endif()

  file(GLOB_RECURSE _cargo_inputs LIST_DIRECTORIES false
       "${_src}/src/*.rs"
       "${_src}/Cargo.toml"
       "${_src}/Cargo.lock"
       "${_src}/build.rs"
       "${_src}/cbindgen.toml")
  set(_cargo_stamp "${CHATVV_READ_ALOUD_CARGO_TARGET_DIR}/.read_aloud-build.stamp")

  add_custom_command(
    OUTPUT "${_cargo_stamp}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory
            "${CHATVV_READ_ALOUD_CARGO_TARGET_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E env ${_env}
            "${_cargo}" build
            --manifest-path "${_src}/Cargo.toml"
            --locked
            ${_target_args}
            ${_profile_args}
            ${_offline_arg}
    COMMAND "${CMAKE_COMMAND}" -E touch "${_cargo_stamp}"
    DEPENDS ${_cargo_inputs}
    WORKING_DIRECTORY "${_src}"
    COMMENT "Building read_aloud (cargo ${_profile_label}, target: ${_target_label})"
    USES_TERMINAL
    VERBATIM)

  # --- staging -------------------------------------------------------------
  set(_staged_outputs "${_stage_header}" "${_staged_static}" "${_staged_shared}")
  add_custom_command(
    OUTPUT ${_staged_outputs}
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${_stage_include}" "${_stage_lib}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${_cargo_header}" "${_stage_header}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${_cargo_static}" "${_staged_static}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${_cargo_shared}" "${_staged_shared}"
    DEPENDS "${_cargo_stamp}"
    COMMENT "Staging read_aloud artifacts into ${_stage}"
    VERBATIM)

  if(WIN32 AND MSVC)
    add_custom_command(
      OUTPUT "${_staged_implib}"
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different
              "${_cargo_implib}" "${_staged_implib}"
      DEPENDS "${_staged_shared}"
      COMMENT "Staging read_aloud MSVC import library"
      VERBATIM)
    list(APPEND _staged_outputs "${_staged_implib}")
  endif()

  add_custom_target(chatvv_read_aloud_build DEPENDS ${_staged_outputs})

  # --- imported target -----------------------------------------------------
  add_library(chatvv::read_aloud UNKNOWN IMPORTED GLOBAL)
  add_dependencies(chatvv::read_aloud chatvv_read_aloud_build)

  set(_link_libraries "")
  if(_linkage STREQUAL "static")
    if(APPLE)
      list(APPEND _link_libraries
           "-Wl,-framework,Security"
           "-Wl,-framework,CoreFoundation"
           "-Wl,-framework,Foundation")
    elseif(ANDROID)
      if(NOT TARGET Threads::Threads)
        find_package(Threads REQUIRED)
      endif()
      list(APPEND _link_libraries ${_openssl_libs} z log m
           ${CMAKE_DL_LIBS} Threads::Threads)
    elseif(WIN32)
      # Rust std + native-tls/schannel import libraries on MSVC.
      list(APPEND _link_libraries
           ws2_32 userenv bcrypt crypt32 ntdll advapi32 secur32 iphlpapi ole32)
    else()
      if(NOT TARGET Threads::Threads)
        find_package(Threads REQUIRED)
      endif()
      list(APPEND _link_libraries ${_openssl_libs}
           Threads::Threads ${CMAKE_DL_LIBS} m)
    endif()
    set(_imported_location "${_staged_static}")
  else()
    set(_imported_location "${_staged_shared}")
  endif()

  set_target_properties(chatvv::read_aloud PROPERTIES
    IMPORTED_LOCATION "${_imported_location}"
    INTERFACE_INCLUDE_DIRECTORIES "${_stage_include}"
    INTERFACE_COMPILE_DEFINITIONS "CHATVV_HAVE_READ_ALOUD=1"
    INTERFACE_LINK_LIBRARIES "${_link_libraries}")

  if(WIN32 AND MSVC AND _linkage STREQUAL "shared")
    # Runtime = the DLL, link time = the import library.
    set_target_properties(chatvv::read_aloud PROPERTIES
      IMPORTED_IMPLIB "${_staged_implib}")
  endif()

  message(STATUS
    "read-aloud TTS: target=${_target_label} linkage=${_linkage} "
    "profile=${_profile}")
  message(STATUS
    "read-aloud TTS: artifacts staged in ${_stage} "
    "(include/read_aloud.h, lib/...)")
endfunction()

chatvv_add_read_aloud()
