#include "chatvv/chatvv.h"

#include <curl/curl.h>
#include <nlohmann/json.hpp>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "app/config.h"
#include "context/injections.h"
#include "dialog/dialog_service.h"
#include "dialog/response_hub.h"
#include "llm/provider.h"
#include "memory/embedding.h"
#include "store/db.h"
#include "util/log.h"

namespace {

using json = nlohmann::json;

char* dup_string(const std::string& value) {
  auto* out = static_cast<char*>(std::malloc(value.size() + 1));
  if (!out) return nullptr;
  std::memcpy(out, value.data(), value.size());
  out[value.size()] = '\0';
  return out;
}

void set_error(char** error_json, const std::string& code,
               const std::string& message) {
  if (!error_json) return;
  *error_json = dup_string(json{{"code", code}, {"message", message}}.dump());
}

int32_t event_type_for(const std::string& type) {
  if (type == "response.created") return CHATVV_EVENT_STARTED;
  if (type == "response.output_text.delta") return CHATVV_EVENT_DELTA;
  if (type == "response.completed" || type == "response.incomplete") {
    return CHATVV_EVENT_COMPLETED;
  }
  if (type == "response.failed") return CHATVV_EVENT_FAILED;
  if (type == "chatvv.context.built") return CHATVV_EVENT_CONTEXT;
  if (type.rfind("response.", 0) == 0) return CHATVV_EVENT_TOOL;
  return 0;
}

void ensure_curl() {
  static std::once_flag once;
  std::call_once(once, [] { curl_global_init(CURL_GLOBAL_DEFAULT); });
}

void init_logging_once(const std::filesystem::path& data_dir) {
  static std::once_flag once;
  std::call_once(once, [&] {
    chatvv::init_log(chatvv::LogLevel::Info, data_dir / "chatvv.log");
  });
}

bool parse_config(const json& input, chatvv::Config& cfg, std::string& error) {
  if (!input.is_object()) {
    error = "config_json must be a JSON object";
    return false;
  }

  auto string_field = [&](const char* key, std::string& out) {
    const auto it = input.find(key);
    if (it != input.end() && it->is_string()) out = it->get<std::string>();
  };
  auto int_field = [&](const char* key, int& out) {
    const auto it = input.find(key);
    if (it != input.end() && it->is_number_integer()) out = it->get<int>();
  };

  string_field("data_dir", cfg.storage.data_dir);
  string_field("injections_dir", cfg.injections.dir);
  string_field("provider", cfg.llm.provider);
  string_field("base_url", cfg.llm.base_url);
  string_field("endpoint", cfg.llm.endpoint);
  string_field("api_key", cfg.llm.api_key);
  string_field("ca_bundle", cfg.llm.ca_bundle);
  string_field("model", cfg.llm.model);
  string_field("reasoning_effort", cfg.llm.reasoning_effort);
  string_field("system_prompt", cfg.prompt.system_text);
  string_field("embedding_model", cfg.embedding.model);
  int_field("max_output_tokens", cfg.llm.max_output_tokens);
  int_field("embedding_threads", cfg.embedding.threads);
  int_field("timeout_ms", cfg.llm.timeout_ms);

  if (cfg.storage.data_dir.empty()) {
    error = "data_dir is required";
    return false;
  }
  if (cfg.injections.dir.empty()) {
    cfg.injections.dir = (std::filesystem::path(cfg.storage.data_dir) /
                          "injections")
                             .string();
  }
  if (cfg.llm.provider.empty()) cfg.llm.provider = "mock";
  if (cfg.llm.model.empty()) cfg.llm.model = "deepseek-flash";
  if (cfg.llm.max_output_tokens <= 0) cfg.llm.max_output_tokens = 4096;
  if (cfg.llm.timeout_ms <= 0) cfg.llm.timeout_ms = 120000;
  if (cfg.prompt.system_text.empty()) {
    cfg.prompt.system_text = chatvv::Config::default_system_prompt();
  }
  return true;
}

std::vector<chatvv::Injection> parse_injections(const char* injections_json,
                                                 std::string& error) {
  std::vector<chatvv::Injection> out;
  if (!injections_json || !*injections_json) return out;
  try {
    const json input = json::parse(injections_json);
    if (!input.is_array()) {
      error = "injections_json must be an array";
      return out;
    }
    int index = 0;
    for (const auto& item : input) {
      if (!item.is_object()) continue;
      chatvv::Injection inj;
      inj.name = item.value("name", "injection-" + std::to_string(index++));
      inj.position = item.value("position", std::string("before_latest"));
      inj.mode = item.value("mode", std::string("append"));
      inj.trust = item.value("trust", std::string("data"));
      inj.description = item.value("description", std::string());
      inj.body = item.value("content", std::string());
      inj.depth = item.value("depth", 0);
      inj.priority = item.value("priority", 100);
      inj.enabled = item.value("enabled", true) && !inj.body.empty();
      if (!inj.enabled) continue;
      if (inj.position == "at_depth" && (inj.depth < 1 || inj.depth > 64)) {
        continue;
      }
      out.push_back(std::move(inj));
    }
  } catch (const std::exception& e) {
    error = e.what();
  }
  return out;
}

nlohmann::json memory_json(const chatvv::Memory& memory) {
  return {{"id", memory.id},
          {"text", memory.text},
          {"created_at", memory.created_at},
          {"last_used_at", memory.last_used_at},
          {"use_count", memory.use_count},
          {"importance", memory.importance},
          {"durability", memory.durability},
          {"status", memory.status}};
}

}  // namespace

struct chatvv_engine;
struct chatvv_sub;

struct chatvv_sub {
  chatvv_engine* engine = nullptr;
  std::string id;
  chatvv_event_cb callback = nullptr;
  void* user_data = nullptr;
  std::thread thread;
  std::atomic<bool> stop{false};

  void run();
};

struct chatvv_engine {
  chatvv::Config cfg;
  std::unique_ptr<chatvv::Db> db;
  chatvv::InjectionStore injections;
  chatvv::ResponseHub hub;
  std::unique_ptr<chatvv::Provider> provider;
  std::unique_ptr<chatvv::EmbeddingEngine> embedding;
  std::unique_ptr<chatvv::DialogService> dialog;
  std::mutex subs_mu;
  std::vector<std::unique_ptr<chatvv_sub>> subs;
  std::atomic<bool> stopping{false};
};

void chatvv_sub::run() {
  int64_t after_seq = 0;
  while (!stop.load() && !engine->stopping.load()) {
    const auto result = engine->hub.wait(id, after_seq, 200);
    if (!result.found) {
      // The worker may not have published response.created yet. Do not treat
      // "unknown id" as terminal on the first poll.
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      continue;
    }
    for (const auto& event : result.events) {
      after_seq = event.seq;
      if (!callback) continue;
      const int32_t type = event_type_for(event.type);
      if (type == 0) continue;
      char* event_copy = dup_string(event.data);
      if (!event_copy) continue;
      try {
        callback(user_data, type, event_copy);
      } catch (...) {
        // Ownership transferred to the callback only when it returns normally.
        std::free(event_copy);
      }
    }
    if (result.done) break;
  }
}

namespace {

char* start_turn(chatvv_engine* engine, const char* text,
                 std::vector<chatvv::Injection> extra,
                 chatvv_event_cb callback, void* user_data,
                 char** error_json) {
  if (!engine) {
    set_error(error_json, "invalid_argument", "engine is null");
    return nullptr;
  }
  if (!text || !*text) {
    set_error(error_json, "invalid_argument", "text must not be empty");
    return nullptr;
  }
  if (engine->stopping.load()) {
    set_error(error_json, "engine_stopped", "engine is shutting down");
    return nullptr;
  }

  try {
    const auto started = engine->dialog->start(text, std::move(extra));
    auto sub = std::make_unique<chatvv_sub>();
    sub->engine = engine;
    sub->id = started.id;
    sub->callback = callback;
    sub->user_data = user_data;
    chatvv_sub* raw = sub.get();
    {
      std::lock_guard lock(engine->subs_mu);
      engine->subs.push_back(std::move(sub));
    }
    raw->thread = std::thread([raw] { raw->run(); });
    return dup_string(started.id);
  } catch (const std::exception& e) {
    set_error(error_json, "send_failed", e.what());
    return nullptr;
  } catch (...) {
    set_error(error_json, "send_failed", "unknown error");
    return nullptr;
  }
}

}  // namespace

extern "C" {

chatvv_engine* chatvv_create(const char* config_json, char** error_json) {
  if (error_json) *error_json = nullptr;
  if (!config_json) {
    set_error(error_json, "invalid_argument", "config_json is required");
    return nullptr;
  }

  try {
    const json input = json::parse(config_json);
    chatvv::Config cfg;
    std::string config_error;
    if (!parse_config(input, cfg, config_error)) {
      set_error(error_json, "invalid_config", config_error);
      return nullptr;
    }

    std::filesystem::create_directories(cfg.storage.data_dir);
    init_logging_once(cfg.storage.data_dir);
    ensure_curl();

    auto engine = std::make_unique<chatvv_engine>();
    engine->cfg = std::move(cfg);
    engine->db = std::make_unique<chatvv::Db>(engine->cfg.db_path());
    engine->db->migrate();
    engine->injections.load_dir(engine->cfg.injections.dir);
    engine->provider = chatvv::make_provider(engine->cfg);
    if (engine->cfg.embedding.enabled &&
        !engine->cfg.embedding.model.empty()) {
      engine->embedding = std::make_unique<chatvv::EmbeddingEngine>();
      std::string embedding_error;
      if (!engine->embedding->load(engine->cfg.embedding.model,
                                   engine->cfg.embedding.threads,
                                   &embedding_error)) {
        chatvv::log_warn("embedding.load_failed",
                         {{"error", embedding_error}});
        engine->embedding.reset();
      }
    }
    engine->dialog = std::make_unique<chatvv::DialogService>(
        engine->cfg, *engine->db, engine->injections, engine->hub,
        *engine->provider, engine->embedding.get());
    return engine.release();
  } catch (const std::exception& e) {
    set_error(error_json, "create_failed", e.what());
    return nullptr;
  } catch (...) {
    set_error(error_json, "create_failed", "unknown error");
    return nullptr;
  }
}

void chatvv_destroy(chatvv_engine* engine) {
  if (!engine) return;
  engine->stopping.store(true);
  if (engine->dialog) engine->dialog->shutdown();

  std::vector<std::unique_ptr<chatvv_sub>> subs;
  {
    std::lock_guard lock(engine->subs_mu);
    subs.swap(engine->subs);
  }
  for (auto& sub : subs) {
    sub->stop.store(true);
    if (sub->thread.joinable()) sub->thread.join();
  }

  engine->dialog.reset();
  engine->provider.reset();
  engine->db.reset();
  delete engine;
}

char* chatvv_send(chatvv_engine* engine, const char* text,
                  chatvv_event_cb callback, void* user_data,
                  char** error_json) {
  if (error_json) *error_json = nullptr;
  return start_turn(engine, text, {}, callback, user_data, error_json);
}

char* chatvv_send_ex(chatvv_engine* engine, const char* text,
                     const char* injections_json, chatvv_event_cb callback,
                     void* user_data, char** error_json) {
  if (error_json) *error_json = nullptr;
  std::string parse_error;
  auto extra = parse_injections(injections_json, parse_error);
  if (!parse_error.empty()) {
    set_error(error_json, "invalid_injections", parse_error);
    return nullptr;
  }
  return start_turn(engine, text, std::move(extra), callback, user_data,
                    error_json);
}

void chatvv_cancel(chatvv_engine* engine, const char* response_id) {
  if (!engine || !response_id || !*response_id) return;
  try {
    engine->dialog->cancel(response_id);
  } catch (...) {
    // Cancellation is best-effort.
  }
}

char* chatvv_history(chatvv_engine* engine, int32_t limit, int64_t before_seq,
                     char** error_json) {
  if (error_json) *error_json = nullptr;
  if (!engine) {
    set_error(error_json, "invalid_argument", "engine is null");
    return nullptr;
  }
  if (limit <= 0) limit = 30;
  if (limit > 200) limit = 200;

  try {
    bool has_more = false;
    const auto messages =
        engine->db->list_messages(limit, before_seq, 0, &has_more);
    json data = json::array();
    for (const auto& message : messages) {
      data.push_back({{"id", message.id},
                      {"seq", message.seq},
                      {"role", message.role},
                      {"content", message.content},
                      {"created_at", message.created_at},
                      {"response_id", message.response_id}});
    }
    return dup_string(
        json{{"data", std::move(data)}, {"has_more", has_more}}.dump());
  } catch (const std::exception& e) {
    set_error(error_json, "history_failed", e.what());
    return nullptr;
  }
}

char* chatvv_capabilities(chatvv_engine* engine, char** error_json) {
  if (error_json) *error_json = nullptr;
  if (!engine) {
    set_error(error_json, "invalid_argument", "engine is null");
    return nullptr;
  }
  return dup_string(json{{"ffi_abi", 1},
                         {"version", "0.1.0"},
                         {"provider", engine->cfg.llm.provider},
                         {"model", engine->cfg.llm.model},
                         {"streaming", true},
                         {"cancel", true}}
                        .dump());
}

char* chatvv_memories(chatvv_engine* engine, int32_t limit,
                       const char* query, char** error_json) {
  if (error_json) *error_json = nullptr;
  if (!engine) {
    set_error(error_json, "invalid_argument", "engine is null");
    return nullptr;
  }
  try {
    json data = json::array();
    for (const auto& memory :
         engine->db->list_memories(limit, query ? query : "")) {
      data.push_back(memory_json(memory));
    }
    return dup_string(json{{"data", std::move(data)}}.dump());
  } catch (const std::exception& e) {
    set_error(error_json, "memories_failed", e.what());
    return nullptr;
  }
}

char* chatvv_archive(chatvv_engine* engine, int32_t keep_recent,
                     char** error_json) {
  if (error_json) *error_json = nullptr;
  if (!engine) {
    set_error(error_json, "invalid_argument", "engine is null");
    return nullptr;
  }
  try {
    const auto archived =
        engine->db->archive_messages(keep_recent > 0 ? keep_recent : 20);
    json payload{{"archived_messages", archived.archived_messages},
                 {"cutoff_seq", archived.cutoff_seq},
                 {"memory", nullptr}};
    if (archived.archived_messages > 0) {
      if (engine->embedding && engine->embedding->ready()) {
        const auto values = engine->embedding->embed(archived.memory.text);
        if (!values.empty()) {
          engine->db->set_memory_embedding(archived.memory.id, values);
        }
      }
      payload["memory"] = memory_json(archived.memory);
    }
    return dup_string(payload.dump());
  } catch (const std::exception& e) {
    set_error(error_json, "archive_failed", e.what());
    return nullptr;
  }
}

int32_t chatvv_delete_memory(chatvv_engine* engine, const char* memory_id) {
  if (!engine || !memory_id || !*memory_id) return 0;
  try {
    return engine->db->delete_memory(memory_id) ? 1 : 0;
  } catch (...) {
    return 0;
  }
}

char* chatvv_save_context(chatvv_engine* engine, char** error_json) {
  if (error_json) *error_json = nullptr;
  if (!engine) {
    set_error(error_json, "invalid_argument", "engine is null");
    return nullptr;
  }
  try {
    auto archived = engine->db->archive_messages(0);
    if (archived.archived_messages > 0 && engine->embedding &&
        engine->embedding->ready()) {
      const auto values = engine->embedding->embed(archived.memory.text);
      if (!values.empty()) {
        engine->db->set_memory_embedding(archived.memory.id, values);
      }
    }
    engine->db->clear_context();
    json payload{{"archived_messages", archived.archived_messages},
                 {"memory", nullptr}};
    if (archived.archived_messages > 0) {
      payload["memory"] = memory_json(archived.memory);
    }
    return dup_string(payload.dump());
  } catch (const std::exception& e) {
    set_error(error_json, "save_context_failed", e.what());
    return nullptr;
  }
}

int32_t chatvv_clear_context(chatvv_engine* engine, char** error_json) {
  if (error_json) *error_json = nullptr;
  if (!engine) return 0;
  try {
    engine->db->clear_context();
    return 1;
  } catch (const std::exception& e) {
    set_error(error_json, "clear_context_failed", e.what());
    return 0;
  }
}

void chatvv_free(char* value) { std::free(value); }

}  // extern "C"
