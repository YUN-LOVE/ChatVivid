import { reactive, ref } from 'vue';

export type ChatRole = 'user' | 'assistant';

export interface ChatMessage {
  id: string;
  role: ChatRole;
  content: string;
  createdAt: number;
  streaming?: boolean;
  error?: boolean;
  local?: boolean;
}

function newId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID();
  return Math.random().toString(36).slice(2);
}

function normalizeBase(base: string): string {
  return base.replace(/\/+$/, '');
}

function outputText(payload: unknown): string {
  const response = (payload as { response?: { output?: unknown } })?.response;
  const output = Array.isArray(response?.output) ? response?.output : [];
  let text = '';
  for (const item of output) {
    if (!item || typeof item !== 'object') continue;
    const record = item as { type?: string; content?: unknown };
    if (record.type !== 'message' || !Array.isArray(record.content)) continue;
    for (const part of record.content) {
      if (!part || typeof part !== 'object') continue;
      const p = part as { type?: string; text?: string };
      if (p.type === 'output_text' && p.text) text += p.text;
    }
  }
  return text;
}

async function readSse(
  body: ReadableStream<Uint8Array>,
  onEvent: (event: string, data: Record<string, unknown>) => void,
): Promise<void> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  const dispatch = (block: string) => {
    let event = 'message';
    const dataLines: string[] = [];
    for (const rawLine of block.split('\n')) {
      const line = rawLine.endsWith('\r') ? rawLine.slice(0, -1) : rawLine;
      if (!line || line.startsWith(':')) continue;
      if (line.startsWith('event:')) event = line.slice(6).trim();
      else if (line.startsWith('data:')) dataLines.push(line.slice(5).trim());
    }
    if (!dataLines.length) return;
    const raw = dataLines.join('\n');
    if (raw === '[DONE]') return;
    try {
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      onEvent(String(parsed.type ?? event), parsed);
    } catch {
      // Ignore malformed keepalive frames.
    }
  };

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    let index = buffer.indexOf('\n\n');
    while (index >= 0) {
      dispatch(buffer.slice(0, index));
      buffer = buffer.slice(index + 2);
      index = buffer.indexOf('\n\n');
    }
  }
  buffer += decoder.decode();
  if (buffer.trim()) dispatch(buffer);
}

export interface UseChatOptions {
  apiBase: () => string;
  apiKey?: () => string;
  onReply?: (message: ChatMessage) => void;
  onStatus?: (online: boolean) => void;
}

export function useChat(options: UseChatOptions) {
  const messages = ref<ChatMessage[]>([]);
  const authHeaders = (): Record<string, string> => {
    const key = options.apiKey?.().trim();
    return key ? { Authorization: `Bearer ${key}` } : {};
  };
  const busy = ref(false);
  const online = ref(false);
  let controller: AbortController | null = null;

  async function loadHistory() {
    try {
      const res = await fetch(`${normalizeBase(options.apiBase())}/v1/messages?limit=30`, {
        headers: authHeaders(),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const payload = (await res.json()) as {
        data?: Array<{ id?: string; role?: string; content?: string; created_at?: number }>;
      };
      const history = (payload.data ?? [])
        .filter((m) => (m.role === 'user' || m.role === 'assistant') && m.content)
        .map<ChatMessage>((m) => ({
          id: m.id ?? newId(),
          role: m.role as ChatRole,
          content: m.content ?? '',
          createdAt: m.created_at ?? Date.now(),
        }));
      if (history.length) messages.value = history;
      online.value = true;
      options.onStatus?.(true);
    } catch {
      online.value = false;
      options.onStatus?.(false);
    }
  }

  async function send(text: string) {
    const content = text.trim();
    if (!content || busy.value) return;
    busy.value = true;

    messages.value.push({
      id: newId(),
      role: 'user',
      content,
      createdAt: Date.now(),
    });

    const reply = reactive<ChatMessage>({
      id: newId(),
      role: 'assistant',
      content: '',
      createdAt: Date.now(),
      streaming: true,
    });
    messages.value.push(reply);

    controller = new AbortController();
    try {
      const res = await fetch(`${normalizeBase(options.apiBase())}/v1/turns`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...authHeaders() },
        body: JSON.stringify({ message: content, stream: true }),
        signal: controller.signal,
      });
      if (!res.ok || !res.body) {
        let detail = `HTTP ${res.status}`;
        try {
          const body = (await res.json()) as { error?: { message?: string } };
          if (body.error?.message) detail = body.error.message;
        } catch {
          // keep the status text
        }
        throw new Error(detail);
      }

      await readSse(res.body, (event, data) => {
        if (event === 'response.output_text.delta') {
          const delta = typeof data.delta === 'string' ? data.delta : '';
          reply.content += delta;
        } else if (event === 'response.completed') {
          const full = outputText(data);
          if (full) reply.content = full;
          reply.streaming = false;
        } else if (event === 'response.failed') {
          const response = data.response as { error?: { message?: string } } | undefined;
          throw new Error(response?.error?.message ?? '生成失败');
        } else if (event === 'response.incomplete') {
          reply.streaming = false;
        }
      });

      reply.streaming = false;
      if (!reply.content) reply.content = '……（没有收到内容）';
      online.value = true;
      options.onStatus?.(true);
      options.onReply?.(reply);
    } catch (error) {
      reply.streaming = false;
      reply.error = true;
      if (error instanceof DOMException && error.name === 'AbortError') {
        reply.content = reply.content || '……（已中断）';
      } else {
        online.value = false;
        options.onStatus?.(false);
        const detail = error instanceof Error ? error.message : String(error);
        reply.content =
          reply.content ||
          `……连接不上后端。\n请确认 chatvvd 在 ${normalizeBase(options.apiBase())} 运行。\n\n（${detail}）`;
      }
    } finally {
      busy.value = false;
      controller = null;
    }
  }

  function stop() {
    controller?.abort();
    controller = null;
  }

  return { messages, busy, online, loadHistory, send, stop };
}
