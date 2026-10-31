#include "llm/mock_provider.h"

#include <chrono>
#include <thread>
#include <vector>

#include "util/ulid.h"
#include "util/util.h"

namespace chatvv {
namespace {

std::string last_user_text(const nlohmann::json& input) {
  if (!input.is_array()) return {};
  for (auto it = input.rbegin(); it != input.rend(); ++it) {
    if (it->value("role", std::string()) != "user") continue;
    std::string out;
    for (const auto& part : it->value("content", nlohmann::json::array())) {
      if (part.value("type", std::string()) == "input_text") {
        out += part.value("text", std::string());
      }
    }
    if (!out.empty()) return out;
  }
  return {};
}

std::vector<std::string> utf8_chunks(const std::string& s, size_t max_chars) {
  std::vector<std::string> out;
  size_t start = 0;
  size_t count = 0;
  for (size_t i = 0; i < s.size(); ++i) {
    if ((static_cast<unsigned char>(s[i]) & 0xC0) == 0x80) continue;
    if (count == max_chars) {
      out.push_back(s.substr(start, i - start));
      start = i;
      count = 0;
    }
    ++count;
  }
  if (start < s.size()) out.push_back(s.substr(start));
  return out;
}

}  // namespace

LlmResult MockProvider::complete(const LlmRequest& req, const EventSink& sink) {
  const std::string rid = "resp_mock_" + ulid();
  const std::string item_id = "msg_mock_" + ulid();

  sink("response.created",
       {{"type", "response.created"},
        {"response",
         {{"id", rid},
          {"object", "response"},
          {"status", "in_progress"},
          {"model", req.model}}}});

  sink("response.output_item.added",
       {{"type", "response.output_item.added"},
        {"output_index", 0},
        {"item",
         {{"id", item_id},
          {"type", "message"},
          {"role", "assistant"},
          {"status", "in_progress"},
          {"content", nlohmann::json::array()}}}});

  const std::string user = last_user_text(req.input);
  const std::string text =
      "（mock）我收到了你的消息" + (user.empty() ? std::string("。") : "：") +
      (user.empty() ? std::string() : user) +
      "\n\n现在走的是本地 mock 流。接上 DeepSeek 后，这里会替换成真实回复。";

  for (const auto& chunk : utf8_chunks(text, 12)) {
    if (req.cancel && req.cancel->load()) {
      LlmResult cancelled;
      cancelled.status = "cancelled";
      cancelled.error = "cancelled";
      return cancelled;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(25));
    sink("response.output_text.delta",
         {{"type", "response.output_text.delta"},
          {"item_id", item_id},
          {"output_index", 0},
          {"content_index", 0},
          {"delta", chunk}});
  }

  sink("response.output_text.done",
       {{"type", "response.output_text.done"},
        {"item_id", item_id},
        {"output_index", 0},
        {"content_index", 0},
        {"text", text}});

  nlohmann::json item = {
      {"id", item_id},
      {"type", "message"},
      {"role", "assistant"},
      {"status", "completed"},
      {"content",
       nlohmann::json::array(
           {{{"type", "output_text"}, {"text", text}}})}};

  sink("response.output_item.done",
       {{"type", "response.output_item.done"},
        {"output_index", 0},
        {"item", item}});

  const int input_tokens = estimate_tokens(req.instructions + req.input.dump());
  const int output_tokens = estimate_tokens(text);
  nlohmann::json usage = {{"input_tokens", input_tokens},
                          {"input_tokens_details", {{"cached_tokens", 0}}},
                          {"output_tokens", output_tokens},
                          {"output_tokens_details", {{"reasoning_tokens", 0}}},
                          {"total_tokens", input_tokens + output_tokens}};

  nlohmann::json response = {{"id", rid},
                             {"object", "response"},
                             {"status", "completed"},
                             {"model", req.model},
                             {"output", nlohmann::json::array({item})},
                             {"usage", usage}};

  sink("response.completed",
       {{"type", "response.completed"}, {"response", response}});

  LlmResult result;
  result.ok = true;
  result.status = "completed";
  result.output = nlohmann::json::array({item});
  result.usage = usage;
  return result;
}

}  // namespace chatvv
