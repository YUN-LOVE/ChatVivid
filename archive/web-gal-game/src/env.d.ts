/// <reference types="astro/client" />

interface ImportMetaEnv {
  readonly PUBLIC_API_BASE?: string;
  readonly PUBLIC_TTS_BASE?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
