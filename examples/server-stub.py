#!/usr/bin/env python3
"""insights-share — self-host server stub.

Minimal HTTP server that conforms to references/server-protocol.md, just
enough for smoke testing the client + hooks + statusline. Not for production.

Storage: ~/.claude/insights/server-stub.json (single JSON array of cards).

Run: python3 examples/server-stub.py
"""
from __future__ import annotations

import json
import os
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

STORE = Path.home() / ".claude" / "insights" / "server-stub.json"
STORE.parent.mkdir(parents=True, exist_ok=True)
LOCK = threading.Lock()
STARTED_AT = time.time()


def _load() -> list[dict]:
    if not STORE.exists():
        return []
    try:
        return json.loads(STORE.read_text() or "[]")
    except Exception:
        return []


def _save(cards: list[dict]) -> None:
    STORE.write_text(json.dumps(cards, indent=2, ensure_ascii=False))


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _new_id() -> str:
    return "ins_" + secrets.token_hex(6)


class Handler(BaseHTTPRequestHandler):
    server_version = "insights-share-stub/0.1"

    @staticmethod
    def _expand_tokens(q: str, cwd: str) -> list[str]:
        """Build a search token list from a free-text query plus a cwd path.
        cwd tokens are split on '/', filtered to >=4 chars, and depluralised
        so a path component like 'migrations' matches a card tagged 'migration'."""
        out: list[str] = []
        if q:
            out.append(q)
        if cwd:
            for raw in cwd.replace("/", " ").split():
                if len(raw) < 4:
                    continue
                out.append(raw)
                if raw.endswith("ies") and len(raw) > 4:
                    out.append(raw[:-3] + "y")
                elif raw.endswith("es") and len(raw) > 5:
                    out.append(raw[:-2])
                elif raw.endswith("s") and len(raw) > 4:
                    out.append(raw[:-1])
        seen: set[str] = set()
        deduped: list[str] = []
        for t in out:
            if t and t not in seen:
                seen.add(t)
                deduped.append(t)
        return deduped

    def _json(self, status: int, payload) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Insights-Server-Version", "v0.1-stub")
        self.end_headers()
        self.wfile.write(body)

    def _text(self, status: int, body: str) -> None:
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802
        url = urlparse(self.path)
        if url.path == "/healthz":
            return self._text(200, "ok")

        if url.path == "/insights":
            with LOCK:
                return self._json(200, _load())

        if url.path == "/insights/search":
            qs = parse_qs(url.query)
            q = (qs.get("q", [""])[0] or "").lower()
            cwd = (qs.get("cwd", [""])[0] or "").lower()
            with LOCK:
                cards = _load()
            if not q and not cwd:
                return self._json(200, [])
            tokens = self._expand_tokens(q, cwd)
            hits = []
            for c in cards:
                hay = " ".join(str(c.get(k, "")) for k in ("title", "trap", "fix")) + \
                      " " + ",".join(c.get("tags", []) or [])
                hay = hay.lower()
                if any(t in hay for t in tokens):
                    hits.append(c)
            return self._json(200, hits[:25])

        if url.path.startswith("/insights/"):
            target = url.path.split("/", 2)[2]
            with LOCK:
                for c in _load():
                    if c.get("id") == target:
                        return self._json(200, c)
            return self._json(404, {"error": "not_found", "message": target})

        if url.path == "/stats":
            qs = parse_qs(url.query)
            cwd = (qs.get("cwd", [""])[0] or "").lower()
            with LOCK:
                cards = _load()
            session_relevant = 0
            if cwd:
                tokens = self._expand_tokens("", cwd)
                for c in cards:
                    hay = " ".join(str(c.get(k, "")) for k in ("title", "trap", "fix")) + \
                          " " + ",".join(c.get("tags", []) or [])
                    if any(t in hay.lower() for t in tokens):
                        session_relevant += 1
            return self._json(200, {
                "total": len(cards),
                "new": 0,
                "session_relevant": session_relevant,
                "online": True,
                "last_sync_seconds_ago": int(time.time() - STARTED_AT),
            })

        return self._json(404, {"error": "not_found", "message": self.path})

    def do_POST(self):  # noqa: N802
        url = urlparse(self.path)
        if url.path != "/insights":
            return self._json(404, {"error": "not_found", "message": self.path})
        length = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            return self._json(400, {"error": "bad_json", "message": "invalid JSON body"})
        if not isinstance(body, dict) or not body.get("title"):
            return self._json(400, {"error": "bad_card", "message": "title required"})
        body.setdefault("tags", [])
        body.setdefault("scope", "project")
        body["id"] = _new_id()
        body["created_at"] = body["updated_at"] = _now()
        with LOCK:
            cards = _load()
            cards.append(body)
            _save(cards)
        return self._json(201, body)

    def do_PATCH(self):  # noqa: N802
        url = urlparse(self.path)
        if not url.path.startswith("/insights/"):
            return self._json(404, {"error": "not_found", "message": self.path})
        target = url.path.split("/", 2)[2]
        length = int(self.headers.get("Content-Length") or 0)
        try:
            patch = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            return self._json(400, {"error": "bad_json", "message": "invalid JSON body"})
        if not isinstance(patch, dict):
            return self._json(400, {"error": "bad_patch", "message": "object required"})
        for immut in ("id", "created_at"):
            patch.pop(immut, None)
        with LOCK:
            cards = _load()
            for c in cards:
                if c.get("id") == target:
                    c.update(patch)
                    c["updated_at"] = _now()
                    _save(cards)
                    return self._json(200, c)
        return self._json(404, {"error": "not_found", "message": target})

    def do_DELETE(self):  # noqa: N802
        url = urlparse(self.path)
        if not url.path.startswith("/insights/"):
            return self._json(404, {"error": "not_found", "message": self.path})
        target = url.path.split("/", 2)[2]
        with LOCK:
            cards = _load()
            for i, c in enumerate(cards):
                if c.get("id") == target:
                    cards.pop(i)
                    _save(cards)
                    return self._json(200, {"deleted": target})
        return self._json(404, {"error": "not_found", "message": target})

    def log_message(self, fmt, *args):
        # quiet by default; tail ~/.claude/insights/server.log if needed
        return


def main():
    host = os.environ.get("INSIGHTS_BIND_HOST", "127.0.0.1")
    port = int(os.environ.get("INSIGHTS_BIND_PORT", "7777"))
    srv = ThreadingHTTPServer((host, port), Handler)
    print(f"insights-share stub listening on http://{host}:{port} (store={STORE})")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
