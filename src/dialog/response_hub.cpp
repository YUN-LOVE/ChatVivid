#include "dialog/response_hub.h"

#include <chrono>

namespace chatvv {

void ResponseHub::open(const std::string& id) {
  std::lock_guard lock(mu_);
  states_[id];
}

void ResponseHub::publish(const std::string& id, int64_t seq,
                          const std::string& type, const std::string& data) {
  {
    std::lock_guard lock(mu_);
    states_[id].events.push_back({seq, type, data});
  }
  cv_.notify_all();
}

void ResponseHub::finish(const std::string& id) {
  {
    std::lock_guard lock(mu_);
    states_[id].done = true;
  }
  cv_.notify_all();
}

WaitResult ResponseHub::wait(const std::string& id, int64_t after_seq,
                             int timeout_ms) {
  std::unique_lock lock(mu_);
  if (!states_.contains(id)) return {{}, false, false};

  auto ready = [&] {
    const auto& state = states_[id];
    if (state.done) return true;
    for (const auto& e : state.events) {
      if (e.seq > after_seq) return true;
    }
    return false;
  };
  cv_.wait_for(lock, std::chrono::milliseconds(timeout_ms), ready);

  auto& state = states_[id];
  WaitResult result;
  result.done = state.done;
  for (const auto& e : state.events) {
    if (e.seq > after_seq) result.events.push_back(e);
  }
  return result;
}

bool ResponseHub::known(const std::string& id) {
  std::lock_guard lock(mu_);
  return states_.contains(id);
}

}  // namespace chatvv
