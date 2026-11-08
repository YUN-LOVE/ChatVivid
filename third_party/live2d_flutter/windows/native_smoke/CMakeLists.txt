cmake_minimum_required(VERSION 3.16)

cmake_policy(SET CMP0091 NEW)
project(native_live2d_smoke LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")

set(CUBISM_SDK_ROOT "" CACHE PATH "Extracted Cubism SDK for Native root")
if(NOT EXISTS "${CUBISM_SDK_ROOT}/Core/include/Live2DCubismCore.h")
  message(FATAL_ERROR "Set CUBISM_SDK_ROOT to the extracted Cubism SDK root")
endif()
set(CUBISM_FRAMEWORK_ROOT "${CUBISM_SDK_ROOT}/Framework" CACHE PATH
  "Cubism Framework source root")
if(EXISTS "${CUBISM_FRAMEWORK_ROOT}/src/CubismFramework.cpp")
  set(CUBISM_FRAMEWORK_SOURCE_ROOT "${CUBISM_FRAMEWORK_ROOT}/src")
  set(CUBISM_FRAMEWORK_STANDALONE ON)
elseif(EXISTS "${CUBISM_FRAMEWORK_ROOT}/CubismFramework.cpp")
  set(CUBISM_FRAMEWORK_SOURCE_ROOT "${CUBISM_FRAMEWORK_ROOT}")
  set(CUBISM_FRAMEWORK_STANDALONE OFF)
else()
  message(FATAL_ERROR "Set CUBISM_FRAMEWORK_ROOT to a Cubism Framework source root")
endif()

set(FRAMEWORK_SOURCE D3D11)

add_library(Live2DCubismCore STATIC IMPORTED)
set_target_properties(Live2DCubismCore PROPERTIES
  IMPORTED_LOCATION_DEBUG
    "${CUBISM_SDK_ROOT}/Core/lib/windows/x86_64/143/Live2DCubismCore_MDd.lib"
  IMPORTED_LOCATION_RELEASE
    "${CUBISM_SDK_ROOT}/Core/lib/windows/x86_64/143/Live2DCubismCore_MD.lib"
  IMPORTED_LOCATION_RELWITHDEBINFO
    "${CUBISM_SDK_ROOT}/Core/lib/windows/x86_64/143/Live2DCubismCore_MD.lib"
  IMPORTED_LOCATION_MINSIZEREL
    "${CUBISM_SDK_ROOT}/Core/lib/windows/x86_64/143/Live2DCubismCore_MD.lib"
  INTERFACE_INCLUDE_DIRECTORIES "${CUBISM_SDK_ROOT}/Core/include"
)

if(CUBISM_FRAMEWORK_STANDALONE)
  add_subdirectory("${CUBISM_FRAMEWORK_ROOT}" cubism_framework)
else()
  file(GLOB_RECURSE CUBISM_FRAMEWORK_SOURCES CONFIGURE_DEPENDS
    "${CUBISM_FRAMEWORK_SOURCE_ROOT}/*.cpp"
  )
  list(FILTER CUBISM_FRAMEWORK_SOURCES EXCLUDE REGEX ".*/D3D9/.*")
  list(FILTER CUBISM_FRAMEWORK_SOURCES EXCLUDE REGEX ".*/Metal/.*")
  list(FILTER CUBISM_FRAMEWORK_SOURCES EXCLUDE REGEX ".*/OpenGL/.*")
  list(FILTER CUBISM_FRAMEWORK_SOURCES EXCLUDE REGEX ".*/Vulkan/.*")
  add_library(Framework STATIC ${CUBISM_FRAMEWORK_SOURCES})
  target_include_directories(Framework PUBLIC
    "${CUBISM_FRAMEWORK_SOURCE_ROOT}"
    "${CUBISM_SDK_ROOT}/Core/include"
  )
endif()
target_link_libraries(Framework PUBLIC
  Live2DCubismCore
  d3d11.lib
  d3dcompiler.lib
)

add_executable(native_live2d_smoke main.cpp)
target_compile_definitions(native_live2d_smoke PRIVATE _CRT_SECURE_NO_WARNINGS)
target_link_libraries(native_live2d_smoke PRIVATE
  Framework
  Live2DCubismCore
  d3d11.lib
  d3dcompiler.lib
)

add_custom_command(TARGET native_live2d_smoke POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_directory
    "${CUBISM_FRAMEWORK_SOURCE_ROOT}/Rendering/D3D11/Shaders"
    "$<TARGET_FILE_DIR:native_live2d_smoke>/FrameworkShaders"
)
