<template>
  <section class="dialogue-panel font-sans">
    <div class="name-plate">
      <span class="text-[11px] font-medium tracking-[0.32em] text-gold-200">{{ speaker }}</span>
      <span class="text-[8px] tracking-[0.22em] text-ink-300/50">MEMORY ENTITY</span>
    </div>

    <div class="flex items-start gap-4 px-5 pb-2 pt-7 sm:px-8 sm:pt-8">
      <div class="min-h-[5.5rem] flex-1 cursor-pointer select-text" @click="activate">
        <p
          class="whitespace-pre-wrap text-[14px] leading-[1.95] text-ink-100 sm:text-[16px] sm:leading-[2.05]"
          :class="message?.error ? 'text-rose-200/90' : ''"
        >
          <span v-if="displayText">{{ displayText }}</span>
          <span v-else class="text-ink-300/40">……</span>
          <span v-if="typing" class="dialogue-cursor" />
        </p>
      </div>

      <div class="hidden w-24 shrink-0 flex-col items-end gap-3 pt-1 sm:flex">
        <span v-if="debug" class="font-mono text-[8px] text-gold-300/60">s{{ displayText.length }}/{{ fullText.length }}</span>
        <span class="text-[9px] tracking-[0.3em]" :class="online ? 'text-emerald-300/70' : 'text-rose-300/70'">
          {{ online ? 'LINKED' : 'OFFLINE' }}
        </span>
        <div v-if="speaking" class="flex h-4 items-end gap-[3px]">
          <span v-for="i in 4" :key="i" class="wave-bar" :style="{ height: `${6 + i * 2}px`, animationDelay: `${i * 0.12}s` }" />
        </div>
        <span v-else class="text-[9px] tracking-[0.24em] text-gold-300/45">
          {{ busy ? 'THINKING' : 'READY' }}
        </span>
      </div>
    </div>

    <div class="mx-5 h-px bg-gradient-to-r from-gold-400/30 via-gold-400/10 to-transparent sm:mx-8" />

    <form class="flex flex-col gap-3 px-5 pb-4 pt-3 sm:flex-row sm:items-center sm:gap-6 sm:px-8 sm:pb-5" @submit.prevent="submit">
      <label class="group flex flex-1 items-center gap-3 border-b border-white/10 pb-2 transition focus-within:border-gold-400/50">
        <span class="font-display text-lg leading-none text-gold-400/80">›</span>
        <input
          v-model="draft"
          type="text"
          :disabled="busy"
          class="w-full bg-transparent text-[13px] tracking-wide text-ink-100 outline-none placeholder:text-ink-300/35 disabled:cursor-not-allowed sm:text-sm"
          :placeholder="busy ? '正在组织语言…' : '说点什么，或者只是叫一声她的名字…'"
          autocomplete="off"
          spellcheck="false"
        />
      </label>

      <div class="flex items-center justify-between gap-4 sm:justify-end sm:gap-5">
        <div class="flex items-center gap-4 text-[9px] tracking-[0.28em]">
          <button
            type="button"
            class="transition hover:text-gold-200"
            :class="autoPlay ? 'text-gold-300' : 'text-ink-300/45'"
            @click="$emit('toggleAuto')"
          >
            AUTO
          </button>
          <button type="button" class="text-ink-300/45 transition hover:text-gold-200" @click="$emit('openHistory')">LOG</button>
          <button type="button" class="text-ink-300/45 transition hover:text-gold-200" @click="$emit('openSettings')">CONFIG</button>
        </div>

        <button
          type="submit"
          :disabled="busy || !draft.trim()"
          class="group flex items-center gap-2 border border-gold-400/25 bg-gold-400/10 px-4 py-2 text-[10px] tracking-[0.28em] text-gold-200 transition hover:border-gold-400/60 hover:bg-gold-400/20 disabled:cursor-not-allowed disabled:opacity-35"
        >
          发送
          <svg viewBox="0 0 24 24" class="h-3 w-3 fill-none stroke-current" stroke-width="1.6">
            <path d="M4 12h16M13 5l7 7-7 7" stroke-linecap="round" stroke-linejoin="round" />
          </svg>
        </button>
      </div>
    </form>
  </section>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import type { ChatMessage } from '../composables/useChat';

const props = defineProps<{
  message: ChatMessage | null;
  busy: boolean;
  online: boolean;
  speaking: boolean;
  autoPlay: boolean;
}>();

const emit = defineEmits<{
  send: [text: string];
  toggleAuto: [];
  openHistory: [];
  openSettings: [];
  interrupt: [];
}>();

const debug = typeof window !== 'undefined' && new URLSearchParams(window.location.search).has('debug');
const draft = ref('');
const displayText = ref('');
let timer: number | null = null;

const fullText = computed(() => props.message?.content ?? '');
const speaker = computed(() => (props.message?.role === 'user' ? '你' : '水仙女'));
const typing = computed(() => displayText.value.length < fullText.value.length);

function stopTimer() {
  if (timer !== null) {
    window.clearInterval(timer);
    timer = null;
  }
}

function startTimer() {
  stopTimer();
  timer = window.setInterval(() => {
    const goal = fullText.value;
    if (displayText.value.length >= goal.length) {
      if (!props.message?.streaming) stopTimer();
      return;
    }
    const remaining = goal.length - displayText.value.length;
    const step = Math.max(1, Math.min(4, Math.ceil(remaining / 9)));
    displayText.value = goal.slice(0, displayText.value.length + step);
  }, 22);
}

watch(
  () => props.message?.id,
  () => {
    displayText.value = '';
    startTimer();
  },
  { immediate: true },
);

watch(
  () => props.message?.content,
  () => {
    if (displayText.value.length > fullText.value.length) displayText.value = fullText.value;
    if (timer === null) startTimer();
  },
);

onBeforeUnmount(stopTimer);

function reveal() {
  displayText.value = fullText.value;
  stopTimer();
}

function activate() {
  reveal();
  if (props.speaking) emit('interrupt');
}

function submit() {
  const text = draft.value.trim();
  if (!text || props.busy) return;
  draft.value = '';
  emit('send', text);
}
</script>
