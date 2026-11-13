#include "memory/embedding.h"

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <mutex>

#include <ggml-backend.h>
#include <llama.h>

#include "util/log.h"

namespace chatvv {
namespace {

std::once_flag g_backend_once;

void normalize(std::vector<float>& values) {
  double norm = 0.0;
  for (float value : values) norm += static_cast<double>(value) * value;
  norm = std::sqrt(norm);
  if (norm <= 1e-12) return;
  for (float& value : values) value = static_cast<float>(value / norm);
}

}  // namespace

EmbeddingEngine::EmbeddingEngine() = default;

EmbeddingEngine::~EmbeddingEngine() {
  std::lock_guard lock(mutex_);
  if (context_) llama_free(context_);
  if (model_) llama_model_free(model_);
}

bool EmbeddingEngine::load(const std::string& model_path, int threads,
                           std::string* error) {
  std::lock_guard lock(mutex_);
  if (model_path.empty() || !std::filesystem::exists(model_path)) {
    if (error) *error = "embedding model not found: " + model_path;
    return false;
  }
  std::call_once(g_backend_once, [] { llama_backend_init(); });

  if (context_) {
    llama_free(context_);
    context_ = nullptr;
  }
  if (model_) {
    llama_model_free(model_);
    model_ = nullptr;
  }

  llama_model_params model_params = llama_model_default_params();
  model_params.n_gpu_layers = 0;

  // Keep RAG embeddings on the CPU on every platform.
  //
  // The embedding model is tiny (bge-small, ~26 MB), so a GPU backend buys
  // nothing measurable, but ggml's Vulkan backend crashes while loading the
  // model on some Android devices (SIGSEGV with a NULL buffer-type iface inside
  // ggml_backend_buft_alloc_buffer_n, reported from llama_model_load_from_file
  // on a Pixel 6a/Adreno). A NULL-terminated CPU-only device list makes llama
  // allocate the weights through the CPU buffer types; llama_backend_init()
  // still registers the Vulkan backend for the ASR/LLM paths.
  static ggml_backend_dev_t cpu_devices[2] = {nullptr, nullptr};
  cpu_devices[0] = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU);
  if (cpu_devices[0] != nullptr) {
    model_params.devices = cpu_devices;
    log_info("embedding.devices", {{"selected", "cpu"}});
  }

  model_ = llama_model_load_from_file(model_path.c_str(), model_params);
  if (!model_) {
    if (error) *error = "llama_model_load_from_file failed";
    return false;
  }

  llama_context_params context_params = llama_context_default_params();
  context_params.n_ctx = 512;
  context_params.n_batch = 512;
  context_params.n_ubatch = 512;
  context_params.n_threads = std::max(1, threads);
  context_params.n_threads_batch = std::max(1, threads);
  context_params.embeddings = true;
  context_params.pooling_type = LLAMA_POOLING_TYPE_CLS;
  context_params.attention_type = LLAMA_ATTENTION_TYPE_NON_CAUSAL;
  context_ = llama_init_from_model(model_, context_params);
  if (!context_) {
    if (error) *error = "llama_init_from_model failed";
    llama_model_free(model_);
    model_ = nullptr;
    return false;
  }
  dim_ = llama_model_n_embd(model_);
  if (dim_ <= 0) {
    if (error) *error = "embedding model has no embedding dimension";
    return false;
  }
  log_info("embedding.ready",
           {{"model", model_path}, {"dim", dim_}, {"threads", threads}});
  return true;
}

bool EmbeddingEngine::ready() const {
  return model_ != nullptr && context_ != nullptr;
}

int EmbeddingEngine::dim() const { return dim_; }

std::vector<float> EmbeddingEngine::embed(const std::string& text,
                                          std::string* error) {
  std::lock_guard lock(mutex_);
  if (!ready()) {
    if (error) *error = "embedding engine not ready";
    return {};
  }
  if (text.empty()) {
    if (error) *error = "empty embedding text";
    return {};
  }
  const llama_vocab* vocab = llama_model_get_vocab(model_);
  const int32_t needed =
      -llama_tokenize(vocab, text.data(), static_cast<int32_t>(text.size()),
                      nullptr, 0, true, false);
  if (needed <= 0) {
    if (error) *error = "tokenization failed";
    return {};
  }
  const int32_t count = std::min<int32_t>(needed, 512);
  std::vector<llama_token> tokens(static_cast<size_t>(count));
  if (llama_tokenize(vocab, text.data(), static_cast<int32_t>(text.size()),
                     tokens.data(), count, true, false) < 0) {
    if (error) *error = "tokenization overflow";
    return {};
  }
  llama_batch batch = llama_batch_get_one(tokens.data(), count);
  const int32_t rc = llama_model_has_encoder(model_)
                          ? llama_encode(context_, batch)
                          : llama_decode(context_, batch);
  if (rc != 0) {
    if (error) *error = "llama encode failed: " + std::to_string(rc);
    return {};
  }
  const float* values = llama_get_embeddings_seq(context_, 0);
  if (!values) values = llama_get_embeddings(context_);
  if (!values) {
    if (error) *error = "no embeddings returned";
    return {};
  }
  std::vector<float> result(values, values + dim_);
  normalize(result);
  llama_memory_clear(llama_get_memory(context_), true);
  return result;
}

}  // namespace chatvv
