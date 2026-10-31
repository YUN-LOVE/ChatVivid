#include "context/injections.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <set>
#include <sstream>

#include "util/log.h"
#include "util/util.h"

namespace fs = std::filesystem;

namespace chatvv {
namespace {

const std::set<std::string> kPositions = {
    "before_system", "system",      "after_system", "chat_start",
    "after_first_message", "before_latest", "at_depth"};

const std::set<std::string> kHeadPositions = {
    "before_system", "system", "after_system", "chat_start",
    "after_first_message"};

std::string strip_comments(std::string s) {
  size_t pos = 0;
  while ((pos = s.find("<!--", pos)) != std::string::npos) {
    const size_t end = s.find("-->", pos + 4);
    if (end == std::string::npos) {
      s.erase(pos);
      break;
    }
    s.erase(pos, end + 3 - pos);
  }
  return s;
}

bool parse_bool(const std::string& v, bool fallback) {
  if (v == "true" || v == "1" || v == "yes") return true;
  if (v == "false" || v == "0" || v == "no") return false;
  return fallback;
}

int parse_int(const std::string& v, int fallback) {
  try {
    return std::stoi(v);
  } catch (...) {
    return fallback;
  }
}

std::string read_file(const fs::path& p) {
  std::ifstream in(p, std::ios::binary);
  if (!in) return {};
  std::ostringstream ss;
  ss << in.rdbuf();
  return ss.str();
}

bool parse_slot(const fs::path& path, Injection& out, std::string& error) {
  std::string raw = read_file(path);
  if (raw.empty()) {
    error = "empty file";
    return false;
  }

  std::string s;
  s.reserve(raw.size());
  for (char c : raw) {
    if (c != '\r') s.push_back(c);
  }

  if (!starts_with(s, "---\n")) {
    error = "missing YAML frontmatter";
    return false;
  }
  const size_t fm_end = s.find("\n---", 4);
  if (fm_end == std::string::npos) {
    error = "unterminated frontmatter";
    return false;
  }

  std::string fm = s.substr(4, fm_end - 4);
  size_t body_start = fm_end + 4;
  if (body_start < s.size() && s[body_start] == '\n') ++body_start;
  out.body = trim(strip_comments(s.substr(body_start)));
  out.name = path.stem().string();

  bool has_position = false;
  std::istringstream lines(fm);
  std::string line;
  while (std::getline(lines, line)) {
    line = trim(line);
    if (line.empty() || line[0] == '#') continue;
    const auto colon = line.find(':');
    if (colon == std::string::npos) continue;
    const std::string key = trim(line.substr(0, colon));
    std::string value = trim(line.substr(colon + 1));
    if (value.size() >= 2 &&
        ((value.front() == '"' && value.back() == '"') ||
         (value.front() == '\'' && value.back() == '\''))) {
      value = value.substr(1, value.size() - 2);
    }

    if (key == "position") {
      out.position = value;
      has_position = true;
    } else if (key == "priority") {
      out.priority = parse_int(value, out.priority);
    } else if (key == "enabled") {
      out.enabled = parse_bool(value, out.enabled);
    } else if (key == "depth") {
      out.depth = parse_int(value, out.depth);
    } else if (key == "mode") {
      out.mode = value;
    } else if (key == "trust") {
      out.trust = value;
    } else if (key == "cache") {
      out.cache = value;
    } else if (key == "description") {
      out.description = value;
    }
  }

  if (!has_position) {
    error = "missing position";
    return false;
  }
  if (!kPositions.contains(out.position)) {
    error = "unknown position: " + out.position;
    return false;
  }
  if (out.position == "at_depth") {
    if (out.depth < 1 || out.depth > 64) {
      error = "at_depth requires depth in [1, 64]";
      return false;
    }
  } else {
    out.depth = 0;
  }
  if (out.position != "system" && out.mode != "append") {
    out.mode = "append";
  }
  if (out.cache != "day" && out.cache != "immediate") {
    out.cache = kHeadPositions.contains(out.position) ? "day" : "immediate";
  }
  if (out.body.empty()) {
    error = "empty body";
    return false;
  }
  return true;
}

}  // namespace

void InjectionStore::load_dir(const std::string& dir) {
  slots_.clear();
  std::error_code ec;
  if (!fs::is_directory(dir, ec)) {
    log_warn("injections.dir_missing", {{"dir", dir}});
    return;
  }

  for (const auto& entry : fs::directory_iterator(dir, ec)) {
    if (ec) break;
    if (!entry.is_regular_file()) continue;
    if (entry.path().extension() != ".md") continue;
    if (entry.path().filename() == "README.md") continue;

    Injection slot;
    std::string error;
    if (!parse_slot(entry.path(), slot, error)) {
      log_warn("injections.invalid",
               {{"file", entry.path().string()}, {"error", error}});
      continue;
    }
    if (!slot.enabled) {
      log_debug("injections.disabled", {{"name", slot.name}});
      continue;
    }
    slots_.push_back(std::move(slot));
  }

  std::sort(slots_.begin(), slots_.end(),
            [](const Injection& a, const Injection& b) {
              if (a.priority != b.priority) return a.priority < b.priority;
              return a.name < b.name;
            });
  log_info("injections.loaded", {{"dir", dir}, {"count", slots_.size()}});
}

std::vector<Injection> InjectionStore::by_position(
    const std::string& position) const {
  std::vector<Injection> out;
  for (const auto& slot : slots_) {
    if (slot.enabled && slot.position == position) out.push_back(slot);
  }
  return out;
}

nlohmann::json InjectionStore::to_json() const {
  nlohmann::json arr = nlohmann::json::array();
  for (const auto& slot : slots_) {
    arr.push_back({{"name", slot.name},
                   {"position", slot.position},
                   {"depth", slot.depth},
                   {"priority", slot.priority},
                   {"enabled", slot.enabled},
                   {"trust", slot.trust},
                   {"cache", slot.cache},
                   {"mode", slot.mode},
                   {"description", slot.description},
                   {"tokens", estimate_tokens(slot.body)}});
  }
  return arr;
}

}  // namespace chatvv
