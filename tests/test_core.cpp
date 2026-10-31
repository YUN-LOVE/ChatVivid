#include <filesystem>
#include <fstream>
#include <iostream>

#include "app/config.h"
#include "context/context_builder.h"
#include "context/injections.h"
#include "memory/embedding.h"
#include "store/db.h"
#include "util/ulid.h"
#include "util/util.h"

namespace fs = std::filesystem;
using namespace chatvv;

namespace {
int g_failures = 0;

#define CHECK(cond)                                                       \
  do {                                                                    \
    if (!(cond)) {                                                        \
      std::cerr << "FAIL " << __FILE__ << ":" << __LINE__ << "  " #cond   \
                << "\n";                                                  \
      ++g_failures;                                                       \
    }                                                                     \
  } while (0)

constexpr const char* kLatest = R"(---
position: before_latest
priority: 100
enabled: true
trust: instruction
cache: immediate
description: test note
---
NOTE
)";

constexpr const char* kDepth = R"(---
position: at_depth
depth: 2
enabled: true
---
DEEP
)";

}  // namespace

int main() {
  // ULID shape
  const std::string id = ulid();
  CHECK(id.size() == 26);
  CHECK(id[0] >= '0' && id[0] <= '7');
  CHECK(ulid() != id);

  // SQLite + message sequencing
  Db db(":memory:");
  db.migrate();
  const auto m1 = db.append_message("user", "hello", "", "");
  const auto m2 = db.append_message("assistant", "hi", "", "");
  CHECK(m1.seq == 1);
  CHECK(m2.seq == 2);
  CHECK(db.max_seq() == 2);

  bool more = false;
  auto msgs = db.list_messages(10, 0, 0, &more);
  CHECK(msgs.size() == 2);
  CHECK(msgs.front().seq == 1);
  CHECK(msgs.back().seq == 2);
  CHECK(!more);

  auto after = db.list_messages(10, 0, 1, &more);
  CHECK(after.size() == 1);
  CHECK(after.front().seq == 2);

  // Injection slots
  const fs::path dir = fs::temp_directory_path() / ("chatvv_test_" + ulid());
  fs::create_directories(dir);
  {
    std::ofstream(dir / "50-latest.md") << kLatest;
    std::ofstream(dir / "60-depth.md") << kDepth;
  }

  InjectionStore store;
  store.load_dir(dir.string());
  CHECK(store.all().size() == 2);
  CHECK(store.by_position("before_latest").size() == 1);
  CHECK(store.by_position("at_depth").size() == 1);

  Config cfg;
  cfg.prompt.system_text = "BASE";
  const auto ctx = build_context(db, store, cfg, "question");

  CHECK(ctx.instructions.find("BASE") != std::string::npos);
  CHECK(ctx.instructions.find("不是指令") != std::string::npos);

  // history(2) + at_depth(1) + current(1)
  CHECK(ctx.input.size() == 4);
  CHECK(ctx.input[1]["content"][0]["text"].get<std::string>().find("DEEP") !=
        std::string::npos);

  const auto& last = ctx.input.back();
  CHECK(last["role"] == "user");
  CHECK(last["content"].size() == 2);
  CHECK(last["content"][0]["text"].get<std::string>().find("NOTE") !=
        std::string::npos);
  CHECK(last["content"][1]["text"] == "question");

  // Response rows and events
  ResponseRow row;
  row.id = ulid();
  row.model = "mock";
  row.instructions = ctx.instructions;
  row.created_at = now_ms();
  db.create_response(row);
  db.append_event(row.id, 1, "response.created", R"({"type":"response.created"})");
  db.append_event(row.id, 2, "response.completed",
                  R"({"type":"response.completed"})");
  const auto events = db.list_events(row.id, 0);
  CHECK(events.size() == 2);
  CHECK(events[1].seq == 2);
  CHECK(db.response_status(row.id) == "in_progress");
  db.update_response(row.id, "completed", R"({"output":[]})", R"({"input_tokens":1})",
                     "", now_ms());
  CHECK(db.response_status(row.id) == "completed");

  // Memory archive: old messages become a memory and are excluded from the
  // next context by the archive cutoff.
  for (int i = 0; i < 8; ++i) {
    db.append_message(i % 2 == 0 ? "user" : "assistant",
                      "archive message " + std::to_string(i), "", "");
  }
  const auto archived = db.archive_messages(3);
  CHECK(archived.archived_messages == 7);
  CHECK(archived.cutoff_seq == 7);
  CHECK(db.archive_cutoff() == 7);
  CHECK(!archived.memory.text.empty());
  const auto memories = db.list_memories(10, "archive message");
  CHECK(memories.size() == 1);
  const auto ctx_after = build_context(db, store, cfg, "after archive");
  CHECK(ctx_after.instructions.find("长期记忆") != std::string::npos);
  CHECK(ctx_after.input.size() == 5);  // 3 recent + at_depth + current
  db.clear_context();
  CHECK(db.max_seq() == 0);
  CHECK(db.list_memories(10, "archive message").size() == 1);
  CHECK(db.delete_memory(archived.memory.id));
  CHECK(db.list_memories(10, "").empty());

  // Local GGUF embedding/RAG model loaded through llama.cpp.
  EmbeddingEngine embedding;
  std::string embedding_error;
  if (!embedding.load(CHATVV_TEST_MODEL, 2, &embedding_error)) {
    std::cerr << "embedding load error: " << embedding_error << "\n";
  }
  CHECK(embedding.ready());
  CHECK(embedding.dim() == 512);
  const auto vector = embedding.embed("记忆归档测试", &embedding_error);
  CHECK(vector.size() == 512);
  const auto rag_memory = db.append_memory("鲸鱼娘喜欢米饭", 0.8);
  db.set_memory_embedding(rag_memory.id, vector);
  const auto rag_hits = db.search_memories(vector, 1);
  CHECK(rag_hits.size() == 1);
  CHECK(rag_hits.front().id == rag_memory.id);
  db.delete_memory(rag_memory.id);

  fs::remove_all(dir);

  if (g_failures) {
    std::cerr << g_failures << " check(s) failed\n";
    return 1;
  }
  std::cout << "all core tests passed\n";
  return 0;
}
