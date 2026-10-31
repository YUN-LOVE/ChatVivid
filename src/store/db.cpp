#include "store/db.h"

#include <sqlite3.h>

#include <algorithm>
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

}  // namespace chatvv
