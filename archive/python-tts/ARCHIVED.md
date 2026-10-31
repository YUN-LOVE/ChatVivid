# ARCHIVED · Python edge-tts sidecar

> **2026-10-31 归档。** 旧 Web 版用的 edge-tts HTTP sidecar。
> 新 Flutter app 优先使用系统 TTS，不再依赖 Python/edge-tts。

## 内容

- `edge_tts_server.py`：`POST /tts`，返回 base64 MP3 + WordBoundary。
- `README.md`：旧安装/运行说明。
- `requirements.txt`：`edge-tts`。

## 如果还想用

```bash
cd archive/python-tts
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python edge_tts_server.py --port 8010
```

- 需要联网访问 Microsoft 语音服务。
- 依赖 Python，不适合作为移动端内置方案。
- 新 app 的 TTS 设计见 `docs/flutter-app-design.md`（系统 TTS 优先）。
