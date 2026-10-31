#include "llm/provider.h"

#include "app/config.h"
#include "llm/mock_provider.h"
#include "llm/responses_provider.h"
#include "util/log.h"

namespace chatvv {

std::unique_ptr<Provider> make_provider(const Config& cfg) {
  if (cfg.llm.provider == "deepseek" || cfg.llm.provider == "responses" ||
      cfg.llm.provider == "openai") {
    log_info("provider.responses",
             {{"base_url", cfg.llm.base_url}, {"endpoint", cfg.llm.endpoint}});
    return std::make_unique<ResponsesProvider>(cfg);
  }
  log_info("provider.mock", {});
  return std::make_unique<MockProvider>();
}

}  // namespace chatvv
