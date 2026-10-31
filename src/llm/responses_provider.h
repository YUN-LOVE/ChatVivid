#pragma once

#include "llm/provider.h"

namespace chatvv {

class ResponsesProvider : public Provider {
 public:
  explicit ResponsesProvider(const Config& cfg);

  LlmResult complete(const LlmRequest& req, const EventSink& sink) override;

 private:
  std::string default_base_url_;
  std::string default_endpoint_;
  std::string default_api_key_;
  int default_timeout_ms_ = 120000;
};

}  // namespace chatvv
