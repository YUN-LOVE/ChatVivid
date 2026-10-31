#pragma once

#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

struct sqlite3;

namespace chatvv {

struct Message {
  std::string id;
  int64_t seq = 0;
  std::string role;
  std::string content;
  std::string rendered;  // JSON array of content parts, or empty
  std::string response_id;
  int64_t created_at = 0;
};

struct ResponseRow {
  std::string id;
  std::string status = "in_progress";
  std::string model;
  std::string instructions;
  std::string input_meta = "{}";
  std::string output;
  std::string usage;
  std::string error;
  int64_t created_at = 0;
  int64_t completed_at = 0;
};

struct Memory {
  std::string id;
  std::string text;
  int64_t created_at = 0;
  int64_t last_used_at = 0;
  int use_count = 0;
  double importance = 0.5;
  int durability = 3;
  std::string status = "active";
};

struct ArchiveResult {
  Memory memory;
  int archived_messages = 0;
  int64_t cutoff_seq = 0;
};

struct StoredEvent {
  int64_t seq = 0;
  std::string type;
  std::string data;
};

class Db {
 public:
  explicit Db(const std::string& path);
  ~Db();
  Db(const Db&) = delete;
  Db& operator=(const Db&) = delete;

  void migrate();

  Message append_message(const std::string& role, const std::string& content,
                         const std::string& rendered_json,
                         const std::string& response_id);
  std::vector<Message> list_messages(int limit, int64_t before_seq,
                                     int64_t after_seq, bool* has_more);
  int64_t max_seq();

  Memory append_memory(const std::string& text, double importance = 0.5,
                       int durability = 3);
  std::vector<Memory> list_memories(int limit, const std::string& query);
  bool delete_memory(const std::string& id);
  void mark_memory_used(const std::string& id);
  int64_t archive_cutoff();
  ArchiveResult archive_messages(int keep_recent, int max_chars = 6000);

  void create_response(const ResponseRow& row);
  void update_response(const std::string& id, const std::string& status,
                       const std::string& output, const std::string& usage,
                       const std::string& error, int64_t completed_at);
  std::optional<ResponseRow> get_response(const std::string& id);
  std::string response_status(const std::string& id);

  void append_event(const std::string& response_id, int64_t seq,
                    const std::string& type, const std::string& data);
  std::vector<StoredEvent> list_events(const std::string& response_id,
                                       int64_t after_seq);

 private:
  void exec_locked(const std::string& sql);

  sqlite3* db_ = nullptr;
  std::mutex mu_;
};

}  // namespace chatvv
