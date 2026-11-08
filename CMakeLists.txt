cmake_minimum_required(VERSION 3.28)
project(chatvv VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "" FORCE)
endif()

# Vendored single-header dependencies (pinned; see third_party/README.md)
add_library(chatvv_deps INTERFACE)
target_include_directories(chatvv_deps SYSTEM INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/third_party)

# SQLite: CMake's FindSQLite3 on newer versions, vcpkg's port otherwise.
find_package(SQLite3 QUIET)
if(SQLite3_FOUND)
  if(TARGET SQLite3::SQLite3)
    set(CHATVV_SQLITE SQLite3::SQLite3)
  elseif(TARGET SQLite::SQLite3)
    set(CHATVV_SQLITE SQLite::SQLite3)
  else()
    message(FATAL_ERROR "SQLite3 was found but no imported target is available")
  endif()
else()
  find_package(unofficial-sqlite3 CONFIG REQUIRED)
  set(CHATVV_SQLITE unofficial::sqlite3::sqlite3)
endif()

find_package(CURL REQUIRED)
if(TARGET CURL::libcurl)
  set(CHATVV_CURL CURL::libcurl)
elseif(TARGET CURL::libcurl_shared)
  set(CHATVV_CURL CURL::libcurl_shared)
else()
  message(FATAL_ERROR "CURL was found but no imported target is available")
endif()

find_package(Threads REQUIRED)

target_link_libraries(chatvv_deps INTERFACE ${CHATVV_SQLITE} ${CHATVV_CURL} Threads::Threads)

if(WIN32)
  target_compile_definitions(chatvv_deps INTERFACE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_link_libraries(chatvv_deps INTERFACE ws2_32)
endif()

function(chatvv_warnings target)
  if(MSVC)
    target_compile_options(${target} PRIVATE /W4 /permissive- /utf-8)
  else()
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic)
  endif()
endfunction()

# Local RAG embeddings. llama.cpp is vendored and built as static CPU code.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_IS_DEV OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_MTMD OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
add_subdirectory(third_party/llama.cpp EXCLUDE_FROM_ALL)
# LTO across the large vendored llama/ggml graph is not worth the CI time.
foreach(_llama_target llama ggml ggml-base ggml-cpu)
  if(TARGET ${_llama_target})
    set_target_properties(${_llama_target} PROPERTIES
      INTERPROCEDURAL_OPTIMIZATION OFF
      CXX_STANDARD 17
      CXX_STANDARD_REQUIRED ON
      CXX_EXTENSIONS OFF)
  endif()
endforeach()

add_library(chatvv_core STATIC
  src/util/log.cpp
  src/memory/embedding.cpp
  src/util/ulid.cpp
  src/app/config.cpp
  src/store/db.cpp
  src/context/injections.cpp
  src/context/context_builder.cpp
  src/llm/provider.cpp
  src/llm/mock_provider.cpp
  src/llm/responses_provider.cpp
  src/dialog/response_hub.cpp
  src/dialog/dialog_service.cpp
  src/tts/edge_tts.cpp)
target_include_directories(chatvv_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_include_directories(chatvv_core SYSTEM PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/third_party/llama.cpp/include)
target_link_libraries(chatvv_core PUBLIC chatvv_deps llama)
set_target_properties(chatvv_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
chatvv_warnings(chatvv_core)

# HTTP/SSE is a server adapter, not part of the embedded core.
add_library(chatvv_server STATIC src/http/server.cpp)
target_include_directories(chatvv_server PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(chatvv_server PUBLIC chatvv_core)
chatvv_warnings(chatvv_server)

# Stable C ABI for Dart/FFI. The core never binds a socket in this path.
add_library(chatvv_ffi SHARED src/ffi/chatvv_ffi.cpp)
target_include_directories(chatvv_ffi
  PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(chatvv_ffi PRIVATE chatvv_core)
if(ANDROID)
  # Android 15+/17 requires 16 KB page-compatible ELF load segments.
  target_link_options(chatvv_ffi PRIVATE
    "-Wl,-z,max-page-size=16384"
    "-Wl,-z,common-page-size=16384")
endif()
target_compile_definitions(chatvv_ffi PRIVATE CHATVV_FFI_BUILD)
set_target_properties(chatvv_ffi PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON)
chatvv_warnings(chatvv_ffi)

add_executable(chatvvd src/main.cpp)
target_link_libraries(chatvvd PRIVATE chatvv_server)
chatvv_warnings(chatvvd)

enable_testing()
add_executable(chatvv_tests tests/test_core.cpp)
target_link_libraries(chatvv_tests PRIVATE chatvv_core)
target_compile_definitions(chatvv_tests PRIVATE
  CHATVV_TEST_MODEL="${CMAKE_CURRENT_SOURCE_DIR}/app/assets/models/bge-small-zh-v1.5-q8_0.gguf")
chatvv_warnings(chatvv_tests)
add_test(NAME core COMMAND chatvv_tests)

add_executable(chatvv_ffi_tests tests/test_ffi.cpp)
target_include_directories(chatvv_ffi_tests
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(chatvv_ffi_tests PRIVATE chatvv_ffi)
chatvv_warnings(chatvv_ffi_tests)
add_test(NAME ffi COMMAND chatvv_ffi_tests)

# The smoke test is a bash script; Windows only runs the core test.
if(UNIX)
  add_test(NAME smoke COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/scripts/smoke.sh)
  set_tests_properties(smoke PROPERTIES
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    ENVIRONMENT "BIN=$<TARGET_FILE:chatvvd>")
endif()

install(TARGETS chatvvd chatvv_ffi
  RUNTIME DESTINATION bin
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib)
install(FILES include/chatvv/chatvv.h DESTINATION include/chatvv)
install(FILES config/config.example.toml DESTINATION share/chatvv)
