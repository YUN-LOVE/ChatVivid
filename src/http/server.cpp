#include "http/server.h"

#include "memory/embedding.h"

#include <httplib.h>

#include <chrono>
#include <exception>
#include <thread>

#include "app/config.h"
#include "context/context_builder.h"
#include "dialog/dialog_service.h"
#include "dialog/response_hub.h"
#include "store/db.h"
#include "util/log.h"
#include "util/ulid.h"
#include "util/util.h"

namespace chatvv {
namespace {

struct SseState {
  std::string id;
  int64_t last_seq = 0;
  bool replayed = false;
  bool terminal = false;
  bool closed = false;
  std::vector<StoredEvent> replay;
};

bool write_event(httplib::DataSink& sink, int64_t seq, const std::string& type,
                 const std::string& data) {
  std::string out;
  out.reserve(type.size() + data.size() + 64);
  out += "id: ";
  out += std::to_string(seq);
  out += "\nevent: ";
  out += type;
  out += "\ndata: ";
  out += data;
  out += "\n\n";
  return sink.write(out.data(), out.size());
}

bool terminal_status(const std::string& s) {
  return s == "completed" || s == "incomplete" || s == "failed" ||
         s == "cancelled";
}

nlohmann::json parse_json(const std::string& text, bool array) {
  if (!text.empty()) {
    try {
      auto j = nlohmann::json::parse(text);
      if (array ? j.is_array() : j.is_object()) return j;
    } catch (...) {
    }
  }
  return array ? nlohmann::json::array() : nlohmann::json::object();
}

nlohmann::json response_json(const ResponseRow& r) {
  nlohmann::json out = {{"id", r.id},
                        {"object", "response"},
                        {"status", r.status},
                        {"model", r.model},
                        {"created_at", r.created_at / 1000},
                        {"output", parse_json(r.output, true)},
                        {"usage", parse_json(r.usage, false)}};
  if (r.completed_at > 0) out["completed_at"] = r.completed_at / 1000;
  if (!r.error.empty()) {
    out["error"] = {{"code", "error"}, {"message", r.error}};
  }
  return out;
}

int64_t parse_i64(const std::string& s, int64_t fallback) {
  if (s.empty()) return fallback;
  try {
    return std::stoll(s);
  } catch (...) {
    return fallback;
  }
}

std::string etag_for(int64_t server_seq, size_t count) {
  return "W/\"" + std::to_string(server_seq) + "-" + std::to_string(count) +
         "\"";
}

}  // namespace

HttpServer::HttpServer(const Config& cfg, Db& db, InjectionStore& slots,
                       ResponseHub& hub, DialogService& dialog,
                       EmbeddingEngine* embedding)
    : cfg_(cfg),
      db_(db),
      slots_(slots),
      hub_(hub),
      dialog_(dialog),
      embedding_(embedding) {
  setup_routes();
}

HttpServer::~HttpServer() { stop(); }

void HttpServer::add_cors(httplib::Response& res) const {
  res.set_header("Access-Control-Allow-Origin", cfg_.server.cors_origin);
  res.set_header("Access-Control-Expose-Headers", "X-Server-Seq, ETag");
}

namespace {

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

void HttpServer::json_response(httplib::Response& res,
                               const nlohmann::json& body, int status) const {
  res.status = status;
  res.set_content(body.dump(), "application/json; charset=utf-8");
  add_cors(res);
}

void HttpServer::error_response(httplib::Response& res, int status,
                                const std::string& code,
                                const std::string& message) const {
  nlohmann::json body = {{"error", {{"code", code}, {"message", message}}},
                         {"request_id", ulid()}};
  json_response(res, body, status);
}

bool HttpServer::authorized(const httplib::Request& req,
                            httplib::Response& res) const {
  if (cfg_.server.api_key.empty()) return true;
  if (req.get_header_value("Authorization") ==
      "Bearer " + cfg_.server.api_key) {
    return true;
  }
  error_response(res, 401, "unauthorized",
                 "missing or invalid bearer token");
  return false;
}

std::vector<Injection> HttpServer::parse_injections(
    const nlohmann::json& arr) const {
  std::vector<Injection> out;
  if (!arr.is_array()) return out;
  int index = 0;
  for (const auto& item : arr) {
    if (!item.is_object()) continue;
    Injection inj;
    inj.name = "api-" + std::to_string(index++);
    inj.position = item.value("position", std::string("before_latest"));
    inj.mode = item.value("mode", std::string("append"));
    inj.body = item.value("content", std::string());
    inj.trust = item.value("trust", std::string("data"));
    inj.description = item.value("description", std::string());
    inj.priority = item.value("priority", 100);
    inj.depth = item.value("depth", 0);
    inj.enabled = !inj.body.empty();
    if (!inj.enabled) continue;
    if (inj.position == "at_depth") {
      if (inj.depth < 1 || inj.depth > 64) continue;
    } else {
      inj.depth = 0;
    }
    out.push_back(std::move(inj));
  }
  return out;
}

void HttpServer::stream_events(httplib::Response& res, const std::string& id,
                               int64_t after) {
  const std::string status = db_.response_status(id);
  if (status.empty()) {
    error_response(res, 404, "not_found", "response not found");
    return;
  }
  if (after < 0) after = 0;

  auto state = std::make_shared<SseState>();
  state->id = id;
  state->last_seq = after;
  state->replay = db_.list_events(id, after);
  state->terminal = terminal_status(status);

  res.set_header("Cache-Control", "no-cache, no-transform");
  res.set_header("X-Accel-Buffering", "no");
  add_cors(res);

  res.set_chunked_content_provider(
      "text/event-stream", [this, state](size_t, httplib::DataSink& sink) {
        if (state->closed) return false;

        if (!state->replayed) {
          for (const auto& event : state->replay) {
            if (!write_event(sink, event.seq, event.type, event.data)) {
              state->closed = true;
              return false;
            }
            state->last_seq = event.seq;
          }
          state->replayed = true;
          if (state->terminal) {
            sink.done();
            state->closed = true;
            return false;
          }
        }

        const WaitResult w = hub_.wait(state->id, state->last_seq, 15000);
        if (!w.found) {
          db_.update_response(state->id, "failed", "", "", "stream_lost",
                              now_ms());
          const nlohmann::json data = {
              {"type", "response.failed"},
              {"response",
               {{"id", state->id},
                {"status", "failed"},
                {"error",
                 {{"code", "stream_lost"},
                  {"message",
                   "this response is no longer active in the current process"}}}}}};
          write_event(sink, state->last_seq + 1, "response.failed",
                      data.dump());
          sink.done();
          state->closed = true;
          return false;
        }

        for (const auto& event : w.events) {
          if (!write_event(sink, event.seq, event.type, event.data)) {
            state->closed = true;
            return false;
          }
          state->last_seq = event.seq;
        }

        if (w.done) {
          sink.done();
          state->closed = true;
          return false;
        }
        if (w.events.empty()) {
          static constexpr char kPing[] = ": ping\n\n";
          if (!sink.write(kPing, sizeof(kPing) - 1)) {
            state->closed = true;
            return false;
          }
        }
        return sink.is_writable();
      });
}

void HttpServer::setup_routes() {
  svr_ = std::make_unique<httplib::Server>();
  svr_->set_payload_max_length(8 * 1024 * 1024);
  svr_->set_read_timeout(30, 0);
  svr_->set_write_timeout(60, 0);

  svr_->set_exception_handler(
      [](const httplib::Request&, httplib::Response& res,
         std::exception_ptr ep) {
        std::string message = "internal error";
        try {
          if (ep) std::rethrow_exception(ep);
        } catch (const std::exception& e) {
          message = e.what();
        } catch (...) {
        }
        res.status = 500;
        res.set_content(
            nlohmann::json{{"error",
                            {{"code", "internal"}, {"message", message}}}}
                .dump(),
            "application/json; charset=utf-8");
      });

  svr_->Get("/healthz", [](const httplib::Request&, httplib::Response& res) {
    res.set_content(nlohmann::json{{"ok", true}}.dump(),
                    "application/json; charset=utf-8");
  });

  svr_->Get("/readyz", [this](const httplib::Request&, httplib::Response& res) {
    const bool needs_key = cfg_.llm.provider == "deepseek" ||
                           cfg_.llm.provider == "responses" ||
                           cfg_.llm.provider == "openai";
    if (needs_key && cfg_.llm.api_key.empty()) {
      error_response(res, 503, "missing_api_key",
                     "llm provider requires an API key");
      return;
    }
    try {
      const int64_t seq = db_.max_seq();
      json_response(res, {{"ok", true},
                          {"message_seq", seq},
                          {"provider", cfg_.llm.provider}});
    } catch (const std::exception& e) {
      error_response(res, 503, "not_ready", e.what());
    }
  });

  svr_->Get("/v1/capabilities",
            [this](const httplib::Request&, httplib::Response& res) {
              json_response(
                  res,
                  {{"version", "0.1.0"},
                   {"features",
                    {{"chat", true},
                     {"streaming", true},
                     {"injections", true},
                     {"responses_api", true},
                     {"memory", true},
                     {"scheduler", false},
                     {"client_sync", true}}},
                   {"models",
                    nlohmann::json::array(
                        {{{"id", cfg_.llm.model},
                          {"provider", cfg_.llm.provider},
                          {"tools", false}}})},
                   {"limits",
                    {{"max_history_messages", 500},
                     {"max_payload_mb", 8}}}});
            });

  svr_->Get("/v1/injections",
            [this](const httplib::Request& req, httplib::Response& res) {
              if (!authorized(req, res)) return;
              json_response(res, slots_.to_json());
            });

  svr_->Get("/v1/memories",
            [this](const httplib::Request& req, httplib::Response& res) {
              if (!authorized(req, res)) return;
              int limit =
                  static_cast<int>(parse_i64(req.get_param_value("limit"), 50));
              if (limit < 1) limit = 1;
              if (limit > 200) limit = 200;
              const std::string query = req.get_param_value("query");
              nlohmann::json data = nlohmann::json::array();
              for (const auto& memory : db_.list_memories(limit, query)) {
                data.push_back(memory_json(memory));
              }
              json_response(res, {{"data", data}});
            });

  svr_->Post("/v1/memories/archive",
             [this](const httplib::Request& req, httplib::Response& res) {
               if (!authorized(req, res)) return;
               int keep_recent = 20;
               try {
                 const auto body = nlohmann::json::parse(req.body);
                 keep_recent = body.value("keep_recent", 20);
               } catch (...) {
               }
               try {
                 auto archived = db_.archive_messages(keep_recent);
                 nlohmann::json memories = nlohmann::json::array();
                 for (const auto& memory : archived.memories) {
                   if (embedding_ && embedding_->ready()) {
                     const auto values = embedding_->embed(memory.text);
                     if (!values.empty()) {
                       db_.set_memory_embedding(memory.id, values);
                     }
                   }
                   memories.push_back(memory_json(memory));
                 }
                 nlohmann::json payload{
                     {"archived_messages", archived.archived_messages},
                     {"cutoff_seq", archived.cutoff_seq},
                     {"memories", std::move(memories)},
                     {"memory", nullptr}};
                 if (!archived.memories.empty()) {
                   payload["memory"] = memory_json(archived.memories.front());
                 }
                 json_response(res, payload);
               } catch (const std::exception& e) {
                 error_response(res, 500, "archive_failed", e.what());
               }
             });

  svr_->Post("/v1/context/save",
             [this](const httplib::Request& req, httplib::Response& res) {
               if (!authorized(req, res)) return;
               try {
                 auto archived = db_.archive_messages(0);
                 nlohmann::json memories = nlohmann::json::array();
                 for (const auto& memory : archived.memories) {
                   if (embedding_ && embedding_->ready()) {
                     const auto values = embedding_->embed(memory.text);
                     if (!values.empty()) {
                       db_.set_memory_embedding(memory.id, values);
                     }
                   }
                   memories.push_back(memory_json(memory));
                 }
                 db_.clear_context();
                 nlohmann::json payload{
                     {"archived_messages", archived.archived_messages},
                     {"memories", std::move(memories)},
                     {"memory", nullptr}};
                 if (!archived.memories.empty()) {
                   payload["memory"] = memory_json(archived.memories.front());
                 }
                 json_response(res, payload);
               } catch (const std::exception& e) {
                 error_response(res, 500, "save_context_failed", e.what());
               }
             });

  svr_->Post("/v1/context/clear",
             [this](const httplib::Request& req, httplib::Response& res) {
               if (!authorized(req, res)) return;
               try {
                 db_.clear_context();
                 json_response(res, {{"ok", true}});
               } catch (const std::exception& e) {
                 error_response(res, 500, "clear_context_failed", e.what());
               }
             });

  svr_->Delete(R"(/v1/memories/([^/]+))",
               [this](const httplib::Request& req, httplib::Response& res) {
                 if (!authorized(req, res)) return;
                 const std::string id = req.matches[1];
                 if (!db_.delete_memory(id)) {
                   error_response(res, 404, "not_found", "memory not found");
                   return;
                 }
                 res.status = 204;
                 add_cors(res);
               });

  svr_->Get("/v1/messages",
            [this](const httplib::Request& req, httplib::Response& res) {
              if (!authorized(req, res)) return;
              int limit =
                  static_cast<int>(parse_i64(req.get_param_value("limit"), 50));
              if (limit < 1) limit = 1;
              if (limit > 200) limit = 200;
              const int64_t before =
                  parse_i64(req.get_param_value("before_seq"), 0);
              const int64_t after =
                  parse_i64(req.get_param_value("after_seq"), 0);

              bool has_more = false;
              const auto messages = db_.list_messages(limit, before, after,
                                                      &has_more);
              nlohmann::json data = nlohmann::json::array();
              for (const auto& m : messages) {
                data.push_back({{"id", m.id},
                                {"seq", m.seq},
                                {"role", m.role},
                                {"content", m.content},
                                {"created_at", m.created_at},
                                {"response_id", m.response_id}});
              }
              const int64_t server_seq = db_.max_seq();
              const std::string etag = etag_for(server_seq, messages.size());
              res.set_header("ETag", etag);
              res.set_header("X-Server-Seq", std::to_string(server_seq));
              res.set_header("Cache-Control", "no-cache");

              if (req.get_header_value("If-None-Match") == etag) {
                res.status = 304;
                add_cors(res);
                return;
              }
              json_response(res, {{"data", data},
                                  {"has_more", has_more},
                                  {"server_seq", server_seq}});
            });

  svr_->Get("/v1/messages/changes",
            [this](const httplib::Request& req, httplib::Response& res) {
              if (!authorized(req, res)) return;
              const int64_t since =
                  parse_i64(req.get_param_value("since_seq"), 0);
              int limit =
                  static_cast<int>(parse_i64(req.get_param_value("limit"), 200));
              if (limit < 1) limit = 1;
              if (limit > 500) limit = 500;

              bool has_more = false;
              const auto messages =
                  db_.list_messages(limit, 0, since, &has_more);
              nlohmann::json data = nlohmann::json::array();
              for (const auto& m : messages) {
                data.push_back({{"id", m.id},
                                {"seq", m.seq},
                                {"role", m.role},
                                {"content", m.content},
                                {"created_at", m.created_at},
                                {"response_id", m.response_id}});
              }
              const int64_t server_seq = db_.max_seq();
              const std::string etag = etag_for(server_seq, messages.size());
              res.set_header("ETag", etag);
              res.set_header("X-Server-Seq", std::to_string(server_seq));
              res.set_header("Cache-Control", "no-cache");
              if (req.get_header_value("If-None-Match") == etag) {
                res.status = 304;
                add_cors(res);
                return;
              }
              json_response(res, {{"data", data},
                                  {"deleted", nlohmann::json::array()},
                                  {"has_more", has_more},
                                  {"server_seq", server_seq}});
            });

  svr_->Post("/v1/context/preview",
             [this](const httplib::Request& req, httplib::Response& res) {
               if (!authorized(req, res)) return;
               nlohmann::json body;
               try {
                 body = nlohmann::json::parse(req.body);
               } catch (...) {
                 error_response(res, 400, "invalid_json", "body is not JSON");
                 return;
               }
               const std::string text = body.value("message", std::string());
               if (text.empty()) {
                 error_response(res, 400, "message_required",
                                "message must not be empty");
                 return;
               }
               const auto extra = parse_injections(
                   body.value("injections", nlohmann::json::array()));
               auto ctx = build_context(db_, slots_, cfg_, text, extra, embedding_);
               json_response(res, {{"instructions", ctx.instructions},
                                   {"input", ctx.input},
                                   {"tools", ctx.tools},
                                   {"manifest", ctx.manifest}});
             });

  svr_->Post("/v1/turns",
             [this](const httplib::Request& req, httplib::Response& res) {
               if (!authorized(req, res)) return;
               nlohmann::json body;
               try {
                 body = nlohmann::json::parse(req.body);
               } catch (...) {
                 error_response(res, 400, "invalid_json", "body is not JSON");
                 return;
               }
               const std::string text = body.value("message", std::string());
               if (text.empty()) {
                 error_response(res, 400, "message_required",
                                "message must not be empty");
                 return;
               }
               const auto extra = parse_injections(
                   body.value("injections", nlohmann::json::array()));
               const auto started = dialog_.start(text, extra);
               if (body.value("stream", true)) {
                 stream_events(res, started.id, 0);
                 return;
               }
               json_response(res,
                             {{"id", started.id},
                              {"object", "response"},
                              {"status", started.status},
                              {"events_url",
                               "/v1/responses/" + started.id + "/events"}},
                             202);
             });

  svr_->Post("/v1/responses",
             [this](const httplib::Request& req, httplib::Response& res) {
               if (!authorized(req, res)) return;
               nlohmann::json body;
               try {
                 body = nlohmann::json::parse(req.body);
               } catch (...) {
                 error_response(res, 400, "invalid_json", "body is not JSON");
                 return;
               }
               if (body.contains("previous_response_id")) {
                 error_response(res, 400, "unsupported_parameter",
                                "previous_response_id is not supported yet; "
                                "send the full input");
                 return;
               }

               std::string text;
               const auto& input = body["input"];
               if (input.is_string()) {
                 text = input.get<std::string>();
               } else if (input.is_array()) {
                 for (const auto& item : input) {
                   if (!item.is_object()) continue;
                   if (item.value("type", std::string()) != "message") continue;
                   if (item.value("role", std::string()) != "user") continue;
                   const auto& content = item["content"];
                   if (content.is_string()) {
                     text += content.get<std::string>();
                   } else if (content.is_array()) {
                     for (const auto& part : content) {
                       if (part.is_string()) {
                         text += part.get<std::string>();
                       } else if (part.is_object()) {
                         const auto type =
                             part.value("type", std::string());
                         if (type == "input_text" || type == "output_text" ||
                             type == "text") {
                           text += part.value("text", std::string());
                         }
                       }
                     }
                   }
                 }
               }
               if (text.empty()) {
                 error_response(res, 400, "input_required",
                                "input must contain a user message");
                 return;
               }

               const std::string instructions =
                   body.value("instructions", std::string());
               const auto started =
                   dialog_.start(text, {}, instructions);
               if (body.value("stream", false)) {
                 stream_events(res, started.id, 0);
                 return;
               }

               for (int i = 0; i < 2400; ++i) {
                 const auto row = db_.get_response(started.id);
                 if (row && terminal_status(row->status)) {
                   json_response(res, response_json(*row));
                   return;
                 }
                 std::this_thread::sleep_for(std::chrono::milliseconds(50));
               }
               error_response(res, 504, "timeout",
                              "response did not finish in 120s");
             });

  svr_->Get(R"(/v1/responses/([0-9A-Za-z_\-]+))",
            [this](const httplib::Request& req, httplib::Response& res) {
              if (!authorized(req, res)) return;
              const std::string id = req.matches[1].str();
              const auto row = db_.get_response(id);
              if (!row) {
                error_response(res, 404, "not_found", "response not found");
                return;
              }
              json_response(res, response_json(*row));
            });

  svr_->Get(R"(/v1/responses/([0-9A-Za-z_\-]+)/events)",
            [this](const httplib::Request& req, httplib::Response& res) {
              if (!authorized(req, res)) return;
              const std::string id = req.matches[1].str();
              int64_t after = parse_i64(req.get_param_value("after"), 0);
              if (after == 0) {
                after = parse_i64(req.get_header_value("Last-Event-ID"), 0);
              }
              stream_events(res, id, after);
            });

  svr_->Post(R"(/v1/responses/([0-9A-Za-z_\-]+)/cancel)",
             [this](const httplib::Request& req, httplib::Response& res) {
               if (!authorized(req, res)) return;
               const std::string id = req.matches[1].str();
               if (dialog_.cancel(id)) {
                 json_response(res, {{"id", id}, {"status", "cancelling"}},
                               202);
                 return;
               }
               const auto row = db_.get_response(id);
               if (!row) {
                 error_response(res, 404, "not_found", "response not found");
                 return;
               }
               if (terminal_status(row->status)) {
                 error_response(res, 409, "already_finished",
                                "response is already " + row->status);
                 return;
               }
               error_response(res, 409, "not_cancellable",
                              "response is not active");
             });

  svr_->Options(R"(.*)",
                [this](const httplib::Request&, httplib::Response& res) {
                  add_cors(res);
                  res.set_header("Access-Control-Allow-Methods",
                                 "GET, POST, OPTIONS");
                  res.set_header(
                      "Access-Control-Allow-Headers",
                      "Authorization, Content-Type, Last-Event-ID, "
                      "If-None-Match, Idempotency-Key");
                  res.set_header("Access-Control-Max-Age", "600");
                  res.status = 204;
                });

  svr_->set_error_handler(
      [this](const httplib::Request&, httplib::Response& res) {
        if (res.status == 404) {
          nlohmann::json body = {
              {"error", {{"code", "not_found"}, {"message", "no such route"}}},
              {"request_id", ulid()}};
          res.set_content(body.dump(), "application/json; charset=utf-8");
          add_cors(res);
        }
      });
}

bool HttpServer::listen() {
  log_info("server.listen",
           {{"bind", cfg_.server.bind}, {"port", cfg_.server.port}});
  return svr_->listen(cfg_.server.bind, cfg_.server.port);
}

void HttpServer::stop() {
  if (svr_) svr_->stop();
}

}  // namespace chatvv
