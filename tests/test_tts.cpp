// Unit tests for the read-aloud backed TTS wrapper (src/tts/synthesize.cpp).
//
// These tests are deliberately offline: they only exercise voice-name mapping,
// argument validation and the read_aloud C ABI helpers. They never open a
// socket. A real end-to-end synthesis test would require the Microsoft Edge
// read-aloud service and therefore belongs in the manual smoke checks.

#include "tts/synthesize.h"

#include <cstdio>
#include <string>
#include <vector>

#if defined(CHATVV_HAVE_READ_ALOUD)
extern "C" {
#include "read_aloud.h"
}
#endif

namespace {

int g_failures = 0;

void Check(bool condition, const char* expression, int line) {
  if (condition) return;
  std::fprintf(stderr, "FAIL:%d: %s\n", line, expression);
  ++g_failures;
}

void CheckEqual(const std::string& actual, const std::string& expected,
                const char* expression, int line) {
  if (actual == expected) return;
  std::fprintf(stderr, "FAIL:%d: %s\n  expected: %s\n  actual:   %s\n", line,
               expression, expected.c_str(), actual.c_str());
  ++g_failures;
}

void CheckErrorContains(const chatvv::SynthesizeResult& result,
                        const std::string& expected, const char* expression,
                        int line) {
  if (result.ok) {
    std::fprintf(stderr, "FAIL:%d: %s unexpectedly succeeded\n", line,
                 expression);
    ++g_failures;
    return;
  }
  if (result.error.find(expected) == std::string::npos) {
    std::fprintf(stderr,
                 "FAIL:%d: %s\n  expected substring: %s\n  actual error: %s\n",
                 line, expression, expected.c_str(), result.error.c_str());
    ++g_failures;
  }
}

#define CHECK(expr) Check((expr), #expr, __LINE__)
#define CHECK_EQ(actual, expected) \
  CheckEqual((actual), (expected), #actual " == " #expected, __LINE__)
#define CHECK_ERROR_CONTAINS(result, needle) \
  CheckErrorContains((result), (needle), #result " error contains " #needle, \
                     __LINE__)

void TestOptions() {
  chatvv::SynthesizeOptions options;
  CHECK(options.IsDefault());
  options.rate = 0.5f;
  CHECK(!options.IsDefault());
  options.rate = 0.0f;
  options.pitch_hz = -20;
  CHECK(!options.IsDefault());
  options.pitch_hz = 0;
  options.volume = -0.5f;
  CHECK(!options.IsDefault());
  options.volume = 0.0f;
  CHECK(options.IsDefault());

  // Argument validation happens before any network I/O, so this stays offline.
  const auto empty_text = chatvv::Synthesize("", "zh-CN-XiaoxiaoNeural",
                                             "/tmp/never.mp3", options);
  CHECK_ERROR_CONTAINS(empty_text, "text is empty");
  const auto empty_path = chatvv::Synthesize("hello", "zh-CN-XiaoxiaoNeural",
                                             "", options);
  CHECK_ERROR_CONTAINS(empty_path, "output_path is empty");
}

void TestDefaults() {
  CHECK_EQ(chatvv::DefaultVoiceName(), "zh-CN-XiaoxiaoNeural");
  // The Flutter app always requests this voice; it must round-trip unchanged.
  CHECK_EQ(chatvv::ResolveVoiceName("zh-CN-XiaoxiaoNeural"),
           "zh-CN-XiaoxiaoNeural");
}

void TestVoiceMapping() {
  if (!chatvv::ReadAloudAvailable()) {
    std::fprintf(stderr,
                 "SKIP: voice mapping assertions (read_aloud backend disabled, "
                 "stub build)\n");
    return;
  }

  // Empty and unknown voices fall back to the app default.
  CHECK_EQ(chatvv::ResolveVoiceName(""), "zh-CN-XiaoxiaoNeural");
  CHECK_EQ(chatvv::ResolveVoiceName("   "), "zh-CN-XiaoxiaoNeural");
  CHECK_EQ(chatvv::ResolveVoiceName("xx-YY-NoSuchNeural"),
           "zh-CN-XiaoxiaoNeural");

  // Case-insensitive and underscore variants.
  CHECK_EQ(chatvv::ResolveVoiceName("ZH-cn-xiaoxiaoneural"),
           "zh-CN-XiaoxiaoNeural");
  CHECK_EQ(chatvv::ResolveVoiceName("zh_CN_XiaoxiaoNeural"),
           "zh-CN-XiaoxiaoNeural");
  CHECK_EQ(chatvv::ResolveVoiceName("  zh-CN-XiaoxiaoNeural\t"),
           "zh-CN-XiaoxiaoNeural");

  // Full Microsoft Edge voice name form.
  CHECK_EQ(chatvv::ResolveVoiceName(
               "Microsoft Server Speech Text to Speech Voice (en-US, AriaNeural)"),
           "en-US-AriaNeural");
  CHECK_EQ(chatvv::ResolveVoiceName(
               "Microsoft Server Speech Text to Speech Voice (zh-CN, "
               "XiaoxiaoNeural)"),
           "zh-CN-XiaoxiaoNeural");

  // Common zh-CN and en-US/en-GB voices used by the app and its docs.
  const std::vector<std::string> voices = {
      "zh-CN-XiaoxiaoNeural",     "zh-CN-XiaoyiNeural",
      "zh-CN-YunxiNeural",        "zh-CN-YunyangNeural",
      "zh-CN-YunjianNeural",      "zh-CN-liaoning-XiaobeiNeural",
      "zh-CN-shaanxi-XiaoniNeural",
      "en-US-AriaNeural",         "en-US-AnaNeural",
      "en-US-AndrewNeural",       "en-US-AvaNeural",
      "en-US-BrianNeural",        "en-US-ChristopherNeural",
      "en-US-EmmaNeural",         "en-US-EricNeural",
      "en-US-GuyNeural",          "en-US-JennyNeural",
      "en-US-MichelleNeural",     "en-US-RogerNeural",
      "en-US-SteffanNeural",
      "en-US-AndrewMultilingualNeural",
      "en-US-AvaMultilingualNeural",
      "en-US-BrianMultilingualNeural",
      "en-GB-SoniaNeural",        "en-GB-RyanNeural",
      "en-GB-ThomasNeural",       "en-GB-LibbyNeural",
  };
  for (const std::string& voice : voices) {
    CHECK_EQ(chatvv::ResolveVoiceName(voice), voice);
  }

  // Every resolved voice must resolve to itself (idempotent canonical form).
  for (const std::string& voice : voices) {
    CHECK_EQ(chatvv::ResolveVoiceName(chatvv::ResolveVoiceName(voice)), voice);
  }
}

void TestParameterValidation() {
  const std::string voice = "zh-CN-XiaoxiaoNeural";

  // Empty text is rejected before any network access.
  const auto empty_text = chatvv::Synthesize("", voice, "out.mp3");
  CHECK(!empty_text.ok);
  CHECK(empty_text.audio_path.empty());
  CHECK_ERROR_CONTAINS(empty_text, "text is empty");

  // Empty output path is rejected before any network access.
  const auto empty_path = chatvv::Synthesize("hello", voice, "");
  CHECK(!empty_path.ok);
  CHECK_ERROR_CONTAINS(empty_path, "output_path is empty");

  // Invalid UTF-8 is rejected before any network access.
  const std::string invalid_utf8("\xC3\x28", 2);
  const auto bad_text = chatvv::Synthesize(invalid_utf8, voice, "out.mp3");
  CHECK(!bad_text.ok);
  CHECK_ERROR_CONTAINS(bad_text, "not valid UTF-8");

  const auto bad_path =
      chatvv::Synthesize("hello", voice, std::string("\xFF", 1));
  CHECK(!bad_path.ok);
  CHECK_ERROR_CONTAINS(bad_path, "output_path is not valid UTF-8");

  // Invalid UTF-8 voice is rejected before any network access, and never
  // reaches the JSON logger (which rejects invalid UTF-8 strings).
  const auto bad_voice =
      chatvv::Synthesize("hello", std::string("\xC3\x28", 2), "out.mp3");
  CHECK(!bad_voice.ok);
  CHECK_ERROR_CONTAINS(bad_voice, "voice is not valid UTF-8");

  // Stub builds must fail loudly instead of touching the network.
  if (!chatvv::ReadAloudAvailable()) {
    const auto unavailable = chatvv::Synthesize("hello", voice, "out.mp3");
    CHECK(!unavailable.ok);
    CHECK_ERROR_CONTAINS(unavailable, "not built");
  }
}

#if defined(CHATVV_HAVE_READ_ALOUD)
void TestReadAloudAbi() {
  // Linking the Rust staticlib proves the C ABI symbols are reachable.
  const char* status = read_aloud_status_string(READ_ALOUD_STATUS_SUCCESS);
  CHECK(status != nullptr);
  if (status != nullptr) CHECK_EQ(status, "success");

  const char* error = read_aloud_status_string(READ_ALOUD_STATUS_CONNECTION_FAILED);
  CHECK(error != nullptr);

  ReadAloudSpeechOptions options{};
  CHECK(read_aloud_speech_options_init(&options) == READ_ALOUD_STATUS_SUCCESS);
  CHECK(options.size > 0);
  CHECK(read_aloud_speech_options_init(nullptr) ==
        READ_ALOUD_STATUS_INVALID_INPUT);

  // Thread-local detail string: empty until a failure is recorded, never null.
  const char* last_error = read_aloud_last_error_message();
  CHECK(last_error != nullptr);

  // Null pointers must be rejected by the ABI itself, not crash.
  CHECK(read_aloud_text_to_speech(nullptr, VOICE_ZH_CN_XIAOXIAO_NEURAL, nullptr,
                                  "out.mp3") ==
        READ_ALOUD_STATUS_INVALID_INPUT);
  CHECK(read_aloud_text_to_speech("hello", VOICE_EN_US_ARIA_NEURAL, nullptr,
                                  nullptr) ==
        READ_ALOUD_STATUS_INVALID_INPUT);
}
#endif  // CHATVV_HAVE_READ_ALOUD

}  // namespace

int main() {
  TestOptions();
  std::fprintf(stderr,
               "tts tests: read_aloud backend %s\n",
               chatvv::ReadAloudAvailable() ? "enabled" : "disabled (stub)");
  TestDefaults();
  TestVoiceMapping();
  TestParameterValidation();
#if defined(CHATVV_HAVE_READ_ALOUD)
  TestReadAloudAbi();
#endif

  if (g_failures != 0) {
    std::fprintf(stderr, "tts tests: %d failure(s)\n", g_failures);
    return 1;
  }
  std::printf("tts tests ok\n");
  return 0;
}
