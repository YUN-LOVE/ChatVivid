#pragma once

// ASR (speech-to-text) engine for the embedded ChatVivid core.
//
// Thin C++ wrapper around the vendored whisper.cpp C API
// (third_party/whisper.cpp, pinned in UPSTREAM.md). The public C ABI in
// include/chatvv/chatvv.h exposes the same engine to Dart/FFI; this header is
// for the C++ core (tests, future server adapters) and is not a stable ABI.
//
// Threading: one AsrEngine owns one whisper context. Transcription calls on the
// same engine are serialized by an internal mutex (whisper contexts are not
// thread safe); different engines can run in parallel. Loading, transcribing
// and unloading must not race with each other - the mutex covers all of them.

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace chatvv {

// Whisper output segment. Times are milliseconds from the start of the audio.
struct AsrSegment {
  int32_t id = 0;
  int64_t start_ms = 0;
  int64_t end_ms = 0;
  std::string text;
};

// Result of one transcription. On failure ok=false and code/message are set
// (code is a stable machine-readable token, message is human-readable).
struct AsrResult {
  bool ok = false;
  std::string code;
  std::string error;
  std::string text;      // full transcript (segments joined)
  std::string language;  // detected or forced ISO 639-1 code (e.g. "zh")
  std::string model;     // model file path used for this result
  int64_t duration_ms = 0;
  std::vector<AsrSegment> segments;
};

// Per-call options. Defaults transcribe in the detected language with
// automatic thread count and the engine's GPU setting.
struct AsrOptions {
  // Whisper language code ("zh", "en", "ja", ...) or "auto" to detect.
  std::string language = "auto";
  // 0 => whisper default (min(4, hardware_concurrency)); 1..N otherwise.
  int32_t threads = 0;
  // Translate to English instead of transcribing (multilingual models only).
  bool translate = false;
};

// Engine construction options.
struct AsrEngineConfig {
  // UTF-8 path to a ggml Whisper model (ggml-tiny.bin, ggml-base.bin, ...).
  std::string model_path;
  // 0 => auto.
  int32_t threads = 0;
  // Prefer a GPU backend (Vulkan when ggml was built with it). Falls back to
  // CPU if no GPU backend is available or the GPU context cannot be created.
  bool use_gpu = true;
  // Enable flash attention when the backend supports it (off: most compatible).
  bool flash_attn = false;
};

class AsrEngine {
 public:
  AsrEngine();
  ~AsrEngine();

  AsrEngine(AsrEngine&&) noexcept;
  AsrEngine& operator=(AsrEngine&&) noexcept;
  AsrEngine(const AsrEngine&) = delete;
  AsrEngine& operator=(const AsrEngine&) = delete;

  // Loads the model. On failure returns false, leaves the engine unloaded and
  // writes a description to *error (when non-null). Loading an already loaded
  // engine releases the previous model first.
  bool load(const AsrEngineConfig& config, std::string* error);

  // Releases the model. Safe to call when not loaded.
  void unload();

  bool ready() const;
  // Effective model path (empty when not loaded).
  std::string model_path() const;
  // Whether a GPU backend was actually used (after CPU fallback).
  bool using_gpu() const;
  // Effective thread count (0 while unloaded).
  int32_t threads() const;

  // Transcribes a WAV file. Accepts RIFF/WAVE PCM 8/16/24/32-bit, IEEE
  // float32/float64, mono or multi-channel; any sample rate is linearly
  // resampled to 16 kHz mono (whisper's native rate).
  AsrResult transcribe_file(const std::string& wav_path,
                            const AsrOptions& options);

  // Transcribes mono float32 PCM in [-1, 1] at `sample_rate` Hz. The pointer
  // must stay valid for the duration of the call; it is not retained.
  AsrResult transcribe_pcm(const float* samples, size_t sample_count,
                           int32_t sample_rate, const AsrOptions& options);

  // JSON capability object for the C ABI. Includes version/backends/model
  // state; safe to call on a default-constructed (unloaded) engine.
  std::string capabilities_json() const;

  // Serializes an AsrResult to the FFI JSON contract:
  // {"text","language","model","duration_ms","segments":[{"id","start_ms",
  //  "end_ms","text"}]}
  static std::string to_json(const AsrResult& result);

  // Build-level capabilities that do not require a loaded model (helps CI
  // smoke checks and `chatvv_asr_capabilities(NULL, ...)`).
  static std::string static_capabilities_json();

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

// Decodes a WAV file to 16 kHz mono float32 PCM. Exposed for tests and for
// callers that want to inspect/validate audio before transcription.
// Returns false and fills *error on unsupported/corrupt input.
bool DecodeWavToPcm16k(const std::string& wav_path, std::vector<float>* samples,
                       std::string* error);

}  // namespace chatvv
