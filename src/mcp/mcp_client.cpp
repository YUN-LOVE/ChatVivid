#include "mcp/mcp_client.h"

#include <curl/curl.h>

#include <cctype>
#include <sstream>

#include "util/log.h"

namespace chatvv {
namespace {

size_t write_body(char* ptr, size_t size, size_t nmemb, void* userdata) {
  auto* out = static_cast<std::string*>(userdata);
  out->append(ptr, size * nmemb);
  return size * nmemb;
}

struct HeaderCapture {
  std::string session_id;
};

size_t write_header(char* ptr, size_t size, size_t nmemb, void* userdata) {
  auto* capture = static_cast<HeaderCapture*>(userdata);
  std::string line(ptr, size * nmemb);
  std::string lower = line;
  for (auto& c : lower) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  const std::string key = "mcp-session-id:";
  const auto pos = lower.find(key);
  if (pos != std::string::npos) {
    auto value = line.substr(pos + key.size());
    while (!value.empty() && (value.back() == '\r' || value.back() == '\n' ||
                              value.front() == ' ')) {
      if (value.front() == ' ') {
        value.erase(value.begin());
      } else {
        value.pop_back();
      }
    }
    capture->session_id = value;
  }
  return size * nmemb;
}

std::string trim(std::string value) {
  while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front()))) {
    value.erase(value.begin());
  }
  while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back()))) {
    value.pop_back();
  }
  return value;
}

// Extracts the JSON-RPC object with the expected id from an SSE stream.
nlohmann::json from_sse(const std::string& body, int expected_id,
                        bool* found) {
  *found = false;
  std::istringstream stream(body);
  std::string line;
  while (std::getline(stream, line)) {
    if (line.rfind("data:", 0) != 0) continue;
    const std::string payload = trim(line.substr(5));
    if (payload.empty() || payload == "[DONE]") continue;
    try {
      auto parsed = nlohmann::json::parse(payload);
      if (parsed.is_object() && parsed.contains("id") &&
          parsed["id"].is_number() &&
          parsed["id"].get<int>() == expected_id) {
        *found = true;
        return parsed;
      }
    } catch (...) {
      // Ignore malformed SSE chunks.
    }
  }
  return nlohmann::json::object();
}

}  // namespace

McpClient::McpClient(McpServerConfig server) : server_(std::move(server)) {}

bool McpClient::post(const std::string& payload, std::string* body,
                     std::string* content_type, std::string* error) {
  CURL* handle = curl_easy_init();
  if (handle == nullptr) {
    if (error) *error = "curl_easy_init failed";
    return false;
  }
  curl_slist* headers = nullptr;
  headers = curl_slist_append(headers, "Content-Type: application/json");
  headers = curl_slist_append(headers, "Accept: application/json, text/event-stream");
  if (!server_.token.empty()) {
    headers = curl_slist_append(
        headers, ("Authorization: Bearer " + server_.token).c_str());
  }
  if (!session_id_.empty()) {
    headers = curl_slist_append(
        headers, ("Mcp-Session-Id: " + session_id_).c_str());
  }
  body->clear();
  HeaderCapture capture;
  curl_easy_setopt(handle, CURLOPT_URL, server_.url.c_str());
  curl_easy_setopt(handle, CURLOPT_POST, 1L);
  curl_easy_setopt(handle, CURLOPT_HTTPHEADER, headers);
  curl_easy_setopt(handle, CURLOPT_POSTFIELDS, payload.c_str());
  curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE,
                   static_cast<long>(payload.size()));
  curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, write_body);
  curl_easy_setopt(handle, CURLOPT_WRITEDATA, body);
  curl_easy_setopt(handle, CURLOPT_HEADERFUNCTION, write_header);
  curl_easy_setopt(handle, CURLOPT_HEADERDATA, &capture);
  curl_easy_setopt(handle, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT_MS, 5000L);
  curl_easy_setopt(handle, CURLOPT_TIMEOUT_MS, 20000L);

  const CURLcode rc = curl_easy_perform(handle);
  long http_code = 0;
  curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &http_code);
  char* ct = nullptr;
  curl_easy_getinfo(handle, CURLINFO_CONTENT_TYPE, &ct);
  if (content_type) *content_type = ct == nullptr ? "" : ct;
  curl_slist_free_all(headers);
  curl_easy_cleanup(handle);

  if (!capture.session_id.empty()) session_id_ = capture.session_id;
  if (rc != CURLE_OK) {
    if (error) *error = std::string("curl: ") + curl_easy_strerror(rc);
    return false;
  }
  if (http_code >= 400) {
    if (error) *error = "HTTP " + std::to_string(http_code) + ": " +
                        body->substr(0, 300);
    return false;
  }
  return true;
}

bool McpClient::parse_response(const std::string& body,
                               const std::string& content_type,
                               int expected_id, nlohmann::json* result,
                               std::string* error) {
  nlohmann::json rpc;
  if (content_type.find("text/event-stream") != std::string::npos) {
    bool found = false;
    rpc = from_sse(body, expected_id, &found);
    if (!found) {
      if (error) *error = "MCP SSE response has no matching JSON-RPC result";
      return false;
    }
  } else {
    try {
      rpc = nlohmann::json::parse(body);
    } catch (...) {
      if (error) *error = "MCP response is not JSON";
      return false;
    }
  }
  if (rpc.contains("error")) {
    const auto& err = rpc["error"];
    if (error) {
      *error = err.is_object() ? err.value("message", "MCP error")
                               : err.dump();
    }
    return false;
  }
  *result = rpc.value("result", nlohmann::json::object());
  return true;
}

bool McpClient::rpc(int id, const std::string& method,
                    const nlohmann::json& params, nlohmann::json* result,
                    std::string* error) {
  const nlohmann::json request = {{"jsonrpc", "2.0"},
                                  {"id", id},
                                  {"method", method},
                                  {"params", params}};
  std::string body;
  std::string content_type;
  if (!post(request.dump(), &body, &content_type, error)) return false;
  return parse_response(body, content_type, id, result, error);
}

bool McpClient::ensure_initialized(std::string* error) {
  if (initialized_) return true;
  nlohmann::json result;
  const int id = next_id_++;
  if (!rpc(id, "initialize",
           {{"protocolVersion", "2024-11-05"},
            {"capabilities", nlohmann::json::object()},
            {"clientInfo", {{"name", "ChatVivid"}, {"version", "0.1.0"}}}},
           &result, error)) {
    return false;
  }
  // Best-effort initialized notification (no id, no response expected).
  const nlohmann::json note = {{"jsonrpc", "2.0"},
                                {"method", "notifications/initialized"}};
  std::string body;
  std::string content_type;
  std::string note_error;
  post(note.dump(), &body, &content_type, &note_error);
  initialized_ = true;
  return true;
}

bool McpClient::list_tools(std::vector<McpTool>* out, std::string* error) {
  if (!ensure_initialized(error)) return false;
  nlohmann::json result;
  if (!rpc(next_id_++, "tools/list", nlohmann::json::object(), &result,
           error)) {
    return false;
  }
  const auto tools = result.find("tools");
  if (tools == result.end() || !tools->is_array()) return true;
  for (const auto& item : *tools) {
    if (!item.is_object()) continue;
    McpTool tool;
    tool.name = item.value("name", std::string());
    tool.description = item.value("description", std::string());
    const auto schema = item.find("inputSchema");
    if (schema != item.end() && schema->is_object()) {
      tool.input_schema = *schema;
    } else {
      tool.input_schema = {{"type", "object"}, {"properties", nlohmann::json::object()}};
    }
    if (!tool.name.empty()) out->push_back(std::move(tool));
  }
  return true;
}

bool McpClient::call_tool(const std::string& name,
                          const nlohmann::json& arguments, std::string* text,
                          nlohmann::json* raw, std::string* error) {
  if (!ensure_initialized(error)) return false;
  nlohmann::json result;
  if (!rpc(next_id_++, "tools/call",
           {{"name", name}, {"arguments", arguments}}, &result, error)) {
    return false;
  }
  if (raw) *raw = result;
  std::string output;
  const auto content = result.find("content");
  if (content != result.end() && content->is_array()) {
    for (const auto& item : *content) {
      if (!item.is_object()) continue;
      if (item.value("type", std::string()) == "text") {
        output += item.value("text", std::string());
      } else if (item.contains("text")) {
        output += item["text"].dump();
      }
    }
  }
  if (output.empty() && result.contains("structuredContent")) {
    output = result["structuredContent"].dump();
  }
  if (output.empty()) output = result.dump();
  if (text) *text = output;
  return true;
}

}  // namespace chatvv
