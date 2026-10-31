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

add_library(chatvv_core STATIC
  src/util/log.cpp
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
  src/http/server.cpp)
target_include_directories(chatvv_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(chatvv_core PUBLIC chatvv_deps)
chatvv_warnings(chatvv_core)

add_executable(chatvvd src/main.cpp)
target_link_libraries(chatvvd PRIVATE chatvv_core)
chatvv_warnings(chatvvd)

enable_testing()
add_executable(chatvv_tests tests/test_core.cpp)
target_link_libraries(chatvv_tests PRIVATE chatvv_core)
chatvv_warnings(chatvv_tests)
add_test(NAME core COMMAND chatvv_tests)

# The smoke test is a bash script; Windows only runs the core test.
if(UNIX)
  add_test(NAME smoke COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/scripts/smoke.sh)
  set_tests_properties(smoke PROPERTIES WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
endif()

install(TARGETS chatvvd RUNTIME DESTINATION bin)
install(FILES config/config.example.toml DESTINATION share/chatvv)
