#pragma once

#include <chrono>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace chatvv {

inline int64_t now_ms() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::system_clock::now().time_since_epoch())
      .count();
}

inline std::string trim(std::string_view s) {
  const auto begin = s.find_first_not_of(" \t\r\n");
  if (begin == std::string_view::npos) return {};
  const auto end = s.find_last_not_of(" \t\r\n");
  return std::string(s.substr(begin, end - begin + 1));
}

inline std::string join(const std::vector<std::string>& parts, std::string_view sep) {
  std::string out;
  for (size_t i = 0; i < parts.size(); ++i) {
    if (i) out.append(sep);
    out.append(parts[i]);
  }
  return out;
}

inline int estimate_tokens(std::string_view s) {
  return static_cast<int>(s.size() / 3) + 1;
}

inline bool starts_with(std::string_view s, std::string_view prefix) {
  return s.size() >= prefix.size() && s.compare(0, prefix.size(), prefix) == 0;
}

}  // namespace chatvv
