#include "tts/synthesize.h"

#include <algorithm>
#include <cstddef>
#include <filesystem>
#include <string>
#include <string_view>
#include <system_error>

#if defined(CHATVV_HAVE_READ_ALOUD)
// cbindgen emits a plain C header without `extern "C"` guards, so wrap it here
// to bind against the Rust `#[no_mangle]` C ABI symbols.
extern "C" {
#include "read_aloud.h"
}
#endif

#include "util/log.h"

namespace chatvv {
namespace {

constexpr std::string_view kDefaultVoice = "zh-CN-XiaoxiaoNeural";
constexpr std::string_view kFullVoicePrefix =
    "Microsoft Server Speech Text to Speech Voice (";
constexpr char kFullVoiceSuffix = ')';

std::string_view Trim(std::string_view value) {
  const auto is_space = [](char c) {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
  };
  while (!value.empty() && is_space(value.front())) value.remove_prefix(1);
  while (!value.empty() && is_space(value.back())) value.remove_suffix(1);
  return value;
}

/// ASCII-only case folding; voice names are ASCII. Avoids locale surprises.
char FoldAscii(char c) {
  return (c >= 'A' && c <= 'Z') ? static_cast<char>(c - 'A' + 'a') : c;
}

int CompareFold(std::string_view lhs, std::string_view rhs) {
  const std::size_t shared = std::min(lhs.size(), rhs.size());
  for (std::size_t i = 0; i < shared; ++i) {
    const unsigned char a = static_cast<unsigned char>(FoldAscii(lhs[i]));
    const unsigned char b = static_cast<unsigned char>(FoldAscii(rhs[i]));
    if (a != b) return a < b ? -1 : 1;
  }
  if (lhs.size() == rhs.size()) return 0;
  return lhs.size() < rhs.size() ? -1 : 1;
}

/// Returns false for malformed UTF-8 (overlongs, surrogates, > U+10FFFF).
bool IsValidUtf8(std::string_view text) {
  std::size_t i = 0;
  while (i < text.size()) {
    const unsigned char lead = static_cast<unsigned char>(text[i]);
    std::size_t extra = 0;
    unsigned int codepoint = 0;
    if (lead < 0x80) {
      ++i;
      continue;
    } else if ((lead & 0xE0) == 0xC0) {
      extra = 1;
      codepoint = lead & 0x1Fu;
    } else if ((lead & 0xF0) == 0xE0) {
      extra = 2;
      codepoint = lead & 0x0Fu;
    } else if ((lead & 0xF8) == 0xF0) {
      extra = 3;
      codepoint = lead & 0x07u;
    } else {
      return false;
    }
    if (i + extra >= text.size()) return false;
    for (std::size_t j = 1; j <= extra; ++j) {
      const unsigned char continuation =
          static_cast<unsigned char>(text[i + j]);
      if ((continuation & 0xC0) != 0x80) return false;
      codepoint = (codepoint << 6) | (continuation & 0x3Fu);
    }
    switch (extra) {
      case 1:
        if (codepoint < 0x80) return false;  // overlong
        break;
      case 2:
        if (codepoint < 0x800) return false;  // overlong
        if (codepoint >= 0xD800 && codepoint <= 0xDFFF) return false;
        break;
      case 3:
        if (codepoint < 0x10000 || codepoint > 0x10FFFF) return false;
        break;
      default:
        break;
    }
    i += extra + 1;
  }
  return true;
}

/// Normalize a caller supplied voice to the canonical Microsoft Edge short
/// name form ("zh-CN-XiaoxiaoNeural"). Accepts the full Edge name form and
/// underscores; returns "" when the input has no voice part.
std::string NormalizeVoiceName(std::string_view voice) {
  std::string_view value = Trim(voice);
  if (value.empty()) return {};
  if (value.size() > kFullVoicePrefix.size() &&
      value.back() == kFullVoiceSuffix &&
      CompareFold(value.substr(0, kFullVoicePrefix.size()),
                  kFullVoicePrefix) == 0) {
    const std::string_view inner =
        value.substr(kFullVoicePrefix.size(),
                     value.size() - kFullVoicePrefix.size() - 1);
    const std::size_t comma = inner.find(',');
    if (comma != std::string_view::npos) {
      const std::string_view locale = Trim(inner.substr(0, comma));
      const std::string_view name = Trim(inner.substr(comma + 1));
      if (!locale.empty() && !name.empty()) {
        return std::string(locale) + "-" + std::string(name);
      }
    }
    return {};
  }
  std::string normalized(value);
  std::replace(normalized.begin(), normalized.end(), '_', '-');
  return normalized;
}

#if defined(CHATVV_HAVE_READ_ALOUD)

// The table is generated from the vendored read_aloud voices.rs + cbindgen
// header by third_party/read_aloud/chatvv-gen-voice-table.py.
struct VoiceEntry {
  const char* name;
  Voice voice;
};

constexpr VoiceEntry kVoiceTable[] = {
#include "tts/read_aloud_voice_table.inc"
};

constexpr std::size_t kVoiceCount = sizeof(kVoiceTable) / sizeof(kVoiceTable[0]);

const VoiceEntry* FindVoice(std::string_view name) {
  // The table is sorted by case-insensitive canonical name.
  std::size_t low = 0;
  std::size_t high = kVoiceCount;
  while (low < high) {
    const std::size_t middle = low + (high - low) / 2;
    const int order = CompareFold(kVoiceTable[middle].name, name);
    if (order == 0) return &kVoiceTable[middle];
    if (order < 0) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return nullptr;
}

bool ContainsFold(std::string_view haystack, std::string_view needle) {
  if (needle.empty() || needle.size() > haystack.size()) return false;
  for (std::size_t i = 0; i + needle.size() <= haystack.size(); ++i) {
    if (CompareFold(haystack.substr(i, needle.size()), needle) == 0) {
      return true;
    }
  }
  return false;
}

/// Map read_aloud status codes to messages that keep the FFI/UI error shape
/// (a single human readable string). Connection errors are additionally
/// classified as timeouts; the read_aloud C ABI has no explicit timeout knob,
/// so the only signal available is the transport error text.
std::string DescribeStatus(ReadAloudStatus status, std::string_view detail) {
  const std::string_view trimmed = Trim(detail);
  const std::string suffix =
      trimmed.empty() ? std::string() : ": " + std::string(trimmed);
  switch (status) {
    case READ_ALOUD_STATUS_SUCCESS:
      return {};
    case READ_ALOUD_STATUS_INVALID_INPUT:
      return "invalid TTS input" + suffix;
    case READ_ALOUD_STATUS_CONNECTION_FAILED: {
      const bool timed_out = ContainsFold(trimmed, "timed out") ||
                             ContainsFold(trimmed, "timeout") ||
                             ContainsFold(trimmed, "deadline exceeded");
      return std::string(timed_out ? "TTS connection timed out"
                                   : "TTS connection failed") +
             suffix;
    }
    case READ_ALOUD_STATUS_PROTOCOL_ERROR:
      return "TTS protocol error" + suffix;
    case READ_ALOUD_STATUS_IO_ERROR:
      return "TTS I/O error" + suffix;
    case READ_ALOUD_STATUS_INTERNAL_ERROR:
      return "TTS internal error" + suffix;
    default:
      return "TTS failed (status " +
             std::to_string(static_cast<int>(status)) + ")" + suffix;
  }
}

#endif  // CHATVV_HAVE_READ_ALOUD

}  // namespace

std::string DefaultVoiceName() { return std::string(kDefaultVoice); }

bool ReadAloudAvailable() {
#if defined(CHATVV_HAVE_READ_ALOUD)
  return true;
#else
  return false;
#endif
}

std::string ResolveVoiceName(const std::string& voice) {
  if (!IsValidUtf8(voice)) {
    log_warn("tts_voice_invalid_utf8",
             {{"fallback", std::string(kDefaultVoice)}});
    return std::string(kDefaultVoice);
  }
  const std::string normalized = NormalizeVoiceName(voice);
  if (normalized.empty()) return std::string(kDefaultVoice);
#if defined(CHATVV_HAVE_READ_ALOUD)
  if (const VoiceEntry* entry = FindVoice(normalized)) {
    return entry->name;
  }
  // Unrecognized non-empty voices are caller mistakes and deserve a warning.
  log_warn("tts_voice_unknown",
           {{"requested", voice}, {"fallback", std::string(kDefaultVoice)}});
  return std::string(kDefaultVoice);
#else
  // Without the backend there is no voice table to validate against: pass the
  // normalized name through (Synthesize() itself fails with a stub error before
  // ever using it).
  return normalized;
#endif
}

SynthesizeResult Synthesize(const std::string& text, const std::string& voice,
                            const std::string& output_path,
                            const SynthesizeOptions& options) {
  SynthesizeResult result;
  if (text.empty()) {
    result.error = "text is empty";
    return result;
  }
  if (output_path.empty()) {
    result.error = "output_path is empty";
    return result;
  }
  if (!IsValidUtf8(text)) {
    result.error = "text is not valid UTF-8";
    return result;
  }
  if (!IsValidUtf8(output_path)) {
    result.error = "output_path is not valid UTF-8";
    return result;
  }
  if (!IsValidUtf8(voice)) {
    result.error = "voice is not valid UTF-8";
    return result;
  }

#if !defined(CHATVV_HAVE_READ_ALOUD)
  log_error("tts_unavailable", {{"voice", voice}});
  result.error =
      "TTS backend is not built (read_aloud was disabled at configure time)";
  return result;
#else
  const std::string canonical = ResolveVoiceName(voice);
  const VoiceEntry* entry = FindVoice(canonical);
  if (entry == nullptr) {
    // Unreachable: canonical is always one of DefaultVoiceName() or a table
    // entry. Guard anyway so a corrupted table can never pass garbage to Rust.
    log_error("tts_voice_table_corrupt", {{"voice", canonical}});
    result.error = "internal error: unknown TTS voice " + canonical;
    return result;
  }

  ReadAloudSpeechOptions speech_options{};
  speech_options.size = sizeof(ReadAloudSpeechOptions);
  speech_options.pitch_hz =
      std::clamp(options.pitch_hz, -500, 500);
  speech_options.rate = std::clamp(options.rate, -1.0f, 1.0f);
  speech_options.volume = std::clamp(options.volume, -1.0f, 1.0f);
  const ReadAloudSpeechOptions* speech_options_ptr =
      options.IsDefault() ? nullptr : &speech_options;

  auto attempt = [&](const VoiceEntry* voice_entry) {
    return read_aloud_text_to_speech(text.c_str(), voice_entry->voice,
                                     speech_options_ptr,
                                     output_path.c_str());
  };

  ReadAloudStatus status = attempt(entry);
  std::string used_voice = canonical;
  if (status != READ_ALOUD_STATUS_SUCCESS && canonical != DefaultVoiceName()) {
    // Some voices have been removed from the Edge Read Aloud service (e.g.
    // zh-CN-XiaomengNeural was retired in 2026-09) and close the socket while
    // others keep working. Fall back to the default voice instead of failing
    // the whole TTS call.
    const std::string fallback_voice = DefaultVoiceName();
    const VoiceEntry* fallback = FindVoice(fallback_voice);
    if (fallback != nullptr) {
      log_warn("tts_voice_fallback", {{"requested", canonical},
                                      {"fallback", fallback_voice}});
      status = attempt(fallback);
      if (status == READ_ALOUD_STATUS_SUCCESS) {
        used_voice = fallback_voice;
      }
    }
  }
  if (status != READ_ALOUD_STATUS_SUCCESS) {
    const char* detail = read_aloud_last_error_message();
    const std::string message =
        DescribeStatus(status, detail == nullptr ? std::string_view{}
                                                 : std::string_view(detail));
    log_warn("tts_failed", {{"voice", used_voice},
                            {"status", static_cast<int>(status)},
                            {"error", message}});
    result.error = message;
    return result;
  }

  // The C ABI reports success after creating the file; make sure a usable MP3
  // was actually produced (mirrors the old "no audio received" check).
  std::error_code error_code;
  const auto bytes = std::filesystem::file_size(output_path, error_code);
  if (error_code) {
    log_warn("tts_output_missing", {{"voice", used_voice},
                                    {"path", output_path},
                                    {"error", error_code.message()}});
    result.error = "TTS produced no readable output file: " +
                   error_code.message();
    return result;
  }
  if (bytes == 0) {
    std::error_code remove_error;
    std::filesystem::remove(output_path, remove_error);
    log_warn("tts_output_empty", {{"voice", used_voice}, {"path", output_path}});
    result.error = "no audio received (empty output)";
    return result;
  }

  result.ok = true;
  result.audio_path = output_path;
  log_info("tts_synthesized", {{"voice", used_voice}, {"bytes", bytes}});
  return result;
#endif  // CHATVV_HAVE_READ_ALOUD
}

}  // namespace chatvv
