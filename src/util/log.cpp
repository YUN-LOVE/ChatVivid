#include "util/log.h"

#include <chrono>
#include <cstdio>
#include <ctime>
#include <fstream>
#include <mutex>

namespace chatvv {
namespace {

std::mutex g_mu;
LogLevel g_level = LogLevel::Info;
std::ofstream g_file;

const char* level_name(LogLevel level) {
  switch (level) {
    case LogLevel::Debug: return "debug";
    case LogLevel::Info: return "info";
    case LogLevel::Warn: return "warn";
    case LogLevel::Error: return "error";
  }
  return "info";
}

std::string timestamp() {
  using namespace std::chrono;
  const auto now = system_clock::now();
  const auto t = system_clock::to_time_t(now);
  const auto ms = duration_cast<milliseconds>(now.time_since_epoch()) % 1000;
  std::tm tm{};
#if defined(_WIN32) && !defined(__MINGW32__)
  localtime_s(&tm, &t);
#else
  localtime_r(&t, &tm);
#endif
  char date[32];
  std::strftime(date, sizeof(date), "%Y-%m-%dT%H:%M:%S", &tm);
  char out[48];
  std::snprintf(out, sizeof(out), "%s.%03d", date,
                static_cast<int>(ms.count()));
  return out;
}

}  // namespace

void init_log(LogLevel level, const std::filesystem::path& file_path) {
  std::lock_guard lock(g_mu);
  g_level = level;
  if (!file_path.empty()) {
    g_file.open(file_path, std::ios::app);
  }
}

void log(LogLevel level, std::string_view event, const nlohmann::json& fields) {
  if (static_cast<int>(level) < static_cast<int>(g_level)) return;

  nlohmann::json j = {
      {"ts", timestamp()},
      {"level", level_name(level)},
      {"event", std::string(event)},
  };
  if (fields.is_object()) {
    for (auto& [key, value] : fields.items()) j[key] = value;
  } else if (!fields.is_null()) {
    j["data"] = fields;
  }
  const auto line = j.dump() + "\n";

  std::lock_guard lock(g_mu);
  std::fwrite(line.data(), 1, line.size(), stderr);
  if (g_file) {
    g_file << line;
    g_file.flush();
  }
}

}  // namespace chatvv
