#include "dialog/dialog_service.h"

#include <stdexcept>

#include "app/config.h"
#include "dialog/response_hub.h"
#include "llm/provider.h"
#include "store/db.h"
#include "util/log.h"
#include "util/ulid.h"
#include "util/util.h"

namespace chatvv {
namespace {

bool is_terminal(const std::string& type) {
  return type == "response.completed" || type == "response.incomplete" ||
         type == "response.failed";
}

std::string extract_text(const nlohmann::json& output) {
  std::string out;
  if (!output.is_array()) return out;
  for (const auto& item : output) {
    if (item.value("type", std::string()) != "message") continue;
    for (const auto& part : item.value("content", nlohmann::json::array())) {
      if (part.value("type", std::string()) == "output_text") {
        out += part.value("text", std::string());
      }
    }
  }
  return out;
}

}  // namespace

DialogService::DialogService(const Config& cfg, Db& db, InjectionStore& slots,
                             ResponseHub& hub, Provider& provider)
    : cfg_(cfg), db_(db), slots_(slots), hub_(hub), provider_(provider) {}

DialogService::~DialogService() { shutdown(); }

DialogService::StartResult DialogService::start(
    const std::string& text, const std::vector<Injection>& extra,
    const std::string& instructions_override) {
  BuiltContext ctx = build_context(db_, slots_, cfg_, text, extra);
  if (!instructions_override.empty()) {
    ctx.instructions = instructions_override;
  }

  const std::string id = ulid();
  ResponseRow row;
  row.id = id;
  row.model = cfg_.llm.model;
  row.instructions = ctx.instructions;
  row.input_meta = ctx.manifest.dump();
  row.created_at = now_ms();
  db_.create_response(row);

  std::string rendered;
  if (!ctx.input.empty()) {
    const auto& last = ctx.input.back();
    if (last.contains("content")) rendered = last["content"].dump();
  }
  db_.append_message("user", text, rendered, id);
  // Register before the worker can publish. SSE clients may connect as soon
  // as start() returns; an unknown hub id would otherwise race into
  // stream_lost.
  hub_.open(id);

  auto cancel = std::make_shared<std::atomic<bool>>(false);
  {
    std::lock_guard lock(mu_);
    if (stopping_) throw std::runtime_error("dialog service is shutting down");
    cancels_[id] = cancel;
    threads_.emplace_back(
        [this, id, ctx = std::move(ctx), model = cfg_.llm.model, cancel]() mutable {
          run(std::move(id), std::move(ctx), std::move(model), std::move(cancel));
        });
  }

  log_info("turn.started", {{"response_id", id}, {"chars", text.size()}});
  return {id, "in_progress"};
}

void DialogService::run(std::string id, BuiltContext ctx, std::string model,
                        std::shared_ptr<std::atomic<bool>> cancel) {
  int64_t seq = 0;

  auto emit = [&](const std::string& type, nlohmann::json data) {
    ++seq;
    if (data.contains("response") && data["response"].is_object()) {
      data["response"]["id"] = id;
    }
    const std::string dumped = data.dump();
    try {
      db_.append_event(id, seq, type, dumped);
    } catch (const std::exception& e) {
      log_error("event.persist_failed",
                {{"response_id", id}, {"error", e.what()}});
    }
    hub_.publish(id, seq, type, dumped);
  };

  emit("response.created",
       {{"type", "response.created"},
        {"response",
         {{"id", id},
          {"object", "response"},
          {"status", "in_progress"},
          {"model", model},
          {"created_at", now_ms() / 1000}}}});
  emit("chatvv.context.built",
       {{"type", "chatvv.context.built"},
        {"response_id", id},
        {"manifest", ctx.manifest}});

  LlmRequest req;
  req.model = model;
  req.instructions = ctx.instructions;
  req.input = ctx.input;
  req.tools = ctx.tools;
  req.reasoning_effort = cfg_.llm.reasoning_effort;
  req.max_output_tokens = cfg_.llm.max_output_tokens;
  req.base_url = cfg_.llm.base_url;
  req.endpoint = cfg_.llm.endpoint;
  req.api_key = cfg_.llm.api_key;
  req.ca_bundle = cfg_.llm.ca_bundle;
  req.timeout_ms = cfg_.llm.timeout_ms;
  req.cancel = cancel.get();

  auto sink = [&](const std::string& type, const nlohmann::json& data) {
    if (type == "response.created") return;
    // The provider's terminal event can arrive before the assistant message is
    // persisted. Suppress it here; the final event below is emitted only after
    // the DB write, so history is consistent when the callback observes it.
    if (is_terminal(type)) return;
    emit(type, data);
  };

  const LlmResult result = provider_.complete(req, sink);
  const bool cancelled = cancel->load();

  if (cancelled) {
    db_.update_response(id, "cancelled", "", "", "cancelled", now_ms());
    emit("response.incomplete",
         {{"type", "response.incomplete"},
          {"response",
           {{"id", id},
            {"status", "incomplete"},
            {"incomplete_details", {{"reason", "cancelled"}}}}}});
    log_info("turn.cancelled", {{"response_id", id}});
  } else if (!result.ok) {
    db_.update_response(id, "failed", result.output.dump(),
                        result.usage.dump(), result.error, now_ms());
    emit("response.failed",
         {{"type", "response.failed"},
          {"response",
           {{"id", id},
            {"status", "failed"},
            {"error",
             {{"code", "upstream_error"}, {"message", result.error}}}}}});
    log_error("turn.failed", {{"response_id", id}, {"error", result.error}});
  } else {
    const std::string text = extract_text(result.output);
    if (!text.empty()) {
      db_.append_message("assistant", text, "", id);
    }
    const std::string status =
        result.status == "incomplete" ? "incomplete" : "completed";
    db_.update_response(id, status, result.output.dump(), result.usage.dump(),
                        "", now_ms());
    emit("response.completed",
         {{"type", "response.completed"},
          {"response",
           {{"id", id},
            {"object", "response"},
            {"status", status},
            {"model", model},
            {"output", result.output},
            {"usage", result.usage}}}});
    log_info("turn.completed",
             {{"response_id", id}, {"chars", text.size()}, {"status", status}});
  }

  hub_.finish(id);
  {
    std::lock_guard lock(mu_);
    cancels_.erase(id);
  }
}

bool DialogService::cancel(const std::string& id) {
  std::lock_guard lock(mu_);
  const auto it = cancels_.find(id);
  if (it == cancels_.end()) return false;
  it->second->store(true);
  return true;
}

void DialogService::shutdown() {
  std::vector<std::thread> threads;
  {
    std::lock_guard lock(mu_);
    if (stopping_) return;
    stopping_ = true;
    for (auto& [_, flag] : cancels_) flag->store(true);
    threads = std::move(threads_);
  }
  for (auto& t : threads) {
    if (t.joinable()) t.join();
  }
}

}  // namespace chatvv
