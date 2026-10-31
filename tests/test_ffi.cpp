#include "chatvv/chatvv.h"

#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <iostream>
#include <mutex>
#include <string>

namespace {

struct CallbackState {
  std::mutex mu;
  std::condition_variable cv;
  bool completed = false;
  bool failed = false;
  int delta_count = 0;
  std::string text;
  std::string error;
};

std::string escape_json(const std::string& value) {
  std::string out;
  out.reserve(value.size());
  for (const char c : value) {
    if (c == '\\' || c == '"') out.push_back('\\');
    out.push_back(c);
  }
  return out;
}

void on_event(void* user_data, int32_t type, const char* event_json) {
  auto* state = static_cast<CallbackState*>(user_data);
  {
    std::lock_guard lock(state->mu);
    if (type == CHATVV_EVENT_DELTA) {
      ++state->delta_count;
      state->text += event_json ? event_json : "";
    } else if (type == CHATVV_EVENT_COMPLETED) {
      state->completed = true;
    } else if (type == CHATVV_EVENT_FAILED) {
      state->failed = true;
      state->error = event_json ? event_json : "";
    }
  }
  state->cv.notify_all();
}

}  // namespace

int main() {
  const auto data_dir =
      std::filesystem::current_path() / "ffi-test-data";
  std::filesystem::remove_all(data_dir);
  std::filesystem::create_directories(data_dir);

  const std::string config =
      "{\"data_dir\":\"" + escape_json(data_dir.string()) +
      "\",\"provider\":\"mock\",\"model\":\"mock\"}";

  char* error = nullptr;
  chatvv_engine* engine = chatvv_create(config.c_str(), &error);
  if (!engine) {
    std::cerr << "create failed: " << (error ? error : "null") << "\n";
    chatvv_free(error);
    return 1;
  }

  CallbackState state;
  char* response_id =
      chatvv_send(engine, "ffi smoke", &on_event, &state, &error);
  if (!response_id) {
    std::cerr << "send failed: " << (error ? error : "null") << "\n";
    chatvv_free(error);
    chatvv_destroy(engine);
    return 1;
  }

  {
    std::unique_lock lock(state.mu);
    state.cv.wait_for(lock, std::chrono::seconds(10),
                      [&] { return state.completed || state.failed; });
  }

  if (!state.completed || state.failed || state.delta_count == 0) {
    std::cerr << "event stream failed: completed=" << state.completed
              << " failed=" << state.failed
              << " deltas=" << state.delta_count << "\n";
    chatvv_free(response_id);
    chatvv_destroy(engine);
    return 1;
  }

  char* history = chatvv_history(engine, 10, 0, &error);
  if (!history) {
    std::cerr << "history failed: " << (error ? error : "null") << "\n";
    chatvv_free(error);
    chatvv_free(response_id);
    chatvv_destroy(engine);
    return 1;
  }
  const std::string history_json(history);
  if (history_json.find("\"role\":\"user\"") == std::string::npos ||
      history_json.find("\"role\":\"assistant\"") == std::string::npos) {
    std::cerr << "history missing user/assistant: " << history_json << "\n";
    chatvv_free(history);
    chatvv_free(response_id);
    chatvv_destroy(engine);
    return 1;
  }

  char* caps = chatvv_capabilities(engine, &error);
  if (!caps) {
    std::cerr << "capabilities failed: " << (error ? error : "null") << "\n";
    chatvv_free(error);
    chatvv_free(history);
    chatvv_free(response_id);
    chatvv_destroy(engine);
    return 1;
  }

  std::cout << "ffi ok: deltas=" << state.delta_count
            << " history_bytes=" << history_json.size() << "\n";

  chatvv_free(caps);
  chatvv_free(history);
  chatvv_free(response_id);
  chatvv_destroy(engine);
  std::filesystem::remove_all(data_dir);
  return 0;
}
