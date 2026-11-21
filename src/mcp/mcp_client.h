#pragma once

#include <nlohmann/json.hpp>

#include <string>
#include <vector>

#include "app/config.h"

namespace chatvv {

/// One tool exposed by an MCP server.
struct McpTool {
  std::string name;
  std::string description;
  nlohmann::json input_schema = nlohmann::json::object();
};

/// Minimal MCP Streamable-HTTP client (initialize + tools/list + tools/call).
///
/// The transport is JSON-RPC 2.0 over a single HTTP endpoint. Responses may be
/// application/json or text/event-stream (SSE); both are accepted.
class McpClient {
 public:
  explicit McpClient(McpServerConfig server);

  bool list_tools(std::vector<McpTool>* out, std::string* error);
  bool call_tool(const std::string& name, const nlohmann::json& arguments,
                 std::string* text, nlohmann::json* raw, std::string* error);

  const McpServerConfig& server() const { return server_; }

 private:
  bool ensure_initialized(std::string* error);
  bool rpc(int id, const std::string& method, const nlohmann::json& params,
           nlohmann::json* result, std::string* error);
  bool post(const std::string& payload, std::string* body,
            std::string* content_type, std::string* error);
  bool parse_response(const std::string& body,
                      const std::string& content_type, int expected_id,
                      nlohmann::json* result, std::string* error);

  McpServerConfig server_;
  std::string session_id_;
  bool initialized_ = false;
  int next_id_ = 1;
};

}  // namespace chatvv
