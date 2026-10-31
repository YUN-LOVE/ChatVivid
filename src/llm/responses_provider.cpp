#include "llm/responses_provider.h"

#include <curl/curl.h>

#include <mutex>

#include "app/config.h"
#include "util/log.h"
#include "util/util.h"

namespace chatvv {
namespace {

struct StreamState {
  std::string buffer;
  std::string event;
  std::string data;
  std::string text;
  std::string error;
  nlohmann::json final_response = nlohmann::json::object();
  bool saw_final = false;
  const EventSink* sink = nullptr;
  std::atomic<bool>* cancel = nullptr;
};

struct Slist {
  curl_slist* list = nullptr;
  ~Slist() {
    if (list) curl_slist_free_all(list);
  }
  void add(const std::string& value) {
    list = curl_slist_append(list, value.c_str());
  }
};

struct CurlHandle {
  CURL* handle = nullptr;
  CurlHandle() { handle = curl_easy_init(); }
  ~CurlHandle() {
    if (handle) curl_easy_cleanup(handle);
  }
};

void dispatch(StreamState& st) {
  if (st.data.empty()) {
    st.event.clear();
    return;
  }
  std::string payload = st.data;
  st.data.clear();
  st.event.clear();

  if (payload == "[DONE]") return;

  nlohmann::json j;
  try {
    j = nlohmann::json::parse(payload);
  } catch (...) {
    return;
  }

  const std::string type = j.value("type", std::string());
  if (type == "response.completed" || type == "response.incomplete" ||
      type == "response.failed") {
    st.saw_final = true;
    st.final_response = j.value("response", nlohmann::json::object());
  }
  if (type == "response.output_text.delta") {
    st.text += j.value("delta", std::string());
  }
  if (st.sink && *st.sink) {
    try {
      (*st.sink)(type, j);
    } catch (const std::exception& e) {
      st.error = std::string("event sink failed: ") + e.what();
    }
  }
}

size_t on_write(char* ptr, size_t size, size_t nmemb, void* userdata) {
  auto* st = static_cast<StreamState*>(userdata);
  const size_t bytes = size * nmemb;
  st->buffer.append(ptr, bytes);

  size_t pos = 0;
  while ((pos = st->buffer.find('\n')) != std::string::npos) {
    std::string line = st->buffer.substr(0, pos);
    st->buffer.erase(0, pos + 1);
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (line.empty()) {
      dispatch(*st);
      continue;
    }
    if (line[0] == ':') continue;
    if (starts_with(line, "event:")) {
      st->event = trim(line.substr(6));
    } else if (starts_with(line, "data:")) {
      std::string d = line.substr(5);
      if (!d.empty() && d.front() == ' ') d.erase(0, 1);
      if (!st->data.empty()) st->data += '\n';
      st->data += d;
    }
  }
  return bytes;
}

int on_progress(void* userdata, curl_off_t, curl_off_t, curl_off_t, curl_off_t) {
  auto* st = static_cast<StreamState*>(userdata);
  return (st->cancel && st->cancel->load()) ? 1 : 0;
}

std::string join_url(std::string base, std::string endpoint) {
  while (!base.empty() && base.back() == '/') base.pop_back();
  if (!endpoint.empty() && endpoint.front() != '/') endpoint.insert(0, "/");
  return base + endpoint;
}


}  // namespace

ResponsesProvider::ResponsesProvider(const Config& cfg)
    : default_base_url_(cfg.llm.base_url),
      default_endpoint_(cfg.llm.endpoint),
      default_api_key_(cfg.llm.api_key),
      default_timeout_ms_(cfg.llm.timeout_ms) {
  static std::once_flag once;
  std::call_once(once, [] { curl_global_init(CURL_GLOBAL_DEFAULT); });
}

LlmResult ResponsesProvider::complete(const LlmRequest& req,
                                      const EventSink& sink) {
  LlmResult result;
  const std::string base = req.base_url.empty() ? default_base_url_ : req.base_url;
  const std::string endpoint =
      req.endpoint.empty() ? default_endpoint_ : req.endpoint;
  const std::string api_key =
      req.api_key.empty() ? default_api_key_ : req.api_key;
  const std::string url = join_url(base, endpoint);

  if (api_key.empty()) {
    result.error =
        "missing API key: set llm.api_key or DEEPSEEK_API_KEY, or use provider=mock";
    return result;
  }

  nlohmann::json body = {{"model", req.model},
                         {"instructions", req.instructions},
                         {"input", req.input},
                         {"stream", true},
                         {"store", false},
                         {"max_output_tokens", req.max_output_tokens}};
  if (!req.tools.empty()) body["tools"] = req.tools;
  if (!req.reasoning_effort.empty()) {
    body["reasoning"] = {{"effort", req.reasoning_effort}};
  }
  const std::string payload = body.dump();

  StreamState st;
  st.sink = &sink;
  st.cancel = req.cancel;

  Slist headers;
  headers.add("Content-Type: application/json");
  headers.add("Accept: text/event-stream");
  headers.add("Authorization: Bearer " + api_key);

  CurlHandle curl;
  if (!curl.handle) {
    result.error = "curl_easy_init failed";
    return result;
  }

  curl_easy_setopt(curl.handle, CURLOPT_URL, url.c_str());
  curl_easy_setopt(curl.handle, CURLOPT_POST, 1L);
  curl_easy_setopt(curl.handle, CURLOPT_POSTFIELDS, payload.c_str());
  curl_easy_setopt(curl.handle, CURLOPT_POSTFIELDSIZE_LARGE,
                   static_cast<curl_off_t>(payload.size()));
  curl_easy_setopt(curl.handle, CURLOPT_HTTPHEADER, headers.list);
  curl_easy_setopt(curl.handle, CURLOPT_WRITEFUNCTION, on_write);
  curl_easy_setopt(curl.handle, CURLOPT_WRITEDATA, &st);
  if (!req.ca_bundle.empty()) {
    curl_easy_setopt(curl.handle, CURLOPT_CAINFO, req.ca_bundle.c_str());
  }
  curl_easy_setopt(curl.handle, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(curl.handle, CURLOPT_CONNECTTIMEOUT_MS, 10000L);
  curl_easy_setopt(curl.handle, CURLOPT_TIMEOUT_MS,
                   static_cast<long>(req.timeout_ms > 0 ? req.timeout_ms
                                                        : default_timeout_ms_));
  curl_easy_setopt(curl.handle, CURLOPT_NOPROGRESS, 0L);
  curl_easy_setopt(curl.handle, CURLOPT_XFERINFOFUNCTION, on_progress);
  curl_easy_setopt(curl.handle, CURLOPT_XFERINFODATA, &st);
  curl_easy_setopt(curl.handle, CURLOPT_TCP_KEEPALIVE, 1L);

  const CURLcode rc = curl_easy_perform(curl.handle);

  long http_code = 0;
  curl_easy_getinfo(curl.handle, CURLINFO_RESPONSE_CODE, &http_code);

  const bool cancelled = req.cancel && req.cancel->load();
  if (cancelled) {
    result.status = "cancelled";
    result.error = "cancelled";
    return result;
  }

  if (rc != CURLE_OK) {
    result.error = std::string("curl: ") + curl_easy_strerror(rc);
    if (!st.buffer.empty()) result.error += " | " + st.buffer.substr(0, 300);
    return result;
  }
  if (http_code >= 400) {
    result.error = "HTTP " + std::to_string(http_code) + ": " +
                   st.buffer.substr(0, 500);
    return result;
  }

  if (st.saw_final) {
    result.status =
        st.final_response.value("status", std::string("completed"));
    result.output =
        st.final_response.value("output", nlohmann::json::array());
    if (!result.output.is_array()) result.output = nlohmann::json::array();
    result.usage = st.final_response.value("usage", nlohmann::json::object());
    if (result.status == "failed") {
      result.error = st.final_response.value("error", nlohmann::json::object())
                         .value("message", std::string("upstream failed"));
      return result;
    }
    result.ok = true;
    return result;
  }

  // No terminal event: salvage whatever text arrived.
  if (!st.text.empty()) {
    const std::string item_id = "msg_salvaged";
    nlohmann::json item = {
        {"id", item_id},
        {"type", "message"},
        {"role", "assistant"},
        {"status", "complete"},
        {"content",
         nlohmann::json::array(
             {{{"type", "output_text"}, {"text", st.text}}})}};
    result.ok = true;
    result.status = "incomplete";
    result.output = nlohmann::json::array({item});
    return result;
  }

  result.error = st.error.empty() ? "stream ended without a terminal event"
                                  : st.error;
  return result;
}

}  // namespace chatvv
