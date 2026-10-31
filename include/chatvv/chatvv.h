#ifndef CHATVV_CHATVV_H
#define CHATVV_CHATVV_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#if defined(CHATVV_FFI_BUILD)
#define CHATVV_API __declspec(dllexport)
#else
#define CHATVV_API __declspec(dllimport)
#endif
#else
#define CHATVV_API __attribute__((visibility("default")))
#endif

typedef struct chatvv_engine chatvv_engine;

typedef enum chatvv_event_type {
  CHATVV_EVENT_STARTED = 1,
  CHATVV_EVENT_DELTA = 2,
  CHATVV_EVENT_TOOL = 3,
  CHATVV_EVENT_COMPLETED = 4,
  CHATVV_EVENT_FAILED = 5,
  CHATVV_EVENT_CONTEXT = 6
} chatvv_event_type;

/*
 * event_json is UTF-8 JSON allocated by the library. The callback must copy
 * what it needs and then call chatvv_free(event_json). This ownership transfer
 * is required because NativeCallable.listener delivers callbacks
 * asynchronously; a pointer valid only for the native call would dangle.
 */
typedef void (*chatvv_event_cb)(void* user_data, int32_t event_type,
                                char* event_json);

/*
 * config_json is a UTF-8 JSON object. Recognized keys:
 *   data_dir, injections_dir, provider, base_url, endpoint, api_key,
 *   model, reasoning_effort, max_output_tokens, timeout_ms, system_prompt
 *
 * On failure returns NULL and, when error_json is non-NULL, stores a
 * NUL-terminated JSON error object that must be freed with chatvv_free().
 */
CHATVV_API chatvv_engine* chatvv_create(const char* config_json,
                                        char** error_json);

/* Stops workers, waits for callbacks, and frees the engine. */
CHATVV_API void chatvv_destroy(chatvv_engine* engine);

/*
 * Starts a turn. Returns a response id allocated by the library (free with
 * chatvv_free) or NULL on failure. Events are delivered asynchronously on a
 * worker thread until COMPLETED/FAILED.
 */
CHATVV_API char* chatvv_send(chatvv_engine* engine, const char* text,
                             chatvv_event_cb cb, void* user_data,
                             char** error_json);

/*
 * Same as chatvv_send, with per-turn injections. injections_json is a JSON
 * array of {name,position,mode,trust,description,content,depth,priority,
 * enabled}; it is used by prompt management and file attachments.
 */
CHATVV_API char* chatvv_send_ex(chatvv_engine* engine, const char* text,
                                const char* injections_json,
                                chatvv_event_cb cb, void* user_data,
                                char** error_json);

CHATVV_API void chatvv_cancel(chatvv_engine* engine,
                              const char* response_id);

/* Returns {"data":[...],"has_more":bool}; free with chatvv_free(). */
CHATVV_API char* chatvv_history(chatvv_engine* engine, int32_t limit,
                                int64_t before_seq, char** error_json);

/* Returns a JSON capability object; free with chatvv_free(). */
CHATVV_API char* chatvv_capabilities(chatvv_engine* engine,
                                     char** error_json);

/* Memory archive. JSON arrays/objects; free with chatvv_free(). */
CHATVV_API char* chatvv_memories(chatvv_engine* engine, int32_t limit,
                                 const char* query, char** error_json);
CHATVV_API char* chatvv_archive(chatvv_engine* engine, int32_t keep_recent,
                                char** error_json);
CHATVV_API int32_t chatvv_delete_memory(chatvv_engine* engine,
                                        const char* memory_id);

CHATVV_API void chatvv_free(char* value);

#ifdef __cplusplus
}
#endif

#endif  /* CHATVV_CHATVV_H */
