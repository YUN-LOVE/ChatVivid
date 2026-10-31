#pragma once

#include <condition_variable>
#include <cstdint>
#include <map>
#include <mutex>
#include <string>
#include <vector>

namespace chatvv {

struct HubEvent {
  int64_t seq = 0;
  std::string type;
  std::string data;
};

struct WaitResult {
  std::vector<HubEvent> events;
  bool done = false;
  bool found = true;
};

// In-process fan-out for live SSE subscribers. Durable replay comes from SQLite;
// the hub only covers the current process lifetime.
class ResponseHub {
 public:
  void open(const std::string& id);
  void publish(const std::string& id, int64_t seq, const std::string& type,
               const std::string& data);
  void finish(const std::string& id);
  WaitResult wait(const std::string& id, int64_t after_seq, int timeout_ms);
  bool known(const std::string& id);

 private:
  struct State {
    std::vector<HubEvent> events;
    bool done = false;
  };

  std::mutex mu_;
  std::condition_variable cv_;
  std::map<std::string, State> states_;
};

}  // namespace chatvv
