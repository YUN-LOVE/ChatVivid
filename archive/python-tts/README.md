# edge-tts sidecar

> **ARCHIVED 2026-10-31.** 旧 Web 版的 Python TTS sidecar，不再维护。
> 新 app 优先系统 TTS；归档说明见 [ARCHIVED.md](ARCHIVED.md)。


本地 TTS 服务。前端只依赖 HTTP 接口，不依赖 Python。

## 安装

```bash
cd tools
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

国内网络可以用镜像：

```bash
.venv/bin/pip install -i https://pypi.tuna.tsinghua.edu.cn/simple -r requirements.txt
```

## 运行

```bash
tools/.venv/bin/python tools/edge_tts_server.py --port 8010
```

或者在 `web/` 里：

```bash
pnpm tts
```

## 接口

```bash
curl -sS http://127.0.0.1:8010/health
curl -sS http://127.0.0.1:8010/voices
curl -sS -X POST http://127.0.0.1:8010/tts \
  -H 'Content-Type: application/json' \
  -d '{"text":"你好，我是水仙女。","voice":"zh-CN-XiaoxiaoNeural"}' \
  -o /tmp/tts.json
```

`POST /tts` 返回：

```json
{
  "audio": "<base64 mp3>",
  "boundaries": [{"offset": 0, "duration": 180, "text": "你好"}],
  "voice": "zh-CN-XiaoxiaoNeural",
  "chars": 10,
  "bytes": 27000
}
```

- `offset` / `duration` 单位是毫秒，来自 edge-tts 的 WordBoundary 事件。
- 前端当前用 Web Audio 的 AnalyserNode 做振幅口型；`boundaries` 预留给逐字 viseme。
- edge-tts 需要联网访问 Microsoft 的语音服务；离线时前端会提示 TTS 不可用，文字对话不受影响。
