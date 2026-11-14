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

/*
 * ASR (speech-to-text) engine powered by the vendored whisper.cpp build and the
 * same ggml/Vulkan backend stack as the LLM path. See docs/asr.md.
 */
typedef struct chatvv_asr chatvv_asr;

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

/* Synthesize text to an MP3 file with Edge TTS. Returns 0 on success. */
CHATVV_API int32_t chatvv_tts_synthesize(const char* text, const char* voice,
                                          const char* output_path,
                                          char** error_json);

/*
 * Same as chatvv_tts_synthesize with Edge TTS prosody overrides.
 * options_json (optional) is {"pitch_hz":int,"rate":float,"volume":float};
 * rate/volume are relative -1..=1 (0 = service default), pitch_hz is a hertz
 * offset. Invalid/absent fields keep the service default. Returns 0 on success.
 */
CHATVV_API int32_t chatvv_tts_synthesize_opts(const char* text,
                                              const char* voice,
                                              const char* options_json,
                                              const char* output_path,
                                              char** error_json);

/* Memory archive. JSON arrays/objects; free with chatvv_free(). */
CHATVV_API char* chatvv_memories(chatvv_engine* engine, int32_t limit,
                                 const char* query, char** error_json);
CHATVV_API char* chatvv_archive(chatvv_engine* engine, int32_t keep_recent,
                                char** error_json);
CHATVV_API int32_t chatvv_delete_memory(chatvv_engine* engine,
                                        const char* memory_id);
CHATVV_API char* chatvv_save_context(chatvv_engine* engine, char** error_json);
CHATVV_API int32_t chatvv_clear_context(chatvv_engine* engine,
                                        char** error_json);

/*
 * ASR: speech-to-text with whisper.cpp.
 *
 * All ASR functions are thread-affine: one chatvv_asr owns one whisper context.
 * Transcriptions on the same chatvv_asr are serialized internally, but callers
 * must not call chatvv_asr_destroy concurrently with a transcription (use one
 * engine per worker thread or an external lock for that).
 *
 * Returned char* strings are UTF-8 JSON allocated by the library and must be
 * freed with chatvv_free(). On failure the functions return NULL and, when
 * error_json is non-NULL, store a {"code","message"} JSON object that must be
 * freed with chatvv_free().
 */

/*
 * Loads a ggml Whisper model (ggml-tiny.bin, ggml-base.bin, ...; models are not
 * shipped with the repository). model_path is a UTF-8 filesystem path.
 *
 * config_json is an optional UTF-8 JSON object:
 *   use_gpu    (bool, default true)  prefer the GPU (Vulkan) backend, with CPU fallback
 *   threads    (int,  default 0)     decoder threads, 0 = auto
 *   flash_attn (bool, default false) enable flash attention when supported
 *
 * Returns NULL on failure (missing/corrupt model, bad JSON, ...).
 */
CHATVV_API chatvv_asr* chatvv_asr_create(const char* model_path,
                                         const char* config_json,
                                         char** error_json);

/* Releases the engine and its model. NULL is ignored. */
CHATVV_API void chatvv_asr_destroy(chatvv_asr* asr);

/*
 * Transcribes a WAV file. Accepts RIFF/WAVE PCM 8/16/24/32-bit and IEEE
 * float32/float64, mono or multi-channel; any sample rate is linearly resampled
 * to 16 kHz mono.
 *
 * options_json is an optional UTF-8 JSON object:
 *   language  (string, default "auto") whisper language code ("zh", "en", ...)
 *   threads   (int,    default 0)      decoder threads, 0 = auto
 *   translate (bool,   default false)  translate to English (multilingual models)
 *
 * Success returns a JSON object:
 *   {"text": "...", "language": "zh", "model": "/path/model.bin",
 *    "duration_ms": 1234,
 *    "segments": [{"id": 0, "start_ms": 0, "end_ms": 1500, "text": "..."}]}
 */
CHATVV_API char* chatvv_asr_transcribe_file(chatvv_asr* asr,
                                            const char* wav_path,
                                            const char* options_json,
                                            char** error_json);

/*
 * Transcribes raw mono float32 PCM in [-1, 1] (little-endian on the wire).
 * sample_count is the number of float samples; sample_rate is their rate in Hz
 * (any positive rate; != 16000 is linearly resampled to 16 kHz). The buffer is
 * read synchronously and never retained, so it may be released after return.
 * Output/error contract is identical to chatvv_asr_transcribe_file().
 */
CHATVV_API char* chatvv_asr_transcribe_pcm(chatvv_asr* asr,
                                           const float* samples,
                                           int32_t sample_count,
                                           int32_t sample_rate,
                                           const char* options_json,
                                           char** error_json);

/*
 * Returns a JSON capability object for this build/engine: {"engine",
 * "version", "loaded", "model", "sample_rate", "audio_formats", "languages",
 * "backends", "gpu_available", "gpu_requested", "gpu_active", "flash_attn",
 * "threads", "supports_translate"}. asr may be NULL, in which case build-level
 * capabilities are returned. Free with chatvv_free().
 */
CHATVV_API char* chatvv_asr_capabilities(chatvv_asr* asr, char** error_json);

CHATVV_API void chatvv_free(char* value);

#ifdef __cplusplus
}
#endif

#endif  /* CHATVV_CHATVV_H */
