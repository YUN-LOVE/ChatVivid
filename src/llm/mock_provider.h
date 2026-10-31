#pragma once

#include "llm/provider.h"

namespace chatvv {

class MockProvider : public Provider {
 public:
  LlmResult complete(const LlmRequest& req, const EventSink& sink) override;
};

}  // namespace chatvv
