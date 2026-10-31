#pragma once

#include <nlohmann/json.hpp>

#include <atomic>
#include <functional>
#include <memory>
#include <string>

namespace chatvv {

struct Config;

struct LlmRequest {
  std::string model;
  std::string instructions;
  nlohmann::json input = nlohmann::json::array();
  nlohmann::json tools = nlohmann::json::array();
  std::string reasoning_effort = "none";
  int max_output_tokens = 4096;
  std::string base_url;
  std::string endpoint;
  std::string api_key;
  int timeout_ms = 120000;
  std::atomic<bool>* cancel = nullptr;
};

using EventSink =
    std::function<void(const std::string& type, const nlohmann::json& data)>;

struct LlmResult {
  bool ok = false;
  std::string status = "failed";
  nlohmann::json output = nlohmann::json::array();
  nlohmann::json usage = nlohmann::json::object();
  std::string error;
};

class Provider {
 public:
  virtual ~Provider() = default;
  virtual LlmResult complete(const LlmRequest& req, const EventSink& sink) = 0;
};

std::unique_ptr<Provider> make_provider(const Config& cfg);

}  // namespace chatvv
