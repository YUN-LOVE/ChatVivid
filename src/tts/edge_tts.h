#pragma once

#include <string>

namespace chatvv {

struct EdgeTtsResult {
  bool ok = false;
  std::string error;
  std::string audio_path;
};

/// Synthesize text with Microsoft Edge's read-aloud WebSocket service.
/// The implementation is intentionally self-contained so it can be called from
/// the embedded FFI layer without spawning Python.
EdgeTtsResult EdgeTtsSynthesize(const std::string& text,
                                const std::string& voice,
                                const std::string& output_path);

std::string EdgeTtsGenerateSecMsGec();

}  // namespace chatvv
