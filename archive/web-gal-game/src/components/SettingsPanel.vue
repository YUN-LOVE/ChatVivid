<template>
  <div class="fixed inset-0 z-50 flex justify-end bg-black/45 backdrop-blur-sm" @click.self="$emit('close')">
    <aside class="flex h-full w-full max-w-sm flex-col border-l border-gold-400/20 bg-void-950/95 shadow-2xl">
      <header class="flex items-center justify-between border-b border-white/5 px-6 pb-4 pt-6">
        <div>
          <p class="font-display text-xl tracking-[0.28em] text-gold-200">CONFIG</p>
          <p class="mt-1 text-[9px] tracking-[0.3em] text-ink-300/50">SETTINGS / 调律</p>
        </div>
        <button class="text-ink-300/60 transition hover:text-gold-200" aria-label="关闭" @click="$emit('close')">
          <svg viewBox="0 0 24 24" class="h-5 w-5 fill-none stroke-current" stroke-width="1.4">
            <path d="M6 6l12 12M18 6 6 18" stroke-linecap="round" />
          </svg>
        </button>
      </header>

      <div class="scroll-slim flex-1 space-y-7 overflow-y-auto px-6 py-6 text-sm">
        <section class="space-y-3">
          <p class="text-[9px] tracking-[0.32em] text-gold-400/70">MODEL / 模型</p>
          <div class="space-y-2">
            <button
              v-for="entry in MODELS"
              :key="entry.id"
              class="flex w-full items-start justify-between gap-3 border px-3 py-3 text-left transition"
              :class="model.modelId === entry.id
                ? 'border-gold-400/60 bg-gold-400/10 text-gold-100'
                : 'border-white/8 bg-white/[0.02] text-ink-300/75 hover:border-gold-400/30'"
              @click="model.modelId = entry.id"
            >
              <span>
                <span class="block font-serif text-sm">{{ entry.label }}</span>
                <span class="mt-1 block text-[9px] leading-relaxed tracking-[0.08em] text-ink-300/45">{{ entry.note }}</span>
              </span>
              <span v-if="model.modelId === entry.id" class="mt-0.5 text-[8px] tracking-[0.2em] text-gold-300/80">ACTIVE</span>
            </button>
          </div>
          <p class="text-[10px] leading-relaxed text-ink-300/40">切换模型会刷新页面并重新加载骨骼。</p>
        </section>

        <section class="space-y-3">
          <p class="text-[9px] tracking-[0.32em] text-gold-400/70">VOICE / 声音</p>
          <div class="grid grid-cols-2 gap-2">
            <button
              v-for="voice in VOICES"
              :key="voice.id"
              class="border px-3 py-3 text-left transition"
              :class="model.voice === voice.id
                ? 'border-gold-400/60 bg-gold-400/10 text-gold-100'
                : 'border-white/8 bg-white/[0.02] text-ink-300/75 hover:border-gold-400/30'"
              @click="model.voice = voice.id"
            >
              <span class="block font-serif text-sm">{{ voice.label }}</span>
              <span class="mt-1 block text-[9px] tracking-[0.12em] text-ink-300/45">{{ voice.hint }}</span>
            </button>
          </div>
        </section>

        <section class="space-y-4">
          <p class="text-[9px] tracking-[0.32em] text-gold-400/70">PLAYBACK / 播放</p>

          <label class="flex items-center justify-between gap-4">
            <span class="text-ink-300/80">回复后自动朗读</span>
            <button
              role="switch"
              :aria-checked="model.autoPlay"
              class="relative h-6 w-11 rounded-full border transition"
              :class="model.autoPlay ? 'border-gold-400/60 bg-gold-400/25' : 'border-white/15 bg-white/10'"
              @click="model.autoPlay = !model.autoPlay"
            >
              <span
                class="absolute top-1/2 h-4 w-4 -translate-y-1/2 rounded-full transition-all"
                :class="model.autoPlay ? 'left-[22px] bg-gold-300' : 'left-1 bg-ink-300/50'"
              />
            </button>
          </label>

          <label class="block space-y-2">
            <span class="flex items-center justify-between text-ink-300/80">
              <span>音量</span>
              <span class="font-mono text-[10px] text-gold-300/70">{{ Math.round(model.volume * 100) }}%</span>
            </span>
            <input v-model.number="model.volume" type="range" min="0" max="1" step="0.05" class="w-full accent-[#d4b06a]" />
          </label>

          <div class="flex items-center gap-3">
            <button
              class="border border-gold-400/30 px-3 py-2 text-[10px] tracking-[0.24em] text-gold-200 transition hover:bg-gold-400/10 disabled:opacity-40"
              :disabled="!model.voice"
              @click="$emit('test')"
            >
              试听
            </button>
            <span class="text-[10px] tracking-[0.12em]" :class="statusColor">{{ statusText }}</span>
          </div>
        </section>

        <section class="space-y-3">
          <p class="text-[9px] tracking-[0.32em] text-gold-400/70">CONNECTION / 连接</p>
          <label class="block space-y-1.5">
            <span class="text-[11px] text-ink-300/60">后端 API</span>
            <input
              v-model.trim="model.apiBase"
              class="w-full border border-white/10 bg-white/[0.03] px-3 py-2 font-mono text-[11px] text-ink-100 outline-none transition focus:border-gold-400/50"
              spellcheck="false"
            />
          </label>
          <label class="block space-y-1.5">
            <span class="text-[11px] text-ink-300/60">API Key（可选）</span>
            <input
              v-model.trim="model.apiKey"
              type="password"
              class="w-full border border-white/10 bg-white/[0.03] px-3 py-2 font-mono text-[11px] text-ink-100 outline-none transition focus:border-gold-400/50"
              placeholder="留空表示后端未开启鉴权"
              autocomplete="off"
            />
          </label>
          <label class="block space-y-1.5">
            <span class="text-[11px] text-ink-300/60">TTS 服务</span>
            <input
              v-model.trim="model.ttsBase"
              class="w-full border border-white/10 bg-white/[0.03] px-3 py-2 font-mono text-[11px] text-ink-100 outline-none transition focus:border-gold-400/50"
              spellcheck="false"
            />
          </label>
          <button
            class="w-full border border-white/10 py-2 text-[10px] tracking-[0.24em] text-ink-300/70 transition hover:border-gold-400/40 hover:text-gold-200"
            @click="$emit('reconnect')"
          >
            重新连接
          </button>
          <p class="text-[10px] leading-relaxed text-ink-300/40">
            TTS 由 edge-tts 提供。先在仓库根目录运行 <code class="text-gold-300/70">pnpm --dir web tts</code>，
            或直接运行 <code class="text-gold-300/70">tools/.venv/bin/python tools/edge_tts_server.py</code>。
          </p>
        </section>
      </div>

      <footer class="border-t border-white/5 px-6 py-4 text-[9px] tracking-[0.26em] text-ink-300/30">
        CHATVV / MEMORY INTERFACE
      </footer>
    </aside>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { VOICES } from '../composables/useTts';
import { MODELS } from '../models';
import type { Settings } from '../types';

const model = defineModel<Settings>({ required: true });
const props = defineProps<{ ttsStatus: 'idle' | 'ok' | 'error' }>();
defineEmits<{ close: []; test: []; reconnect: [] }>();

const statusText = computed(() => {
  if (props.ttsStatus === 'ok') return 'TTS 正常';
  if (props.ttsStatus === 'error') return 'TTS 不可用';
  return '未测试';
});
const statusColor = computed(() =>
  props.ttsStatus === 'ok'
    ? 'text-emerald-300/70'
    : props.ttsStatus === 'error'
      ? 'text-rose-300/70'
      : 'text-ink-300/40',
);
</script>
