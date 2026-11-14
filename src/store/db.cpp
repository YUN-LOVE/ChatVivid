#include "store/db.h"

#include <sqlite3.h>

#include <algorithm>
#include <cmath>
#include <stdexcept>

#include "util/log.h"
#include "util/ulid.h"
#include "util/util.h"

namespace chatvv {
namespace {

class Stmt {
 public:
  Stmt(sqlite3* db, const char* sql) {
    if (sqlite3_prepare_v2(db, sql, -1, &st_, nullptr) != SQLITE_OK) {
      throw std::runtime_error(std::string("sqlite prepare failed: ") +
                               sqlite3_errmsg(db) + " | " + sql);
    }
  }
  ~Stmt() {
    if (st_) sqlite3_finalize(st_);
  }
  Stmt(const Stmt&) = delete;
  Stmt& operator=(const Stmt&) = delete;

  void text(int i, const std::string& v) {
    sqlite3_bind_text(st_, i, v.c_str(), static_cast<int>(v.size()),
                      SQLITE_TRANSIENT);
  }
  void integer(int i, int64_t v) { sqlite3_bind_int64(st_, i, v); }
  void real(int i, double v) { sqlite3_bind_double(st_, i, v); }
  void null(int i) { sqlite3_bind_null(st_, i); }

  bool step() {
    const int rc = sqlite3_step(st_);
    if (rc == SQLITE_ROW) return true;
    if (rc == SQLITE_DONE) return false;
    throw std::runtime_error(std::string("sqlite step failed: ") +
                             sqlite3_errstr(rc));
  }

  std::string get_text(int i) {
    const auto* p = sqlite3_column_text(st_, i);
    return p ? std::string(reinterpret_cast<const char*>(p)) : std::string();
  }
  int64_t get_int(int i) { return sqlite3_column_int64(st_, i); }
  double get_double(int i) { return sqlite3_column_double(st_, i); }
  sqlite3_stmt* raw() { return st_; }
  const void* get_blob(int i) { return sqlite3_column_blob(st_, i); }
  int get_bytes(int i) { return sqlite3_column_bytes(st_, i); }

 private:
  sqlite3_stmt* st_ = nullptr;
};

}  // namespace

Db::Db(const std::string& path) {
  const int rc = sqlite3_open_v2(
      path.c_str(), &db_,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
      nullptr);
  if (rc != SQLITE_OK) {
    const std::string msg = db_ ? sqlite3_errmsg(db_) : "sqlite open failed";
    if (db_) sqlite3_close(db_);
    db_ = nullptr;
    throw std::runtime_error("cannot open database " + path + ": " + msg);
  }
  exec_locked("PRAGMA journal_mode=WAL;");
  exec_locked("PRAGMA synchronous=NORMAL;");
  exec_locked("PRAGMA foreign_keys=ON;");
  exec_locked("PRAGMA busy_timeout=5000;");
}

Db::~Db() {
  if (db_) sqlite3_close(db_);
}

void Db::exec_locked(const std::string& sql) {
  char* err = nullptr;
  if (sqlite3_exec(db_, sql.c_str(), nullptr, nullptr, &err) != SQLITE_OK) {
    const std::string msg = err ? err : "unknown error";
    sqlite3_free(err);
    throw std::runtime_error("sqlite exec failed: " + msg + " | " + sql);
  }
}

void Db::migrate() {
  std::lock_guard lock(mu_);
  exec_locked(R"sql(
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  seq INTEGER NOT NULL UNIQUE,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  rendered TEXT,
  response_id TEXT,
  created_at INTEGER NOT NULL
) STRICT;
CREATE INDEX IF NOT EXISTS idx_messages_seq ON messages(seq);

CREATE TABLE IF NOT EXISTS responses (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  model TEXT NOT NULL,
  instructions TEXT NOT NULL,
  input_meta TEXT NOT NULL DEFAULT '{}',
  output TEXT,
  usage TEXT,
  error TEXT,
  created_at INTEGER NOT NULL,
  completed_at INTEGER
) STRICT;

CREATE TABLE IF NOT EXISTS response_events (
  response_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  type TEXT NOT NULL,
  data TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (response_id, seq)
) STRICT, WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS memories (
  id TEXT PRIMARY KEY,
  text TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_used_at INTEGER,
  use_count INTEGER NOT NULL DEFAULT 0,
  importance REAL NOT NULL DEFAULT 0.5,
  durability INTEGER NOT NULL DEFAULT 3,
  embedding BLOB,
  status TEXT NOT NULL DEFAULT 'active'
) STRICT;

CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  spec TEXT NOT NULL,
  prompt TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  next_run_at INTEGER,
  last_run_at INTEGER,
  created_at INTEGER NOT NULL
) STRICT;

INSERT OR IGNORE INTO meta(key, value) VALUES ('message_seq', '0');
)sql");
}

Message Db::append_message(const std::string& role,
                           const std::string& content,
                           const std::string& rendered_json,
                           const std::string& response_id) {
  std::lock_guard lock(mu_);
  exec_locked("BEGIN IMMEDIATE");
  try {
    int64_t seq = 1;
    {
      Stmt q(db_, "SELECT COALESCE(MAX(seq), 0) + 1 FROM messages");
      if (q.step()) seq = q.get_int(0);
    }
    Message m;
    m.id = ulid();
    m.seq = seq;
    m.role = role;
    m.content = content;
    m.rendered = rendered_json;
    m.response_id = response_id;
    m.created_at = now_ms();

    Stmt ins(db_,
             "INSERT INTO messages(id, seq, role, content, rendered, "
             "response_id, created_at) VALUES(?, ?, ?, ?, ?, ?, ?)");
    ins.text(1, m.id);
    ins.integer(2, m.seq);
    ins.text(3, m.role);
    ins.text(4, m.content);
    if (m.rendered.empty()) {
      ins.null(5);
    } else {
      ins.text(5, m.rendered);
    }
    if (m.response_id.empty()) {
      ins.null(6);
    } else {
      ins.text(6, m.response_id);
    }
    ins.integer(7, m.created_at);
    ins.step();

    exec_locked("COMMIT");
    return m;
  } catch (...) {
    exec_locked("ROLLBACK");
    throw;
  }
}

std::vector<Message> Db::list_messages(int limit, int64_t before_seq,
                                       int64_t after_seq, bool* has_more) {
  if (limit <= 0) limit = 50;
  if (limit > 500) limit = 500;
  std::lock_guard lock(mu_);

  const char* sql = nullptr;
  if (after_seq > 0) {
    sql =
        "SELECT id, seq, role, content, rendered, response_id, created_at "
        "FROM messages WHERE seq > ? ORDER BY seq ASC LIMIT ?";
  } else if (before_seq > 0) {
    sql =
        "SELECT id, seq, role, content, rendered, response_id, created_at "
        "FROM messages WHERE seq < ? ORDER BY seq DESC LIMIT ?";
  } else {
    sql =
        "SELECT id, seq, role, content, rendered, response_id, created_at "
        "FROM messages ORDER BY seq DESC LIMIT ?";
  }

  Stmt q(db_, sql);
  if (after_seq > 0) {
    q.integer(1, after_seq);
    q.integer(2, limit);
  } else if (before_seq > 0) {
    q.integer(1, before_seq);
    q.integer(2, limit);
  } else {
    q.integer(1, limit);
  }

  std::vector<Message> out;
  while (q.step()) {
    Message m;
    m.id = q.get_text(0);
    m.seq = q.get_int(1);
    m.role = q.get_text(2);
    m.content = q.get_text(3);
    m.rendered = q.get_text(4);
    m.response_id = q.get_text(5);
    m.created_at = q.get_int(6);
    out.push_back(std::move(m));
  }

  const bool more = static_cast<int>(out.size()) >= limit;
  if (after_seq == 0) std::reverse(out.begin(), out.end());
  if (has_more) *has_more = more;
  return out;
}

int64_t Db::max_seq() {
  std::lock_guard lock(mu_);
  Stmt q(db_, "SELECT COALESCE(MAX(seq), 0) FROM messages");
  if (q.step()) return q.get_int(0);
  return 0;
}

void Db::create_response(const ResponseRow& row) {
  std::lock_guard lock(mu_);
  Stmt ins(db_,
           "INSERT INTO responses(id, status, model, instructions, "
           "input_meta, output, usage, error, created_at, completed_at) "
           "VALUES(?, ?, ?, ?, ?, NULL, NULL, NULL, ?, NULL)");
  ins.text(1, row.id);
  ins.text(2, row.status);
  ins.text(3, row.model);
  ins.text(4, row.instructions);
  ins.text(5, row.input_meta.empty() ? "{}" : row.input_meta);
  ins.integer(6, row.created_at);
  ins.step();
}

void Db::update_response(const std::string& id, const std::string& status,
                         const std::string& output, const std::string& usage,
                         const std::string& error, int64_t completed_at) {
  std::lock_guard lock(mu_);
  Stmt upd(db_,
           "UPDATE responses SET status = ?, output = ?, usage = ?, error = ?, "
           "completed_at = ? WHERE id = ?");
  upd.text(1, status);
  if (output.empty()) {
    upd.null(2);
  } else {
    upd.text(2, output);
  }
  if (usage.empty()) {
    upd.null(3);
  } else {
    upd.text(3, usage);
  }
  if (error.empty()) {
    upd.null(4);
  } else {
    upd.text(4, error);
  }
  if (completed_at > 0) {
    upd.integer(5, completed_at);
  } else {
    upd.null(5);
  }
  upd.text(6, id);
  upd.step();
}

std::optional<ResponseRow> Db::get_response(const std::string& id) {
  std::lock_guard lock(mu_);
  Stmt q(db_,
         "SELECT id, status, model, instructions, input_meta, output, usage, "
         "error, created_at, completed_at FROM responses WHERE id = ?");
  q.text(1, id);
  if (!q.step()) return std::nullopt;
  ResponseRow r;
  r.id = q.get_text(0);
  r.status = q.get_text(1);
  r.model = q.get_text(2);
  r.instructions = q.get_text(3);
  r.input_meta = q.get_text(4);
  r.output = q.get_text(5);
  r.usage = q.get_text(6);
  r.error = q.get_text(7);
  r.created_at = q.get_int(8);
  r.completed_at = q.get_int(9);
  return r;
}

std::string Db::response_status(const std::string& id) {
  std::lock_guard lock(mu_);
  Stmt q(db_, "SELECT status FROM responses WHERE id = ?");
  q.text(1, id);
  if (!q.step()) return {};
  return q.get_text(0);
}

void Db::append_event(const std::string& response_id, int64_t seq,
                      const std::string& type, const std::string& data) {
  std::lock_guard lock(mu_);
  Stmt ins(db_,
           "INSERT OR REPLACE INTO response_events(response_id, seq, type, "
           "data, created_at) VALUES(?, ?, ?, ?, ?)");
  ins.text(1, response_id);
  ins.integer(2, seq);
  ins.text(3, type);
  ins.text(4, data);
  ins.integer(5, now_ms());
  ins.step();
}

std::vector<StoredEvent> Db::list_events(const std::string& response_id,
                                         int64_t after_seq) {
  std::lock_guard lock(mu_);
  Stmt q(db_,
         "SELECT seq, type, data FROM response_events WHERE response_id = ? "
         "AND seq > ? ORDER BY seq ASC");
  q.text(1, response_id);
  q.integer(2, after_seq);
  std::vector<StoredEvent> out;
  while (q.step()) {
    out.push_back({q.get_int(0), q.get_text(1), q.get_text(2)});
  }
  return out;
}


std::vector<std::pair<std::string, StoredEvent>> Db::list_recent_events(
    int limit) {
  std::lock_guard lock(mu_);
  // Streaming text deltas would otherwise fill the window and hide
  // context.built / tool events; the developer view wants the structure, not
  // every token chunk.
  Stmt q(db_,
         "SELECT response_id, seq, type, data FROM response_events "
         "WHERE type <> 'response.output_text.delta' "
         "ORDER BY created_at DESC, seq DESC LIMIT ?");
  q.integer(1, limit);
  std::vector<std::pair<std::string, StoredEvent>> out;
  while (q.step()) {
    out.emplace_back(q.get_text(0),
                     StoredEvent{q.get_int(1), q.get_text(2), q.get_text(3)});
  }
  return out;
}

Memory Db::append_memory(const std::string& text, double importance,
                         int durability) {
  std::lock_guard lock(mu_);
  Memory memory;
  memory.id = ulid();
  memory.text = text;
  memory.created_at = now_ms();
  memory.importance = importance;
  memory.durability = durability;
  Stmt ins(db_,
           "INSERT INTO memories(id, text, created_at, last_used_at, "
           "use_count, importance, durability, embedding, status) "
           "VALUES(?, ?, ?, NULL, 0, ?, ?, NULL, 'active')");
  ins.text(1, memory.id);
  ins.text(2, memory.text);
  ins.integer(3, memory.created_at);
  ins.real(4, memory.importance);
  ins.integer(5, memory.durability);
  ins.step();
  return memory;
}

std::vector<Memory> Db::list_memories(int limit, const std::string& query) {
  if (limit <= 0) limit = 30;
  if (limit > 200) limit = 200;
  std::lock_guard lock(mu_);
  Stmt q(db_,
         "SELECT id, text, created_at, COALESCE(last_used_at, 0), use_count, "
         "importance, durability, status FROM memories "
         "WHERE status = 'active' AND (? = '' OR text LIKE '%' || ? || '%') "
         "ORDER BY created_at DESC LIMIT ?");
  q.text(1, query);
  q.text(2, query);
  q.integer(3, limit);
  std::vector<Memory> out;
  while (q.step()) {
    Memory m;
    m.id = q.get_text(0);
    m.text = q.get_text(1);
    m.created_at = q.get_int(2);
    m.last_used_at = q.get_int(3);
    m.use_count = static_cast<int>(q.get_int(4));
    m.importance = q.get_double(5);
    m.durability = static_cast<int>(q.get_int(6));
    m.status = q.get_text(7);
    out.push_back(std::move(m));
  }
  return out;
}

bool Db::delete_memory(const std::string& id) {
  std::lock_guard lock(mu_);
  Stmt del(db_, "DELETE FROM memories WHERE id = ?");
  del.text(1, id);
  del.step();
  return sqlite3_changes(db_) > 0;
}

void Db::mark_memory_used(const std::string& id) {
  std::lock_guard lock(mu_);
  Stmt upd(db_,
           "UPDATE memories SET last_used_at = ?, use_count = use_count + 1 "
           "WHERE id = ?");
  upd.integer(1, now_ms());
  upd.text(2, id);
  upd.step();
}

void Db::set_memory_embedding(const std::string& id,
                              const std::vector<float>& embedding) {
  if (embedding.empty()) return;
  std::lock_guard lock(mu_);
  Stmt upd(db_, "UPDATE memories SET embedding = ? WHERE id = ?");
  sqlite3_bind_blob(upd.raw(), 1, embedding.data(),
                    static_cast<int>(embedding.size() * sizeof(float)),
                    SQLITE_TRANSIENT);
  upd.text(2, id);
  upd.step();
}

std::vector<Memory> Db::search_memories(const std::vector<float>& query,
                                        int limit) {
  if (query.empty() || limit <= 0) return {};
  std::lock_guard lock(mu_);
  Stmt q(db_,
         "SELECT id, text, created_at, COALESCE(last_used_at, 0), use_count, "
         "importance, durability, status, embedding FROM memories "
         "WHERE status = 'active' AND embedding IS NOT NULL");
  struct Candidate {
    Memory memory;
    double score = 0.0;
  };
  std::vector<Candidate> candidates;
  while (q.step()) {
    const void* blob = q.get_blob(8);
    const int bytes = q.get_bytes(8);
    if (!blob || bytes <= 0 ||
        bytes % static_cast<int>(sizeof(float)) != 0) {
      continue;
    }
    const auto* values = static_cast<const float*>(blob);
    const size_t count = static_cast<size_t>(bytes / sizeof(float));
    if (count != query.size()) continue;
    double dot = 0.0;
    double norm = 0.0;
    for (size_t i = 0; i < count; ++i) {
      dot += static_cast<double>(values[i]) * query[i];
      norm += static_cast<double>(values[i]) * values[i];
    }
    if (norm <= 1e-12) continue;
    Memory memory;
    memory.id = q.get_text(0);
    memory.text = q.get_text(1);
    memory.created_at = q.get_int(2);
    memory.last_used_at = q.get_int(3);
    memory.use_count = static_cast<int>(q.get_int(4));
    memory.importance = q.get_double(5);
    memory.durability = static_cast<int>(q.get_int(6));
    memory.status = q.get_text(7);
    candidates.push_back({std::move(memory), dot / std::sqrt(norm)});
  }
  std::sort(candidates.begin(), candidates.end(),
            [](const Candidate& a, const Candidate& b) {
              return a.score > b.score;
            });
  std::vector<Memory> out;
  for (auto& candidate : candidates) {
    if (static_cast<int>(out.size()) >= limit) break;
    out.push_back(std::move(candidate.memory));
  }
  return out;
}

void Db::clear_context() {
  std::lock_guard lock(mu_);
  exec_locked("BEGIN IMMEDIATE");
  try {
    exec_locked("DELETE FROM response_events");
    exec_locked("DELETE FROM responses");
    exec_locked("DELETE FROM messages");
    exec_locked("INSERT OR REPLACE INTO meta(key, value) VALUES('message_seq', '0')");
    exec_locked("DELETE FROM meta WHERE key = 'archive_cutoff_seq'");
    exec_locked("COMMIT");
  } catch (...) {
    exec_locked("ROLLBACK");
    throw;
  }
  log_info("context.cleared", {});
}

int64_t Db::archive_cutoff() {
  std::lock_guard lock(mu_);
  Stmt q(db_, "SELECT value FROM meta WHERE key = 'archive_cutoff_seq'");
  if (!q.step()) return 0;
  try {
    return std::stoll(q.get_text(0));
  } catch (...) {
    return 0;
  }
}

ArchiveResult Db::archive_messages(int keep_recent, int max_chars) {
  if (keep_recent < 0) keep_recent = 0;
  if (keep_recent > 10000) keep_recent = 10000;
  if (max_chars < 256) max_chars = 256;
  std::lock_guard lock(mu_);

  ArchiveResult result;
  int64_t max_seq = 0;
  {
    Stmt q(db_, "SELECT COALESCE(MAX(seq), 0) FROM messages");
    if (q.step()) max_seq = q.get_int(0);
  }
  int64_t old_cutoff = 0;
  {
    Stmt q(db_, "SELECT value FROM meta WHERE key = 'archive_cutoff_seq'");
    if (q.step()) {
      try {
        old_cutoff = std::stoll(q.get_text(0));
      } catch (...) {
        old_cutoff = 0;
      }
    }
  }
  const int64_t target = std::max<int64_t>(0, max_seq - keep_recent);
  if (target <= old_cutoff) return result;

  std::vector<Message> messages;
  {
    Stmt q(db_,
           "SELECT id, seq, role, content, rendered, response_id, created_at "
           "FROM messages WHERE seq > ? AND seq <= ? ORDER BY seq ASC");
    q.integer(1, old_cutoff);
    q.integer(2, target);
    while (q.step()) {
      Message m;
      m.id = q.get_text(0);
      m.seq = q.get_int(1);
      m.role = q.get_text(2);
      m.content = q.get_text(3);
      m.rendered = q.get_text(4);
      m.response_id = q.get_text(5);
      m.created_at = q.get_int(6);
      messages.push_back(std::move(m));
    }
  }
  if (messages.empty()) return result;

  // Pair one user input with the following assistant reply. One memory per
  // exchange keeps RAG hits specific instead of matching a whole transcript.
  std::vector<std::pair<std::string, std::string>> units;
  std::string pending_user;
  for (const auto& message : messages) {
    if (message.role == "user") {
      if (!pending_user.empty()) {
        units.emplace_back(pending_user, "");
      }
      pending_user = message.content;
    } else if (message.role == "assistant") {
      if (!pending_user.empty()) {
        units.emplace_back(pending_user, message.content);
        pending_user.clear();
      } else {
        units.emplace_back("", message.content);
      }
    }
  }
  if (!pending_user.empty()) units.emplace_back(pending_user, "");
  if (units.empty()) return result;

  std::vector<Memory> created;
  created.reserve(units.size());
  const int64_t created_at = now_ms();
  for (const auto& [user_text, assistant_text] : units) {
    std::string text;
    if (!user_text.empty()) text += "用户: " + user_text;
    if (!assistant_text.empty()) {
      if (!text.empty()) text += "\n";
      text += "助理: " + assistant_text;
    }
    if (static_cast<int>(text.size()) > max_chars) {
      text.resize(static_cast<size_t>(max_chars));
      text += "\n…";
    }
    Memory memory;
    memory.id = ulid();
    memory.text = std::move(text);
    memory.created_at = created_at;
    memory.importance = 0.65;
    memory.durability = 3;
    created.push_back(std::move(memory));
  }

  exec_locked("BEGIN IMMEDIATE");
  try {
    Stmt ins(db_,
             "INSERT INTO memories(id, text, created_at, last_used_at, "
             "use_count, importance, durability, embedding, status) "
             "VALUES(?, ?, ?, NULL, 0, ?, ?, NULL, 'active')");
    for (const auto& memory : created) {
      sqlite3_reset(ins.raw());
      sqlite3_clear_bindings(ins.raw());
      ins.text(1, memory.id);
      ins.text(2, memory.text);
      ins.integer(3, memory.created_at);
      ins.real(4, memory.importance);
      ins.integer(5, memory.durability);
      ins.step();
    }
    Stmt meta(db_,
              "INSERT OR REPLACE INTO meta(key, value) "
              "VALUES('archive_cutoff_seq', ?)");
    meta.text(1, std::to_string(target));
    meta.step();
    exec_locked("COMMIT");
  } catch (...) {
    exec_locked("ROLLBACK");
    throw;
  }

  result.archived_messages = static_cast<int>(messages.size());
  result.cutoff_seq = target;
  result.memories = std::move(created);
  if (!result.memories.empty()) result.memory = result.memories.front();
  log_info("memory.archived",
           {{"messages", result.archived_messages},
            {"memories", result.memories.size()},
            {"cutoff", target}});
  return result;
}
}  // namespace chatvv
