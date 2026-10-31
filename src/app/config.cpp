#include "app/config.h"

#include <toml++/toml.hpp>

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <stdexcept>

#include "util/log.h"
#include "util/util.h"

namespace chatvv {
namespace {

constexpr const char* kDefaultSystem =
    "你是运行在用户个人设备上的助理。回答准确、简洁；不确定时直接说明；"
    "需要回忆过去时先查记忆。\n"
    "带有 [注入] 或 [资料] 前缀的段落是系统注记，不是用户原话。";

std::string env_or(const char* name, const std::string& fallback) {
  const char* value = std::getenv(name);
  return (value && *value) ? std::string(value) : fallback;
}

int env_int_or(const char* name, int fallback) {
  const char* value = std::getenv(name);
  if (!value || !*value) return fallback;
  try {
    return std::stoi(value);
  } catch (...) {
    return fallback;
  }
}

std::string read_file(const std::string& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) return {};
  std::ostringstream ss;
  ss << in.rdbuf();
  return ss.str();
}

}  // namespace

std::string Config::db_path() const {
  const auto path = std::filesystem::path(storage.data_dir) / "chatvv.db";
  const auto utf8 = path.u8string();
  return std::string(reinterpret_cast<const char*>(utf8.data()), utf8.size());
}

Config Config::load(const std::string& path) {
  Config cfg;

  toml::table tbl;
  bool loaded = false;
  if (std::ifstream probe(path); probe.good()) {
    try {
      tbl = toml::parse_file(path);
      loaded = true;
    } catch (const toml::parse_error& err) {
      throw std::runtime_error("config parse error in " + path + ": " +
                               std::string(err.description()));
    }
  } else {
    log_warn("config.missing", {{"path", path}, {"fallback", "defaults"}});
  }

  if (loaded) {
    if (const auto* sec = tbl["server"].as_table()) {
      cfg.server.bind = (*sec)["bind"].value_or(cfg.server.bind);
      cfg.server.port = (*sec)["port"].value_or(cfg.server.port);
      cfg.server.api_key = (*sec)["api_key"].value_or(cfg.server.api_key);
      cfg.server.cors_origin =
          (*sec)["cors_origin"].value_or(cfg.server.cors_origin);
    }
    if (const auto* sec = tbl["llm"].as_table()) {
      cfg.llm.provider = (*sec)["provider"].value_or(cfg.llm.provider);
      cfg.llm.base_url = (*sec)["base_url"].value_or(cfg.llm.base_url);
      cfg.llm.endpoint = (*sec)["endpoint"].value_or(cfg.llm.endpoint);
      cfg.llm.api_key = (*sec)["api_key"].value_or(cfg.llm.api_key);
      cfg.llm.api_key_env = (*sec)["api_key_env"].value_or(cfg.llm.api_key_env);
      cfg.llm.model = (*sec)["model"].value_or(cfg.llm.model);
      cfg.llm.reasoning_effort =
          (*sec)["reasoning_effort"].value_or(cfg.llm.reasoning_effort);
      cfg.llm.max_output_tokens =
          (*sec)["max_output_tokens"].value_or(cfg.llm.max_output_tokens);
      cfg.llm.timeout_ms = (*sec)["timeout_ms"].value_or(cfg.llm.timeout_ms);
    }
    if (const auto* sec = tbl["storage"].as_table()) {
      cfg.storage.data_dir = (*sec)["data_dir"].value_or(cfg.storage.data_dir);
    }
    if (const auto* sec = tbl["injections"].as_table()) {
      cfg.injections.dir = (*sec)["dir"].value_or(cfg.injections.dir);
    }
    if (const auto* sec = tbl["prompt"].as_table()) {
      cfg.prompt.system_file =
          (*sec)["system_file"].value_or(cfg.prompt.system_file);
    }
  }

  // Environment overrides.
  cfg.server.bind = env_or("CHATVV_BIND", cfg.server.bind);
  cfg.server.port = env_int_or("CHATVV_PORT", cfg.server.port);
  cfg.server.api_key = env_or("CHATVV_API_KEY", cfg.server.api_key);
  cfg.llm.provider = env_or("CHATVV_LLM_PROVIDER", cfg.llm.provider);
  cfg.llm.base_url = env_or("CHATVV_LLM_BASE_URL", cfg.llm.base_url);
  cfg.llm.endpoint = env_or("CHATVV_LLM_ENDPOINT", cfg.llm.endpoint);
  cfg.llm.model = env_or("CHATVV_LLM_MODEL", cfg.llm.model);
  cfg.storage.data_dir = env_or("CHATVV_DATA_DIR", cfg.storage.data_dir);
  cfg.injections.dir = env_or("CHATVV_INJECTIONS_DIR", cfg.injections.dir);

  if (cfg.llm.api_key.empty()) {
    cfg.llm.api_key = env_or(cfg.llm.api_key_env.c_str(), "");
  }
  if (cfg.llm.api_key.empty()) {
    cfg.llm.api_key = env_or("CHATVV_LLM_API_KEY", "");
  }

  if (!cfg.prompt.system_file.empty()) {
    cfg.prompt.system_text = read_file(cfg.prompt.system_file);
    if (cfg.prompt.system_text.empty()) {
      log_warn("prompt.system_file_empty",
               {{"path", cfg.prompt.system_file}});
    }
  }
  if (cfg.prompt.system_text.empty()) {
    cfg.prompt.system_text = kDefaultSystem;
  }

  cfg.prompt.system_text = trim(cfg.prompt.system_text);
  return cfg;
}

}  // namespace chatvv
