export interface VoiceOption {
  id: string;
  label: string;
  hint: string;
}

export const VOICES: VoiceOption[] = [
  { id: 'zh-CN-XiaoxiaoNeural', label: '晓晓', hint: '温柔 · 默认' },
  { id: 'zh-CN-XiaoyiNeural', label: '晓伊', hint: '清亮 · 少女' },
  { id: 'zh-CN-YunxiNeural', label: '云希', hint: '少年 · 轻快' },
  { id: 'ja-JP-NanamiNeural', label: '七海', hint: '日语 · 安静' },
];

export interface SpeechHandle {
  analyser: AnalyserNode;
  duration: number;
  onEnded: (callback: () => void) => void;
  stop: () => void;
}

function decodeBase64(value: string): ArrayBuffer {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

export function useTts(baseUrl: () => string, voice: () => string, volume: () => number) {
  let context: AudioContext | null = null;
  let active: SpeechHandle | null = null;
  let generation = 0;

  function audioContext(): AudioContext {
    if (!context) {
      const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      context = new Ctor();
    }
    if (context.state === 'suspended') void context.resume();
    return context;
  }

  async function speak(text: string): Promise<SpeechHandle | null> {
    stop();
    const clean = text.replace(/\s+/g, ' ').trim();
    if (!clean) return null;

    const gen = generation;
    try {
      const res = await fetch(`${baseUrl().replace(/\/+$/, '')}/tts`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: clean, voice: voice() }),
      });
      if (!res.ok) return null;
      const payload = (await res.json()) as { audio?: string };
      if (!payload.audio) return null;
      if (gen !== generation) return null;

      const ctx = audioContext();
      const buffer = await ctx.decodeAudioData(decodeBase64(payload.audio));
      if (gen !== generation) return null;

      const analyser = ctx.createAnalyser();
      analyser.fftSize = 512;
      analyser.smoothingTimeConstant = 0.55;
      const gain = ctx.createGain();
      gain.gain.value = Math.max(0, Math.min(1, volume()));

      const source = ctx.createBufferSource();
      source.buffer = buffer;
      source.connect(analyser);
      analyser.connect(gain);
      gain.connect(ctx.destination);

      let endedCallback: (() => void) | null = null;
      source.onended = () => {
        if (gen === generation) endedCallback?.();
      };

      const handle: SpeechHandle = {
        analyser,
        duration: buffer.duration,
        onEnded: (callback) => {
          endedCallback = callback;
        },
        stop: () => {
          source.onended = null;
          try {
            source.stop();
          } catch {
            // already stopped
          }
          source.disconnect();
          analyser.disconnect();
          gain.disconnect();
        },
      };

      source.start();
      active = handle;
      return handle;
    } catch {
      return null;
    }
  }

  function stop() {
    generation += 1;
    active?.stop();
    active = null;
  }

  function unlock() {
    const ctx = audioContext();
    if (ctx.state === 'suspended') void ctx.resume();
  }

  return { speak, stop, unlock };
}
