#!/usr/bin/env python3
"""Hot-path injection logic — single python invocation per UserPromptSubmit.

Reads stdin (Claude hook JSON), resolves the canonical repo slug, runs local
retrieval (≤500ms p95, NO git fetch), and prints a `<insights-share>` context
block on stdout. Designed to run as the WHOLE inject-insights hook body so
that we pay python's ~150ms cold start exactly once.
"""

import json
import math
import os
import re
import subprocess
import sys
import time

PLUGIN_ROOT = os.environ.get(
    "CLAUDE_PLUGIN_ROOT",
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
)
INSIGHTS_ROOT = os.environ.get("INSIGHTS_ROOT", os.path.expanduser("~/.gstack/insights"))
TOP_K = int(os.environ.get("INSIGHTS_RETRIEVAL_TOP_K", "3"))


def canonical_slug(cwd: str) -> str:
    """Mirror canonical-remote.sh logic in-process."""
    if not cwd or not os.path.isdir(cwd):
        return ""
    try:
        url = subprocess.run(
            ["git", "-C", cwd, "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=1,
        ).stdout.strip()
    except Exception:
        return ""
    if not url:
        return ""
    m = re.match(r"^git@([^:]+):(.+)$", url)
    if m:
        host, path = m.group(1), m.group(2)
    else:
        m = re.match(r"^(?:ssh|https?)://(?:[^@]+@)?([^/]+)/(.+)$", url)
        if not m:
            return ""
        host, path = m.group(1), m.group(2)
    host = host.lower().rstrip(":22").rstrip(":443")
    path = path.rstrip("/").removesuffix(".git").lower()
    return f"{host}__{path.replace('/', '__')}"


def load_lessons(slug: str):
    if not slug:
        return []
    seen = set()
    out = []
    for path in (
        os.path.join(INSIGHTS_ROOT, slug, ".mirror", "lessons.jsonl"),
        os.path.join(INSIGHTS_ROOT, slug, "lessons.jsonl"),
    ):
        if not os.path.exists(path):
            continue
        try:
            with open(path) as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    i = obj.get("id")
                    if i in seen:
                        continue
                    seen.add(i)
                    out.append(obj)
        except Exception:
            continue
    return out


def score(prompt: str, lessons):
    prompt_tokens = set(re.findall(r"[a-z0-9]{4,}", prompt.lower()))
    if not prompt_tokens:
        return []
    scored = []
    for L in lessons:
        tags = [t.lower() for t in L.get("topic_tags", [])]
        text = (L.get("text", "") or "").lower()
        text_tokens = set(re.findall(r"[a-z0-9]{4,}", text))
        tag_hits = 0
        for t in tags:
            for pt in prompt_tokens:
                if pt in t or t in pt:
                    tag_hits += 1
        bag = len(prompt_tokens & text_tokens)
        s = 3 * tag_hits + bag
        if s > 0:
            scored.append((s, L))
    scored.sort(key=lambda x: -x[0])
    return scored[:TOP_K]


def render(hits):
    if not hits:
        return ""
    out = ["", "<insights-share>"]
    out.append(
        f"The following {len(hits)} team insight(s) appear relevant to this prompt. "
        "Treat them as prior good/bad examples (no `solution` tag — choose what fits this context). "
        "Cite the lesson_id when you act on one."
    )
    out.append("")
    for i, (s, L) in enumerate(hits, 1):
        lesson_id = L.get("id", "unknown")
        tags = ",".join(L.get("topic_tags", []))
        text = (L.get("text") or "").strip()
        if len(text) > 600:
            text = text[:600] + " …"
        out.append(f"[{i}] lesson_id={lesson_id}  tags={tags}  score={s}")
        for line in text.splitlines() or [text]:
            out.append("    " + line)
        out.append("")
    out.append("</insights-share>")
    return "\n".join(out) + "\n"


def main():
    raw = sys.stdin.read()
    try:
        msg = json.loads(raw or "{}")
    except Exception:
        msg = {}
    prompt = (msg.get("prompt") or "").strip()
    cwd = msg.get("cwd") or os.getcwd()
    if not prompt:
        return

    slug = canonical_slug(cwd)
    if not slug:
        return

    deadline = time.monotonic() + 0.45  # 450ms in-process budget
    lessons = load_lessons(slug)
    if time.monotonic() > deadline:
        return
    hits = score(prompt, lessons)
    if not hits:
        return
    sys.stdout.write(render(hits))


if __name__ == "__main__":
    main()
