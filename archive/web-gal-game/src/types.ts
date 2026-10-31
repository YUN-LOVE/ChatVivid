export interface Settings {
  modelId: string;
  apiBase: string;
  apiKey: string;
  ttsBase: string;
  voice: string;
  autoPlay: boolean;
  muted: boolean;
  volume: number;
}

export const DEFAULT_SETTINGS: Settings = {
  modelId: 'pmx',
  apiBase: 'http://127.0.0.1:8080',
  apiKey: '',
  ttsBase: 'http://127.0.0.1:8010',
  voice: 'zh-CN-XiaoxiaoNeural',
  autoPlay: true,
  muted: false,
  volume: 0.85,
};
