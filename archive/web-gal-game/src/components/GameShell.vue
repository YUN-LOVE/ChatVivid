<template>
  <div class="grain fixed inset-0 overflow-hidden bg-void-950">
    <div
      class="absolute inset-0 scale-[1.03] bg-cover bg-center"
      style="background-image: url('/backgrounds/kanazawa-night.jpg')"
    />
    <div class="absolute inset-0 bg-[radial-gradient(ellipse_at_50%_32%,rgba(28,44,60,0.06)_0%,rgba(6,7,13,0.48)_58%,rgba(6,7,13,0.95)_100%)]" />
    <div class="absolute inset-0 bg-gradient-to-b from-void-950/45 via-transparent to-void-950/95" />

    <div class="pointer-events-none absolute inset-0 z-[5]">
      <span
        v-for="(particle, index) in dust"
        :key="index"
        class="dust-dot"
        :style="{
          left: particle.left,
          top: particle.top,
          width: particle.size,
          height: particle.size,
          animationDelay: particle.delay,
          animationDuration: particle.duration,
        }"
      />
    </div>

    <CharacterStage
      ref="stageRef"
      class="absolute inset-0 z-10"
      :model-url="model.url"
      :model-type="model.type"
      :resource-path="model.resourcePath"
      :flip="model.flip ?? false"
      :arm-angle="model.armAngle"
      :forearm-angle="model.forearmAngle"
      :material-mode="model.materialMode"
      @ready="onStageReady"
      @progress="onStageProgress"
      @error="onStageError"
    />

    <div class="pointer-events-none absolute left-1/2 top-[48%] z-[6] h-[62%] w-[44%] -translate-x-1/2 -translate-y-1/2 rounded-full bg-void-950/35 blur-[90px]" />
    <div class="pointer-events-none absolute -left-40 top-0 z-[6] h-full w-[45%] rotate-12 bg-gradient-to-r from-gold-200/10 to-transparent blur-3xl" />
    <div class="pointer-events-none absolute inset-x-0 bottom-0 z-20 h-[54%] bg-gradient-to-t from-void-950 via-void-950/72 to-transparent" />

    <header class="absolute inset-x-0 top-0 z-30 flex items-center justify-between px-4 py-4 sm:px-8 sm:py-6">
      <div class="flex items-center gap-3">
        <div class="relative grid h-10 w-10 place-items-center border border-gold-400/25 bg-void-950/35 backdrop-blur">
          <span class="absolute h-2.5 w-2.5 rotate-45 border border-gold-400/60" />
          <span class="font-display text-[9px] tracking-[0.1em] text-gold-300/90">CV</span>
        </div>
        <div>
          <p class="font-display text-lg leading-none tracking-[0.4em] text-gold-100 sm:text-xl">CHATVV</p>
          <p class="mt-1.5 hidden text-[8px] tracking-[0.4em] text-ink-300/45 sm:block">MEMORY / 记忆体</p>
        </div>
      </div>

      <div class="flex items-center gap-2">
        <div class="mr-1 hidden items-center gap-2 border border-white/10 bg-void-950/30 px-3 py-1.5 backdrop-blur sm:flex">
          <span
            class="h-1.5 w-1.5 rounded-full"
            :class="online ? 'bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,0.75)]' : 'bg-rose-400/80'"
          />
          <span class="text-[9px] tracking-[0.3em] text-ink-300/55">{{ online ? 'LINKED' : 'OFFLINE' }}</span>
        </div>

        <button class="icon-btn" :title="settings.muted ? '取消静音' : '静音'" @click="toggleMute">
          <svg v-if="!settings.muted" viewBox="0 0 24 24" class="h-4 w-4 fill-none stroke-current" stroke-width="1.4">
            <path d="M11 5 6 9H3v6h3l5 4V5Z" stroke-linejoin="round" />
            <path d="M15.5 8.7a5 5 0 0 1 0 6.6M18.4 5.8a9.2 9.2 0 0 1 0 12.4" stroke-linecap="round" />
          </svg>
          <svg v-else viewBox="0 0 24 24" class="h-4 w-4 fill-none stroke-current" stroke-width="1.4">
            <path d="M11 5 6 9H3v6h3l5 4V5Z" stroke-linejoin="round" />
            <path d="M16 9.5 21 14.5M21 9.5 16 14.5" stroke-linecap="round" />
          </svg>
        </button>

        <button class="icon-btn" title="对话记录" @click="showHistory = true">
          <svg viewBox="0 0 24 24" class="h-4 w-4 fill-none stroke-current" stroke-width="1.4">
            <circle cx="12" cy="12" r="8.5" />
            <path d="M12 7.5V12l3 2" stroke-linecap="round" stroke-linejoin="round" />
          </svg>
        </button>

        <button class="icon-btn" title="设置" @click="showSettings = true">
          <svg viewBox="0 0 24 24" class="h-4 w-4 fill-none stroke-current" stroke-width="1.4">
            <circle cx="12" cy="12" r="2.6" />
            <path d="M12 3.5v2M12 18.5v2M3.5 12h2M18.5 12h2M6 6l1.4 1.4M16.6 16.6 18 18M18 6l-1.4 1.4M7.4 16.6 6 18" stroke-linecap="round" />
          </svg>
        </button>
      </div>
    </header>

    <main class="absolute inset-x-0 bottom-0 z-30 px-3 pb-3 sm:px-8 sm:pb-6 lg:px-16">
      <DialogueBox
        :message="current"
        :busy="busy"
        :online="online"
        :speaking="speaking"
        :auto-play="settings.autoPlay"
        @send="onSend"
        @toggle-auto="settings.autoPlay = !settings.autoPlay"
        @open-history="showHistory = true"
        @open-settings="showSettings = true"
        @interrupt="stopSpeech"
      />
    </main>

    <div
      v-if="debug"
      class="absolute right-3 top-20 z-50 max-w-[70vw] border border-gold-400/30 bg-void-950/90 p-3 font-mono text-[10px] leading-relaxed text-gold-200"
    >
      <p>messages={{ messages.length }} busy={{ busy }} online={{ online }}</p>
      <p>current={{ current?.id }} len={{ current?.content.length }}</p>
      <p>streaming={{ current?.streaming }} ready={{ ready }}</p>
    </div>

    <SettingsPanel
      v-if="showSettings"
      :model-value="settings"
      :tts-status="ttsStatus"
      @close="showSettings = false"
      @test="testVoice"
      @reconnect="reconnect"
    />
    <HistoryPanel v-if="showHistory" :messages="messages" @close="showHistory = false" />

    <Transition name="fade">
      <div v-if="!ready" class="absolute inset-0 z-50 grid place-items-center bg-void-950/88 backdrop-blur-md">
        <div class="w-72 text-center">
          <p class="font-display text-5xl tracking-[0.5em] text-gold-200">CHATVV</p>
          <p class="mt-4 text-[9px] tracking-[0.42em] text-ink-300/55">
            {{ loadError ? '载入失败' : '正在唤醒记忆体' }}
          </p>
          <div class="mx-auto mt-5 h-px w-44 overflow-hidden bg-white/10">
            <div class="h-full bg-gold-400/70 transition-all duration-300" :style="{ width: `${Math.round(progress * 100)}%` }" />
          </div>
          <p v-if="loadError" class="mt-4 break-words text-[11px] leading-relaxed text-rose-300/75">{{ loadError }}</p>
          <button
            v-if="loadError"
            class="mt-5 border border-gold-400/30 px-4 py-2 text-[10px] tracking-[0.24em] text-gold-200 transition hover:bg-gold-400/10"
            @click="reload"
          >
            重新载入
          </button>
          <button
            v-if="loadError && settings.modelId !== 'glb'"
            class="mt-3 block w-full border border-white/10 px-4 py-2 text-[10px] tracking-[0.2em] text-ink-300/70 transition hover:border-gold-400/30 hover:text-gold-200"
            @click="useFallbackModel"
          >
            使用 GLB 备用模型
          </button>
        </div>
      </div>
    </Transition>

    <Transition name="toast">
      <div
        v-if="toast"
        class="absolute bottom-28 left-1/2 z-50 -translate-x-1/2 border border-gold-400/25 bg-void-950/90 px-5 py-2.5 text-[10px] tracking-[0.16em] text-gold-200/80 shadow-xl backdrop-blur sm:bottom-36"
      >
        {{ toast }}
      </div>
    </Transition>
  </div>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue';
import CharacterStage from './CharacterStage.vue';
import DialogueBox from './DialogueBox.vue';
import HistoryPanel from './HistoryPanel.vue';
import SettingsPanel from './SettingsPanel.vue';
import { useChat, type ChatMessage } from '../composables/useChat';
import { useTts } from '../composables/useTts';
import { DEFAULT_SETTINGS, type Settings } from '../types';
import { getModel, MODELS } from '../models';
import type { CharacterStage as CharacterStageClass, StageDiagnostics } from '../three/CharacterStage';

type StageExposed = { stage: CharacterStageClass | null };

const debug = typeof window !== 'undefined' && new URLSearchParams(window.location.search).has('debug');
const stageRef = ref<StageExposed | null>(null);
const ready = ref(false);
const progress = ref(0);
const loadError = ref('');
const speaking = ref(false);
const ttsStatus = ref<'idle' | 'ok' | 'error'>('idle');
const showSettings = ref(false);
const showHistory = ref(false);
const toast = ref('');
let toastTimer: number | null = null;

function loadSettings(): Settings {
  if (typeof localStorage === 'undefined') return { ...DEFAULT_SETTINGS };
  try {
    const raw = JSON.parse(localStorage.getItem('chatvv.settings') ?? '{}') as Partial<Settings>;
    const merged = { ...DEFAULT_SETTINGS, ...raw };
    const requested = new URLSearchParams(window.location.search).get('model');
    if (requested && MODELS.some((candidate) => candidate.id === requested)) {
      merged.modelId = requested;
    }
    return merged;
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}

const settings = reactive<Settings>(loadSettings());
const bootModelId = settings.modelId;
watch(
  settings,
  (value) => localStorage.setItem('chatvv.settings', JSON.stringify(value)),
  { deep: true },
);

// Switching a 3D model replaces the whole skeleton/morph map; reloading is the
// safest way to dispose the old PMX/physics state and build the new stage.
watch(
  () => settings.modelId,
  (id) => {
    if (id === bootModelId) return;
    localStorage.setItem('chatvv.settings', JSON.stringify(settings));
    window.location.reload();
  },
);

const model = computed(() => getModel(settings.modelId));

const tts = useTts(
  () => settings.ttsBase,
  () => settings.voice,
  () => settings.volume,
);

const chat = useChat({
  apiBase: () => settings.apiBase,
  apiKey: () => settings.apiKey,
  onReply: (message) => {
    if (!settings.autoPlay || settings.muted) return;
    void speak(message.content);
  },
});

const { messages, busy, online, loadHistory, send } = chat;
const current = computed<ChatMessage | null>(() => messages.value[messages.value.length - 1] ?? null);

const dust = Array.from({ length: 18 }, (_, index) => ({
  left: `${(index * 37 + 11) % 100}%`,
  top: `${(index * 53 + 7) % 100}%`,
  size: `${1 + (index % 3) * 0.7}px`,
  delay: `${(index % 9) * 0.9}s`,
  duration: `${9 + (index % 6) * 2}s`,
}));

function stopSpeech() {
  tts.stop();
  speaking.value = false;
  const stage = stageRef.value?.stage;
  stage?.setSpeaking(false);
  stage?.setAnalyser(null);
}

async function speak(text: string) {
  const stage = stageRef.value?.stage ?? null;
  stopSpeech();
  const handle = await tts.speak(text);
  if (!handle) {
    ttsStatus.value = 'error';
    notify('TTS 不可用：先运行 pnpm tts，或检查设置里的 TTS 地址。');
    return;
  }
  ttsStatus.value = 'ok';
  speaking.value = true;
  stage?.setAnalyser(handle.analyser);
  stage?.setSpeaking(true);
  handle.onEnded(() => {
    speaking.value = false;
    stage?.setSpeaking(false);
    stage?.setAnalyser(null);
  });
}

function toggleMute() {
  settings.muted = !settings.muted;
  if (settings.muted) stopSpeech();
}

function onSend(text: string) {
  void send(text);
}

function testVoice() {
  void speak('你好，我是水仙女。今天也一起待一会儿吧。');
}

async function reconnect() {
  await loadHistory();
  notify(online.value ? '已重新连接后端。' : '仍然连接不上后端，请确认 chatvvd 正在运行。');
}

function onStageReady(diagnostics: StageDiagnostics) {
  ready.value = true;
  progress.value = 1;
  console.info('[chatvv] stage ready', diagnostics);
}

function onStageProgress(ratio: number) {
  progress.value = ratio;
}

function onStageError(message: string) {
  loadError.value = message;
}

function reload() {
  window.location.reload();
}

function useFallbackModel() {
  settings.modelId = 'glb';
  localStorage.setItem('chatvv.settings', JSON.stringify(settings));
  window.location.reload();
}

function notify(message: string) {
  toast.value = message;
  if (toastTimer !== null) window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => {
    toast.value = '';
    toastTimer = null;
  }, 4200);
}

onMounted(async () => {
  const unlock = () => tts.unlock();
  window.addEventListener('pointerdown', unlock, { once: true });

  await loadHistory();
  if (!messages.value.length) {
    messages.value.push({
      id: 'intro',
      role: 'assistant',
      content: '……你来了。\n今天，想从哪里开始？',
      createdAt: Date.now(),
      local: true,
    });
  }

  const params = new URLSearchParams(window.location.search);
  if (params.get('tts') === '0') settings.autoPlay = false;
  if (params.get('panel') === 'settings') showSettings.value = true;
  if (params.get('panel') === 'history') showHistory.value = true;
  if (params.has('demo')) {
    window.setTimeout(() => {
      void send('你好，初次见面。');
    }, 500);
  }
});

onBeforeUnmount(() => {
  chat.stop();
  tts.stop();
  if (toastTimer !== null) window.clearTimeout(toastTimer);
});
</script>
