#pragma once

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include "context/context_builder.h"

namespace chatvv {

class Db;
class EmbeddingEngine;
class InjectionStore;
class Provider;
class ResponseHub;
struct Config;

class DialogService {
 public:
  DialogService(const Config& cfg, Db& db, InjectionStore& slots,
                ResponseHub& hub, Provider& provider,
                EmbeddingEngine* embedding = nullptr);
  ~DialogService();

  struct StartResult {
    std::string id;
    std::string status;
  };

  StartResult start(const std::string& text,
                    const std::vector<Injection>& extra = {},
                    const std::string& instructions_override = {});

  bool cancel(const std::string& id);
  void shutdown();

 private:
  void run(std::string id, BuiltContext ctx, std::string model,
           std::string user_text,
           std::shared_ptr<std::atomic<bool>> cancel);

  const Config& cfg_;
  Db& db_;
  InjectionStore& slots_;
  ResponseHub& hub_;
  Provider& provider_;
  EmbeddingEngine* embedding_ = nullptr;

  std::mutex mu_;
  std::unordered_map<std::string, std::shared_ptr<std::atomic<bool>>> cancels_;
  std::vector<std::thread> threads_;
  bool stopping_ = false;
};

}  // namespace chatvv
