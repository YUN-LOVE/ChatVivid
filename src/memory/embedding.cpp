#include "memory/embedding.h"

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <mutex>

#include <ggml-backend.h>
#include <llama.h>

#if defined(__ANDROID__)
#include <android/log.h>
#endif

#include "util/log.h"

namespace chatvv {
namespace {

std::once_flag g_backend_once;

// Route llama.cpp/ggml diagnostics into the app log (chatvv.log) and logcat.
// Native stderr is discarded on Android, so without this the Vulkan backend is
// a black box on device.
void ggml_log_to_app(enum ggml_log_level level, const char * text, void *) {
  if (text == nullptr || *text == '\0') return;
  std::string line(text);
  while (!line.empty() && (line.back() == '\n' || line.back() == '\r')) {
    line.pop_back();
  }
  if (line.empty()) return;
  if (line.size() > 2000) line.resize(2000);
#if defined(__ANDROID__)
  const int prio = level == GGML_LOG_LEVEL_ERROR  ? ANDROID_LOG_ERROR
                   : level == GGML_LOG_LEVEL_WARN ? ANDROID_LOG_WARN
                                                  : ANDROID_LOG_INFO;
  __android_log_print(prio, "chatvv-ggml", "%s", line.c_str());
#endif
  // INFO is extremely chatty (one line per tensor); keep it in logcat only so
  // chatvv.log stays small. Warnings and errors go to both.
  if (level == GGML_LOG_LEVEL_ERROR) {
    log_error("ggml.native", {{"text", line}});
  } else if (level == GGML_LOG_LEVEL_WARN) {
    log_warn("ggml.native", {{"text", line}});
  }
#if !defined(__ANDROID__)
  else {
    log_info("ggml.native", {{"text", line}});
  }
#endif
}

void install_native_logging() {
  static bool installed = false;
  if (installed) return;
  installed = true;
  llama_log_set(ggml_log_to_app, nullptr);
}

void log_backend_inventory() {
  const size_t count = ggml_backend_dev_count();
  log_info("ggml.devices", {{"count", static_cast<int64_t>(count)}});
  for (size_t i = 0; i < count; ++i) {
    ggml_backend_dev_t dev = ggml_backend_dev_get(i);
    if (dev == nullptr) continue;
    const char * name = ggml_backend_dev_name(dev);
    const char * desc = ggml_backend_dev_description(dev);
    log_info("ggml.device",
             {{"index", static_cast<int64_t>(i)},
              {"name", name ? name : ""},
              {"description", desc ? desc : ""},
              {"type", static_cast<int64_t>(ggml_backend_dev_type(dev))}});
    ggml_backend_buffer_type_t buft = ggml_backend_dev_buffer_type(dev);
    if (buft != nullptr) {
      const char * buft_name = ggml_backend_buft_name(buft);
      log_info("ggml.device.buft",
               {{"index", static_cast<int64_t>(i)},
                {"buft", buft_name ? buft_name : ""},
                {"alignment", static_cast<int64_t>(ggml_backend_buft_get_alignment(buft))}});
    }
  }
}

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
  ready_.store(false, std::memory_order_release);
  std::lock_guard lock(mutex_);
  if (context_) llama_free(context_);
  if (model_) llama_model_free(model_);
}

bool EmbeddingEngine::load(const std::string& model_path, int threads,
                           std::string* error) {
  std::lock_guard lock(mutex_);
  ready_.store(false, std::memory_order_release);
  if (model_path.empty() || !std::filesystem::exists(model_path)) {
    if (error) *error = "embedding model not found: " + model_path;
    return false;
  }
  install_native_logging();
  std::call_once(g_backend_once, [] { llama_backend_init(); });
  log_backend_inventory();

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
  ready_.store(true, std::memory_order_release);
  return true;
}

bool EmbeddingEngine::ready() const {
  return ready_.load(std::memory_order_acquire);
}

int EmbeddingEngine::dim() const {
  std::lock_guard lock(mutex_);
  return dim_;
}

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
