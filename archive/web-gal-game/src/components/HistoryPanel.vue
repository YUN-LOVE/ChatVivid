<template>
  <div class="fixed inset-0 z-50 grid place-items-center bg-black/55 px-4 backdrop-blur-sm" @click.self="$emit('close')">
    <section class="flex max-h-[82vh] w-full max-w-2xl flex-col border border-gold-400/20 bg-void-950/95 shadow-2xl">
      <header class="flex items-center justify-between border-b border-white/5 px-6 py-5">
        <div>
          <p class="font-display text-xl tracking-[0.28em] text-gold-200">LOG</p>
          <p class="mt-1 text-[9px] tracking-[0.3em] text-ink-300/50">对话记录 / {{ messages.length }}</p>
        </div>
        <button class="text-ink-300/60 transition hover:text-gold-200" aria-label="关闭" @click="$emit('close')">
          <svg viewBox="0 0 24 24" class="h-5 w-5 fill-none stroke-current" stroke-width="1.4">
            <path d="M6 6l12 12M18 6 6 18" stroke-linecap="round" />
          </svg>
        </button>
      </header>

      <div ref="list" class="scroll-slim flex-1 space-y-5 overflow-y-auto px-6 py-6">
        <p v-if="!messages.length" class="py-16 text-center text-sm text-ink-300/40">还没有记录。</p>
        <article v-for="message in messages" :key="message.id" class="flex gap-4">
          <span
            class="mt-1 h-1.5 w-1.5 shrink-0 rotate-45"
            :class="message.role === 'user' ? 'bg-ink-300/50' : 'bg-gold-400/80'"
          />
          <div class="min-w-0 flex-1">
            <div class="flex items-baseline gap-3">
              <span class="font-serif text-[11px] tracking-[0.2em]" :class="message.role === 'user' ? 'text-ink-300/70' : 'text-gold-300/80'">
                {{ message.role === 'user' ? '你' : '水仙女' }}
              </span>
              <span class="font-mono text-[9px] text-ink-300/30">{{ formatTime(message.createdAt) }}</span>
            </div>
            <p class="mt-1 whitespace-pre-wrap text-[13px] leading-relaxed text-ink-100/80">{{ message.content }}</p>
          </div>
        </article>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue';
import type { ChatMessage } from '../composables/useChat';

defineProps<{ messages: ChatMessage[] }>();
defineEmits<{ close: [] }>();

const list = ref<HTMLDivElement | null>(null);

function formatTime(timestamp: number): string {
  return new Date(timestamp).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
}

onMounted(() => {
  requestAnimationFrame(() => {
    if (list.value) list.value.scrollTop = list.value.scrollHeight;
  });
});
</script>
