#pragma once

#include <nlohmann/json.hpp>

#include <filesystem>
#include <string>
#include <string_view>

namespace chatvv {

enum class LogLevel { Debug = 0, Info, Warn, Error };

void init_log(LogLevel level, const std::filesystem::path& file_path = {});
void log(LogLevel level, std::string_view event, const nlohmann::json& fields = {});

inline void log_debug(std::string_view e, const nlohmann::json& f = {}) {
  log(LogLevel::Debug, e, f);
}
inline void log_info(std::string_view e, const nlohmann::json& f = {}) {
  log(LogLevel::Info, e, f);
}
inline void log_warn(std::string_view e, const nlohmann::json& f = {}) {
  log(LogLevel::Warn, e, f);
}
inline void log_error(std::string_view e, const nlohmann::json& f = {}) {
  log(LogLevel::Error, e, f);
}

}  // namespace chatvv
