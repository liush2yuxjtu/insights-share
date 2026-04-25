#!/usr/bin/env python3
"""Embedding-fallback retriever for insights-share.

Per design doc:
  Retrieval = topic-tag exact match → fallback to embedding similarity.
  Embedding model = sentence-transformers/all-MiniLM-L6-v2 bundled at plugin
  install via first-run pip install. ≤2s timeout (caller enforces).

Stdin: JSON {prompt: str, lessons: [card], top_k: int}
Stdout: JSON [card with `score` populated], top-k by cosine similarity.

Designed to degrade gracefully:
  - If sentence-transformers is not installed, falls back to TF-IDF cosine via
    Python stdlib. The model bundling is ideal but the fallback keeps the
    pipeline working in environments where the heavy dep is missing.
"""
import json
import math
import re
import sys
from collections import Counter


def tokenize(text: str):
    return re.findall(r"[a-z0-9]{3,}", (text or "").lower())


def tfidf_cosine(prompt_tokens, lessons):
    """Lightweight TF-IDF + cosine fallback (no extra deps)."""
    docs = [tokenize(L.get("text", "")) + [t.lower() for t in L.get("topic_tags", [])]
            for L in lessons]
    n = len(docs)
    if n == 0:
        return []
    df = Counter()
    for d in docs:
        for t in set(d):
            df[t] += 1

    def vector(tokens):
        tf = Counter(tokens)
        v = {}
        for t, c in tf.items():
            idf = math.log((n + 1) / (df.get(t, 0) + 1)) + 1
            v[t] = c * idf
        return v

    def cosine(a, b):
        common = set(a) & set(b)
        num = sum(a[t] * b[t] for t in common)
        da = math.sqrt(sum(x * x for x in a.values()))
        db = math.sqrt(sum(x * x for x in b.values()))
        if da == 0 or db == 0:
            return 0.0
        return num / (da * db)

    qv = vector(prompt_tokens)
    out = []
    for L, d in zip(lessons, docs):
        score = cosine(qv, vector(d))
        if score > 0:
            scored = dict(L)
            scored["score"] = round(score, 4)
            out.append(scored)
    return out


def st_cosine(prompt, lessons):
    """Use sentence-transformers if available; otherwise return None."""
    try:
        from sentence_transformers import SentenceTransformer
        import numpy as np
    except Exception:
        return None
    model_name = "sentence-transformers/all-MiniLM-L6-v2"
    try:
        model = SentenceTransformer(model_name)
    except Exception:
        return None
    texts = [(L.get("text", "") + " " + " ".join(L.get("topic_tags", [])))
             for L in lessons]
    try:
        emb = model.encode([prompt] + texts, convert_to_numpy=True, show_progress_bar=False)
    except Exception:
        return None
    q = emb[0]
    docs = emb[1:]
    qn = q / (np.linalg.norm(q) + 1e-9)
    out = []
    for L, d in zip(lessons, docs):
        dn = d / (np.linalg.norm(d) + 1e-9)
        score = float(qn @ dn)
        if score > 0:
            scored = dict(L)
            scored["score"] = round(score, 4)
            out.append(scored)
    return out


def main():
    payload = json.loads(sys.stdin.read() or "{}")
    prompt = payload.get("prompt", "")
    lessons = payload.get("lessons", [])
    top_k = int(payload.get("top_k", 3))
    if not lessons:
        print("[]")
        return
    out = st_cosine(prompt, lessons)
    if out is None:
        out = tfidf_cosine(tokenize(prompt), lessons)
    out.sort(key=lambda x: -x.get("score", 0))
    print(json.dumps(out[:top_k]))


if __name__ == "__main__":
    main()
