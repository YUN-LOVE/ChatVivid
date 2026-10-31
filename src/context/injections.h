#pragma once

#include <nlohmann/json.hpp>

#include <string>
#include <vector>

namespace chatvv {

struct Injection {
  std::string name;
  std::string position;
  std::string mode = "append";
  std::string trust = "instruction";
  std::string cache = "day";
  std::string description;
  std::string body;
  int depth = 0;
  int priority = 100;
  bool enabled = true;
};

class InjectionStore {
 public:
  void load_dir(const std::string& dir);
  std::vector<Injection> by_position(const std::string& position) const;
  const std::vector<Injection>& all() const { return slots_; }
  nlohmann::json to_json() const;

 private:
  std::vector<Injection> slots_;
};

}  // namespace chatvv
