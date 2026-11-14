#include "asr/asr.h"

#include <ggml-backend.h>
#include <nlohmann/json.hpp>
#include <whisper.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <limits>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "util/log.h"
#include "util/util.h"

namespace chatvv {
namespace {

using json = nlohmann::json;

constexpr int32_t kSampleRate = 16000;                 // whisper's native rate
constexpr size_t kMinSamples = kSampleRate / 10;       // reject clips < 100 ms
constexpr uint64_t kMaxWavBytes = 512ull * 1024 * 1024;  // 512 MiB guard rail
constexpr size_t kMaxLogLine = 512;

// ---------------------------------------------------------------------------
// whisper.cpp logging -> chatvv structured log
// ---------------------------------------------------------------------------

void whisper_log_callback(ggml_log_level level, const char* text,
                          void* /*user_data*/) {
  try {
    if (!text || !*text) return;
    std::string line(text);
    while (!line.empty() && (line.back() == '\n' || line.back() == '\r')) {
      line.pop_back();
    }
    if (line.empty()) return;
    if (line.size() > kMaxLogLine) {
      line.resize(kMaxLogLine);
      line.append("...");
    }
    switch (level) {
      case GGML_LOG_LEVEL_ERROR:
        log_error("asr.whisper", {{"line", line}});
        break;
      case GGML_LOG_LEVEL_WARN:
        log_warn("asr.whisper", {{"line", line}});
        break;
      case GGML_LOG_LEVEL_INFO:
      case GGML_LOG_LEVEL_CONT:
      default:
        log_debug("asr.whisper", {{"line", line}});
        break;
    }
  } catch (...) {
    // Logging must never throw across the C callback boundary.
  }
}

void install_whisper_logging() {
  static std::once_flag once;
  std::call_once(once, [] { whisper_log_set(&whisper_log_callback, nullptr); });
}

// ---------------------------------------------------------------------------
// ggml backend introspection (capabilities)
// ---------------------------------------------------------------------------

std::vector<std::string> ggml_backend_names() {
  std::vector<std::string> names;
  const size_t count = ggml_backend_reg_count();
  for (size_t i = 0; i < count; ++i) {
    const ggml_backend_reg_t reg = ggml_backend_reg_get(i);
    if (!reg) continue;
    const char* name = ggml_backend_reg_name(reg);
    if (name && *name) names.emplace_back(name);
  }
  if (names.empty()) names.emplace_back("CPU");
  return names;
}

bool gpu_device_available() {
  return ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU) != nullptr ||
         ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_IGPU) != nullptr;
}

json base_capabilities() {
  json languages = json::array();
  const int max_id = whisper_lang_max_id();
  for (int id = 0; id <= max_id; ++id) {
    const char* code = whisper_lang_str(id);
    if (code && *code) languages.push_back(code);
  }

  json backends = json::array();
  for (auto& name : ggml_backend_names()) backends.push_back(std::move(name));

  const char* version = whisper_version();
  return json{{"engine", "whisper.cpp"},
              {"version", version ? version : "unknown"},
              {"sample_rate", kSampleRate},
              {"audio_formats", json::array({"wav", "pcm_f32"})},
              {"language_default", "auto"},
              {"languages", std::move(languages)},
              {"backends", std::move(backends)},
              {"supports_translate", true},
              {"gpu_available", gpu_device_available()}};
}

// ---------------------------------------------------------------------------
// WAV decoding (RIFF/WAVE -> 16 kHz mono float32)
// ---------------------------------------------------------------------------

uint16_t le_u16(const uint8_t* p) {
  return static_cast<uint16_t>(static_cast<uint16_t>(p[0]) |
                               (static_cast<uint16_t>(p[1]) << 8));
}

uint32_t le_u32(const uint8_t* p) {
  return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) |
         (static_cast<uint32_t>(p[3]) << 24);
}

uint64_t le_u64(const uint8_t* p) {
  return static_cast<uint64_t>(le_u32(p)) |
         (static_cast<uint64_t>(le_u32(p + 4)) << 32);
}

bool read_entire_file(const std::string& path, std::vector<uint8_t>* out,
                      std::string* error) {
  std::error_code ec;
  const auto file_size = std::filesystem::file_size(path, ec);
  if (ec) {
    if (error) *error = "cannot stat audio file '" + path + "': " + ec.message();
    return false;
  }
  if (file_size > kMaxWavBytes) {
    if (error) {
      *error = "audio file is too large (max 512 MiB): '" + path + "'";
    }
    return false;
  }
  std::ifstream in(path, std::ios::binary);
  if (!in) {
    if (error) *error = "cannot open audio file '" + path + "'";
    return false;
  }
  out->resize(static_cast<size_t>(file_size));
  if (file_size > 0) {
    in.read(reinterpret_cast<char*>(out->data()),
            static_cast<std::streamsize>(file_size));
    if (!in) {
      if (error) *error = "failed to read audio file '" + path + "'";
      return false;
    }
  }
  return true;
}

struct WavFormat {
  uint16_t format = 0;  // 1 = PCM integer, 3 = IEEE float
  uint16_t channels = 0;
  uint32_t sample_rate = 0;
  uint16_t bits = 0;
  size_t data_offset = 0;
  size_t data_size = 0;
};

bool parse_wav(const std::vector<uint8_t>& bytes, WavFormat* format,
               std::string* error) {
  auto fail = [error](std::string message) {
    if (error) *error = std::move(message);
    return false;
  };

  if (bytes.size() < 12) return fail("WAV file is too small");
  if (std::memcmp(bytes.data(), "RIFF", 4) != 0 ||
      std::memcmp(bytes.data() + 8, "WAVE", 4) != 0) {
    return fail("not a RIFF/WAVE file");
  }

  bool have_fmt = false;
  bool have_data = false;
  size_t offset = 12;
  while (offset + 8 <= bytes.size()) {
    const uint8_t* header = bytes.data() + offset;
    const size_t payload = offset + 8;
    size_t chunk_size = le_u32(header + 4);
    // Tolerate truncated files and streaming `data` chunks that declare
    // 0xFFFFFFFF; clamp to what is actually present.
    if (chunk_size > bytes.size() - payload) chunk_size = bytes.size() - payload;

    if (std::memcmp(header, "fmt ", 4) == 0) {
      if (chunk_size < 16) return fail("WAV fmt chunk is truncated");
      const uint8_t* p = bytes.data() + payload;
      uint16_t tag = le_u16(p);
      const uint16_t channels = le_u16(p + 2);
      const uint32_t sample_rate = le_u32(p + 4);
      const uint16_t bits = le_u16(p + 14);
      if (tag == 0xFFFE) {  // WAVE_FORMAT_EXTENSIBLE
        if (chunk_size < 40) {
          return fail("WAVE_FORMAT_EXTENSIBLE fmt chunk is truncated");
        }
        tag = le_u16(p + 24);  // first two bytes of the SubFormat GUID
      }
      if (tag != 1 && tag != 3) {
        return fail("unsupported WAV codec (only PCM and IEEE float)");
      }
      if (channels == 0 || channels > 32) {
        return fail("unsupported WAV channel count");
      }
      if (sample_rate == 0 || sample_rate > 384000) {
        return fail("unsupported WAV sample rate");
      }
      if (bits != 8 && bits != 16 && bits != 24 && bits != 32 &&
          bits != 64) {
        return fail("unsupported WAV bit depth");
      }
      if (tag == 1 && bits == 64) {
        return fail("unsupported 64-bit integer WAV samples");
      }
      format->format = tag;
      format->channels = channels;
      format->sample_rate = sample_rate;
      format->bits = bits;
      have_fmt = true;
    } else if (std::memcmp(header, "data", 4) == 0) {
      if (!have_data) {
        format->data_offset = payload;
        format->data_size = chunk_size;
        have_data = true;
      }
    }

    offset = payload + chunk_size;
    if (chunk_size & 1u) ++offset;  // RIFF chunks are word aligned
    if (chunk_size == 0) break;     // malformed; avoid a stalled loop
  }

  if (!have_fmt) return fail("WAV file has no fmt chunk");
  if (!have_data) return fail("WAV file has no data chunk");
  if (format->data_size == 0) return fail("WAV file has no audio samples");
  return true;
}

float sample_to_float(const uint8_t* p, uint16_t bits, bool is_float) {
  if (is_float) {
    if (bits == 32) {
      const uint32_t raw = le_u32(p);
      float value = 0.0f;
      std::memcpy(&value, &raw, sizeof(value));
      return value;
    }
    if (bits == 64) {
      const uint64_t raw = le_u64(p);
      double value = 0.0;
      std::memcpy(&value, &raw, sizeof(value));
      return static_cast<float>(value);
    }
    return 0.0f;
  }
  switch (bits) {
    case 8:
      return (static_cast<int>(p[0]) - 128) / 128.0f;
    case 16:
      return static_cast<int16_t>(le_u16(p)) / 32768.0f;
    case 24: {
      int32_t value = static_cast<int32_t>(le_u32(p) << 8) >> 8;
      return value / 8388608.0f;
    }
    case 32:
      return static_cast<int32_t>(le_u32(p)) / 2147483648.0f;
    default:
      return 0.0f;
  }
}

std::vector<float> resample_linear(const float* input, size_t input_count,
                                   int32_t input_rate, int32_t output_rate) {
  if (input_rate == output_rate || input_count == 0) {
    return std::vector<float>(input, input + input_count);
  }
  const double ratio =
      static_cast<double>(output_rate) / static_cast<double>(input_rate);
  const size_t output_count = std::max<size_t>(
      1, static_cast<size_t>(std::llround(input_count * ratio)));
  std::vector<float> output(output_count);
  for (size_t i = 0; i < output_count; ++i) {
    const double position = static_cast<double>(i) / ratio;
    const size_t index = static_cast<size_t>(position);
    const double fraction = position - static_cast<double>(index);
    const size_t next = std::min(index + 1, input_count - 1);
    output[i] = static_cast<float>(
        static_cast<double>(input[index]) * (1.0 - fraction) +
        static_cast<double>(input[next]) * fraction);
  }
  return output;
}

bool decode_wav(const std::string& wav_path, std::vector<float>* samples,
                std::string* error) {
  std::vector<uint8_t> bytes;
  if (!read_entire_file(wav_path, &bytes, error)) return false;

  WavFormat format;
  if (!parse_wav(bytes, &format, error)) return false;

  const size_t bytes_per_sample = format.bits / 8u;
  const size_t frame_bytes = bytes_per_sample * format.channels;
  if (frame_bytes == 0) {
    if (error) *error = "invalid WAV frame size";
    return false;
  }
  const size_t frames = format.data_size / frame_bytes;
  if (frames == 0) {
    if (error) *error = "WAV file contains no complete audio frames";
    return false;
  }

  const bool is_float = format.format == 3;
  std::vector<float> mono;
  mono.reserve(frames);
  const uint8_t* p = bytes.data() + format.data_offset;
  for (size_t frame = 0; frame < frames; ++frame) {
    double sum = 0.0;
    for (uint16_t channel = 0; channel < format.channels; ++channel) {
      sum += sample_to_float(p, format.bits, is_float);
      p += bytes_per_sample;
    }
    mono.push_back(static_cast<float>(sum / format.channels));
  }

  *samples = resample_linear(mono.data(), mono.size(), format.sample_rate,
                             kSampleRate);
  return true;
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

AsrResult make_error(AsrResult result, std::string code, std::string message) {
  result.ok = false;
  result.code = std::move(code);
  result.error = std::move(message);
  return result;
}

int32_t resolve_threads(int32_t requested, int32_t engine_default) {
  const int32_t wanted = requested > 0 ? requested : engine_default;
  if (wanted <= 0) return 0;  // 0 => whisper's own default
  return std::clamp(wanted, static_cast<int32_t>(1),
                    static_cast<int32_t>(64));
}

}  // namespace

// ---------------------------------------------------------------------------
// AsrEngine
// ---------------------------------------------------------------------------

struct AsrEngine::Impl {
  mutable std::mutex mu;
  whisper_context* ctx = nullptr;
  std::string model_path;
  int32_t threads = 0;
  bool use_gpu = false;
  bool gpu_active = false;
  bool flash_attn = false;
};

AsrEngine::AsrEngine() : impl_(std::make_unique<Impl>()) {}

AsrEngine::~AsrEngine() { unload(); }

AsrEngine::AsrEngine(AsrEngine&&) noexcept = default;
AsrEngine& AsrEngine::operator=(AsrEngine&&) noexcept = default;

bool AsrEngine::load(const AsrEngineConfig& config, std::string* error) {
  auto fail = [error](std::string message) {
    if (error) *error = std::move(message);
    return false;
  };
  if (!impl_) return fail("engine is not initialized");
  if (config.model_path.empty()) return fail("model_path is required");

  std::error_code ec;
  const bool exists = std::filesystem::exists(config.model_path, ec);
  if (ec || !exists) {
    return fail("whisper model not found: '" + config.model_path + "'");
  }

  install_whisper_logging();

  const auto started = now_ms();
  whisper_context_params cparams = whisper_context_default_params();
  cparams.use_gpu = config.use_gpu;
  cparams.flash_attn = config.flash_attn;

  std::lock_guard lock(impl_->mu);
  if (impl_->ctx) {
    whisper_free(impl_->ctx);
    impl_->ctx = nullptr;
  }
  impl_->model_path.clear();
  impl_->threads = 0;
  impl_->use_gpu = config.use_gpu;
  impl_->gpu_active = false;
  impl_->flash_attn = config.flash_attn;

  bool gpu_active = config.use_gpu && gpu_device_available();
  whisper_context* ctx =
      whisper_init_from_file_with_params(config.model_path.c_str(), cparams);
  if (!ctx && config.use_gpu) {
    // Some phones expose a Vulkan loader but fail to create the device. CPU is
    // slow but correct, so fall back instead of failing the whole ASR setup.
    log_warn("asr.gpu_fallback", {{"model", config.model_path}});
    cparams.use_gpu = false;
    gpu_active = false;
    ctx = whisper_init_from_file_with_params(config.model_path.c_str(), cparams);
  }
  if (!ctx) {
    return fail("failed to load whisper model: '" + config.model_path + "'");
  }

  impl_->ctx = ctx;
  impl_->model_path = config.model_path;
  impl_->threads = resolve_threads(config.threads, 0);
  impl_->gpu_active = gpu_active;

  log_info("asr.model_loaded",
           {{"model", impl_->model_path},
            {"wall_ms", now_ms() - started},
            {"gpu", gpu_active},
            {"flash_attn", config.flash_attn},
            {"threads", impl_->threads}});
  return true;
}

void AsrEngine::unload() {
  if (!impl_) return;
  std::lock_guard lock(impl_->mu);
  if (impl_->ctx) {
    whisper_free(impl_->ctx);
    impl_->ctx = nullptr;
  }
  impl_->model_path.clear();
  impl_->threads = 0;
  impl_->gpu_active = false;
}

bool AsrEngine::ready() const {
  if (!impl_) return false;
  std::lock_guard lock(impl_->mu);
  return impl_->ctx != nullptr;
}

std::string AsrEngine::model_path() const {
  if (!impl_) return {};
  std::lock_guard lock(impl_->mu);
  return impl_->model_path;
}

bool AsrEngine::using_gpu() const {
  if (!impl_) return false;
  std::lock_guard lock(impl_->mu);
  return impl_->gpu_active;
}

int32_t AsrEngine::threads() const {
  if (!impl_) return 0;
  std::lock_guard lock(impl_->mu);
  return impl_->threads;
}

AsrResult AsrEngine::transcribe_file(const std::string& wav_path,
                                     const AsrOptions& options) {
  AsrResult result;
  if (wav_path.empty()) {
    return make_error(std::move(result), "invalid_argument",
                      "wav_path is required");
  }
  std::vector<float> samples;
  std::string decode_error;
  if (!decode_wav(wav_path, &samples, &decode_error)) {
    log_warn("asr.wav_decode_failed",
             {{"path", wav_path}, {"error", decode_error}});
    return make_error(std::move(result), "invalid_wav", decode_error);
  }
  return transcribe_pcm(samples.data(), samples.size(), kSampleRate, options);
}

AsrResult AsrEngine::transcribe_pcm(const float* samples, size_t sample_count,
                                    int32_t sample_rate,
                                    const AsrOptions& options) {
  AsrResult result;
  if (!impl_) return make_error(std::move(result), "engine_error", "engine is not initialized");
  if (!samples) {
    if (sample_count == 0) {
      return make_error(std::move(result), "audio_empty", "audio buffer is empty");
    }
    return make_error(std::move(result), "invalid_argument",
                      "samples is null");
  }
  if (sample_count == 0) {
    return make_error(std::move(result), "audio_empty", "audio buffer is empty");
  }
  if (sample_rate <= 0) {
    return make_error(std::move(result), "invalid_argument",
                      "sample_rate must be positive");
  }

  std::string language =
      options.language.empty() ? std::string("auto") : options.language;
  std::transform(language.begin(), language.end(), language.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  const bool auto_language = language == "auto" || language == "detect";
  if (!auto_language && whisper_lang_id(language.c_str()) < 0) {
    return make_error(std::move(result), "invalid_language",
                      "unsupported language code: " + options.language);
  }

  // Resample before taking the engine lock: whisper contexts are not thread
  // safe, but resampling is pure CPU work on the caller's buffer.
  std::vector<float> resampled;
  const float* data = samples;
  size_t count = sample_count;
  if (sample_rate != kSampleRate) {
    resampled = resample_linear(samples, sample_count, sample_rate, kSampleRate);
    data = resampled.data();
    count = resampled.size();
  }
  if (count < kMinSamples) {
    return make_error(std::move(result), "audio_too_short",
                      "audio must be at least 100 ms");
  }
  if (count > static_cast<size_t>(std::numeric_limits<int>::max())) {
    return make_error(std::move(result), "audio_too_long",
                      "audio is too long for whisper.cpp");
  }

  std::lock_guard lock(impl_->mu);
  if (!impl_->ctx) {
    return make_error(std::move(result), "engine_not_loaded",
                      "whisper model is not loaded");
  }

  whisper_full_params params =
      whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  params.print_special = false;
  params.print_progress = false;
  params.print_realtime = false;
  params.print_timestamps = false;
  params.translate = options.translate;
  params.no_context = true;  // each transcription is independent
  params.single_segment = false;
  params.detect_language = false;
  params.language = auto_language ? "auto" : language.c_str();
  const int32_t threads = resolve_threads(options.threads, impl_->threads);
  if (threads > 0) params.n_threads = threads;

  const auto started = now_ms();
  const int rc = whisper_full(impl_->ctx, params, data, static_cast<int>(count));
  if (rc != 0) {
    log_warn("asr.transcribe_failed",
             {{"code", rc}, {"samples", count}, {"sample_rate", kSampleRate}});
    return make_error(std::move(result), "transcribe_failed",
                      "whisper_full failed with code " + std::to_string(rc));
  }

  const int segment_count = whisper_full_n_segments(impl_->ctx);
  result.segments.reserve(static_cast<size_t>(std::max(0, segment_count)));
  for (int i = 0; i < segment_count; ++i) {
    AsrSegment segment;
    segment.id = i;
    // whisper timestamps are in 10 ms units.
    segment.start_ms = whisper_full_get_segment_t0(impl_->ctx, i) * 10;
    segment.end_ms = whisper_full_get_segment_t1(impl_->ctx, i) * 10;
    const char* text = whisper_full_get_segment_text(impl_->ctx, i);
    if (text) segment.text = text;
    result.text.append(segment.text);
    result.segments.push_back(std::move(segment));
  }
  result.text = trim(result.text);

  const int language_id = whisper_full_lang_id(impl_->ctx);
  const char* language_code =
      language_id >= 0 ? whisper_lang_str(language_id) : nullptr;
  result.language = language_code ? language_code
                                  : (auto_language ? "unknown" : language);
  result.model = impl_->model_path;
  result.duration_ms =
      static_cast<int64_t>(count) * 1000 / static_cast<int64_t>(kSampleRate);
  result.ok = true;

  log_info("asr.transcribed",
           {{"model", impl_->model_path},
            {"duration_ms", result.duration_ms},
            {"wall_ms", now_ms() - started},
            {"segments", result.segments.size()},
            {"language", result.language},
            {"gpu", impl_->gpu_active}});
  return result;
}

std::string AsrEngine::capabilities_json() const {
  json caps = base_capabilities();
  if (impl_) {
    std::lock_guard lock(impl_->mu);
    caps["loaded"] = impl_->ctx != nullptr;
    caps["model"] = impl_->model_path;
    caps["threads"] = impl_->threads;
    caps["gpu_requested"] = impl_->use_gpu;
    caps["gpu_active"] = impl_->gpu_active;
    caps["flash_attn"] = impl_->flash_attn;
  } else {
    caps["loaded"] = false;
    caps["model"] = "";
    caps["threads"] = 0;
    caps["gpu_requested"] = false;
    caps["gpu_active"] = false;
    caps["flash_attn"] = false;
  }
  return caps.dump();
}

std::string AsrEngine::static_capabilities_json() {
  return base_capabilities().dump();
}

std::string AsrEngine::to_json(const AsrResult& result) {
  json segments = json::array();
  for (const auto& segment : result.segments) {
    segments.push_back({{"id", segment.id},
                        {"start_ms", segment.start_ms},
                        {"end_ms", segment.end_ms},
                        {"text", segment.text}});
  }
  return json{{"text", result.text},
              {"language", result.language},
              {"model", result.model},
              {"duration_ms", result.duration_ms},
              {"segments", std::move(segments)}}
      .dump();
}

bool DecodeWavToPcm16k(const std::string& wav_path, std::vector<float>* samples,
                       std::string* error) {
  if (!samples) {
    if (error) *error = "samples output is null";
    return false;
  }
  samples->clear();
  return decode_wav(wav_path, samples, error);
}

}  // namespace chatvv
