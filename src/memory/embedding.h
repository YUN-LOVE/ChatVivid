#pragma once

#include <mutex>
#include <string>
#include <vector>

struct llama_model;
struct llama_context;

namespace chatvv {

/// Local GGUF embedding model loaded through llama.cpp.
class EmbeddingEngine {
 public:
  EmbeddingEngine();
  ~EmbeddingEngine();

  EmbeddingEngine(const EmbeddingEngine&) = delete;
  EmbeddingEngine& operator=(const EmbeddingEngine&) = delete;

  bool load(const std::string& model_path, int threads = 2,
            std::string* error = nullptr);
  bool ready() const;
  int dim() const;
  std::vector<float> embed(const std::string& text, std::string* error = nullptr);

 private:
  mutable std::mutex mutex_;
  llama_model* model_ = nullptr;
  llama_context* context_ = nullptr;
  int dim_ = 0;
};

}  // namespace chatvv
