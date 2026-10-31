#pragma once

#include <string>

namespace chatvv {

struct Config {
  struct Server {
    std::string bind = "127.0.0.1";
    int port = 8080;
    std::string api_key;
    std::string cors_origin = "*";
  } server;

  struct Llm {
    std::string provider = "mock";  // mock | deepseek
    std::string base_url = "https://api.deepseek.com";
    std::string endpoint = "/responses";
    std::string api_key;
    std::string ca_bundle;
    std::string api_key_env = "DEEPSEEK_API_KEY";
    std::string model = "deepseek-flash";
    std::string reasoning_effort = "none";
    int max_output_tokens = 4096;
    int timeout_ms = 120000;
  } llm;

  struct Storage {
    std::string data_dir = "./data";
  } storage;

  struct Injections {
    std::string dir = "./config/injections";
  } injections;

  struct Prompt {
    std::string system_file;
    std::string system_text;
  } prompt;

  static Config load(const std::string& path);
  static std::string default_system_prompt();

  std::string db_path() const;
};

}  // namespace chatvv
