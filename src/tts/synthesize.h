#pragma once

#include <string>

namespace chatvv {

/// Result of a text-to-speech synthesis request.
///
/// Mirrors the old self-written Edge TTS result: on success `ok` is true,
/// `audio_path` is the written MP3 path and `error` is empty. On failure `ok`
/// is false, `audio_path` is empty and `error` is a human readable message
/// (already safe to surface through the C ABI error JSON).
struct SynthesizeResult {
  bool ok = false;
  std::string error;
  std::string audio_path;
};

/// Optional prosody overrides for Edge TTS. All fields are relative: rate and
/// volume are in read_aloud's `-1.0..=1.0` range (0 = service default), pitch is
/// a hertz offset (0 = service default).
struct SynthesizeOptions {
  int32_t pitch_hz = 0;
  float rate = 0.0f;
  float volume = 0.0f;

  bool IsDefault() const {
    return pitch_hz == 0 && rate == 0.0f && volume == 0.0f;
  }
};

/// Synthesize `text` to an MP3 file at `output_path` using the vendored
/// read_aloud backend (Microsoft Edge read-aloud service).
///
/// `voice` accepts the Microsoft Edge voice short name used by the Flutter app
/// (for example "zh-CN-XiaoxiaoNeural"), the same name with underscores
/// ("zh_CN_XiaoxiaoNeural"), or the full Edge voice name
/// ("Microsoft Server Speech Text to Speech Voice (zh-CN, XiaoxiaoNeural)").
/// Matching is case-insensitive and whitespace-trimmed. An empty or unknown
/// voice falls back to the default voice (zh-CN-XiaoxiaoNeural) and logs a
/// warning.
///
/// This call performs network I/O and may block for the duration of the
/// WebSocket synthesis. The read_aloud C ABI does not expose a timeout knob;
/// transport timeouts are reported through the returned error.
SynthesizeResult Synthesize(const std::string& text,
                            const std::string& voice,
                            const std::string& output_path,
                            const SynthesizeOptions& options = {});

/// Canonical Edge voice short name chosen for a caller supplied `voice` value.
/// Unknown/empty input resolves to `DefaultVoiceName()`. Exposed for tests and
/// diagnostics; does not perform network I/O.
std::string ResolveVoiceName(const std::string& voice);

/// Voice used when the caller does not request a known one:
/// "zh-CN-XiaoxiaoNeural".
std::string DefaultVoiceName();

/// True when the read_aloud Rust backend was compiled into this build
/// (CHATVV_HAVE_READ_ALOUD). When false, Synthesize() returns an explanatory
/// error and never touches the network.
bool ReadAloudAvailable();

}  // namespace chatvv
