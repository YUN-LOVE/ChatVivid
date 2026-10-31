#pragma once

#include <nlohmann/json.hpp>

#include <string>
#include <vector>

#include "context/injections.h"

namespace chatvv {

class Db;
class EmbeddingEngine;
struct Config;

struct BuiltContext {
  std::string instructions;
  nlohmann::json input = nlohmann::json::array();
  nlohmann::json tools = nlohmann::json::array();
  nlohmann::json manifest = nlohmann::json::object();
};

BuiltContext build_context(Db& db, const InjectionStore& slots,
                           const Config& cfg, const std::string& user_text,
                           const std::vector<Injection>& extra = {},
                           EmbeddingEngine* embedding = nullptr);

}  // namespace chatvv
