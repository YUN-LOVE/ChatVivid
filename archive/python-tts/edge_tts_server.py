#!/usr/bin/env python3
"""Minimal edge-tts sidecar for chatvv.

POST /tts   {"text": "...", "voice": "zh-CN-XiaoxiaoNeural"}
GET  /health
GET  /voices

Returns JSON: {"audio": "<base64 mp3>", "boundaries": [...], "voice": "..."}
The frontend decodes the MP3 into an AudioBuffer and uses an AnalyserNode for
lip sync. Boundaries are kept for future viseme scheduling.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import logging
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    import edge_tts
except ImportError:  # pragma: no cover - startup guidance
    print("edge-tts is not installed. Run: tools/.venv/bin/pip install -r tools/requirements.txt", file=sys.stderr)
    raise

VOICES = [
    {"id": "zh-CN-XiaoxiaoNeural", "label": "晓晓", "hint": "温柔 · 默认"},
    {"id": "zh-CN-XiaoyiNeural", "label": "晓伊", "hint": "清亮 · 少女"},
    {"id": "zh-CN-YunxiNeural", "label": "云希", "hint": "少年 · 轻快"},
    {"id": "ja-JP-NanamiNeural", "label": "七海", "hint": "日语 · 安静"},
]
ALLOWED_VOICES = {voice["id"] for voice in VOICES}
DEFAULT_VOICE = "zh-CN-XiaoxiaoNeural"
MAX_CHARS = 2000
VOICE_RE = re.compile(r"^[A-Za-z]{2,3}-[A-Za-z]{2,4}-[A-Za-z0-9]+Neural$")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOG = logging.getLogger("chatvv.tts")


async def synthesize(text: str, voice: str) -> tuple[bytes, list[dict]]:
    communicate = edge_tts.Communicate(text, voice, boundary="WordBoundary")
    audio = bytearray()
    boundaries: list[dict] = []
    async for chunk in communicate.stream():
        if chunk["type"] == "audio":
            audio.extend(chunk["data"])
        elif chunk["type"] in ("WordBoundary", "SentenceBoundary"):
            boundaries.append(
                {
                    "type": chunk["type"],
                    "offset": round(chunk["offset"] / 10000.0, 2),
                    "duration": round(chunk["duration"] / 10000.0, 2),
                    "text": chunk["text"],
                }
            )
    return bytes(audio), boundaries


class Handler(BaseHTTPRequestHandler):
    server_version = "chatvv-tts/0.1"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:  # noqa: A003 - stdlib signature
        LOG.info("%s - %s", self.address_string(), fmt % args)

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Max-Age", "600")

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:  # noqa: N802 - stdlib signature
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802 - stdlib signature
        if self.path == "/health":
            self._json(200, {"ok": True, "voices": len(VOICES)})
            return
        if self.path == "/voices":
            self._json(200, {"voices": VOICES})
            return
        self._json(404, {"error": {"code": "not_found", "message": "no such route"}})

    def do_POST(self) -> None:  # noqa: N802 - stdlib signature
        if self.path != "/tts":
            self._json(404, {"error": {"code": "not_found", "message": "no such route"}})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > 64 * 1024:
            self._json(413, {"error": {"code": "payload_too_large", "message": "invalid body size"}})
            return

        try:
            payload = json.loads(self.rfile.read(length))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._json(400, {"error": {"code": "invalid_json", "message": "body is not JSON"}})
            return

        text = str(payload.get("text", "")).strip()
        if not text:
            self._json(400, {"error": {"code": "text_required", "message": "text must not be empty"}})
            return
        if len(text) > MAX_CHARS:
            self._json(413, {"error": {"code": "text_too_long", "message": f"text exceeds {MAX_CHARS} chars"}})
            return

        voice = str(payload.get("voice", DEFAULT_VOICE))
        if voice not in ALLOWED_VOICES and not VOICE_RE.match(voice):
            self._json(400, {"error": {"code": "invalid_voice", "message": "unsupported voice"}})
            return

        try:
            audio, boundaries = asyncio.run(synthesize(text, voice))
        except Exception as exc:  # network / provider errors
            LOG.exception("synthesis failed")
            self._json(502, {"error": {"code": "tts_failed", "message": str(exc)}})
            return

        if not audio:
            self._json(502, {"error": {"code": "no_audio", "message": "edge-tts returned no audio"}})
            return

        self._json(
            200,
            {
                "audio": base64.b64encode(audio).decode("ascii"),
                "boundaries": boundaries,
                "voice": voice,
                "chars": len(text),
                "bytes": len(audio),
            },
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="chatvv edge-tts sidecar")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8010)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    LOG.info("listening on http://%s:%d", args.host, args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        LOG.info("shutting down")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
