#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "context/injections.h"

namespace httplib {
class Server;
class Request;
class Response;
}  // namespace httplib

namespace chatvv {

class Db;
class ResponseHub;
class DialogService;
struct Config;

class HttpServer {
 public:
  HttpServer(const Config& cfg, Db& db, InjectionStore& slots,
             ResponseHub& hub, DialogService& dialog);
  ~HttpServer();

  bool listen();
  void stop();

 private:
  void setup_routes();
  bool authorized(const httplib::Request& req, httplib::Response& res) const;
  void add_cors(httplib::Response& res) const;
  void json_response(httplib::Response& res, const nlohmann::json& body,
                     int status = 200) const;
  void error_response(httplib::Response& res, int status,
                      const std::string& code,
                      const std::string& message) const;
  void stream_events(httplib::Response& res, const std::string& id,
                     int64_t after);
  std::vector<Injection> parse_injections(const nlohmann::json& arr) const;

  const Config& cfg_;
  Db& db_;
  InjectionStore& slots_;
  ResponseHub& hub_;
  DialogService& dialog_;
  std::unique_ptr<httplib::Server> svr_;
};

}  // namespace chatvv
