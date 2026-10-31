# Cross-compilation toolchain for Linux aarch64.
#
# Requirements:
#   sudo apt install g++-aarch64-linux-gnu
#   # plus an aarch64 sysroot with libcurl/sqlite if you link against system libs
#
# Typical use with vcpkg (builds curl/sqlite for arm64):
#   cmake --preset arm64-cross
#
# Or manually:
#   cmake -B build/arm64 -G Ninja \
#     -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake \
#     -DVCPKG_TARGET_TRIPLET=arm64-linux \
#     -DVCPKG_CHAINLOAD_TOOLCHAIN_FILE=cmake/toolchains/aarch64-linux-gnu.cmake

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
