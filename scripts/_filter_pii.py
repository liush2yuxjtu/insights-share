#!/usr/bin/env python3
"""Layer 1 PII redactor — pure-Python, deterministic, $0 cost.

Per design doc P5: hard-coded regex append-only filter for API keys, common
secret patterns, $HOME paths, /private paths, JWT shapes, AWS/GCP key shapes.
Runs *before* any haiku call.
"""
import json
import re
import sys

PATTERNS = [
    (re.compile(r"\b(?:AKIA|ASIA|AIDA)[0-9A-Z]{16,}\b"),                                                "aws_access_key_id"),
    (re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b"),                                                         "gcp_api_key"),
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"),                                                   "slack_token"),
    (re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{20,}\b"),                           "github_pat"),
    (re.compile(r"\bsk-(?:proj-|test-|live-|ant-api\d+-)?[A-Za-z0-9_\-]{16,}\b"),                       "openai_key"),
    (re.compile(r"\bsk-ant-[A-Za-z0-9_\-]{16,}\b"),                                                     "anthropic_key"),
    (re.compile(r"\b(?:sk|pk|rk)_(?:test|live)_[A-Za-z0-9]{16,}\b"),                                    "stripe_key"),
    (re.compile(r"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\b"),                  "jwt"),
    # Named secret: keyword (with optional space/_/- separators) + optional :/=/space + value.
    # Handles: "api_key=…", "API key = …", "password verysecret", "AUTH_TOKEN=…"
    (re.compile(
        r"""(?ix)
        \b(?:
            api[\s_\-]?key       | access[\s_\-]?token   | auth[\s_\-]?token  |
            secret(?:[\s_\-]?key)?| client[\s_\-]?secret  |
            backend[\s_\-]?password| dd[\s_\-]?api[\s_\-]?key |
            oauth[\s_\-]?client[\s_\-]?secret |
            password | passwd | bearer | token
        )
        \s*[:=]?\s*
        ['"]?
        ([A-Za-z0-9_\-./+=$@!?#%&*]{8,})
        ['"]?
        """),                                                                                            "named_secret"),
    (re.compile(r"(?i)\bAuthorization:\s*Bearer\s+([A-Za-z0-9_\-./+=]{16,})"),                          "bearer_token"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),                                                 "ssh_priv_key"),
    (re.compile(r"/Users/[A-Za-z0-9_\-]+(?:/[^\s\"']*)?"),                                              "macos_home_path"),
    (re.compile(r"/home/[A-Za-z0-9_\-]+(?:/[^\s\"']*)?"),                                               "linux_home_path"),
    (re.compile(r"/private/[^\s\"']+"),                                                                 "private_path"),
    (re.compile(r"\b(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b"),                                        "ip_address"),
    (re.compile(r"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b"),                               "email"),
    (re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b"),"uuid"),
    # International phone: +<cc>-<area>-<exch>-<sub>
    (re.compile(r"\+\d{1,3}-\d{1,4}-\d{2,5}-\d{2,6}"),                                                  "phone_e164"),
    # Hex strings 32+ chars (md5/sha1/sha256-shaped)
    (re.compile(r"\b[a-f0-9]{32,}\b"),                                                                  "hex_hash"),
    # AWS secret-shape last (most ambiguous): 40+ base64-ish chars
    (re.compile(r"(?<![A-Za-z0-9/+=])[A-Za-z0-9/+=]{40,}(?![A-Za-z0-9/+=])"),                           "aws_secret_shape"),
]


def redact(text: str):
    spans = []
    for rx, label in PATTERNS:
        for m in rx.finditer(text):
            spans.append({"start": m.start(), "end": m.end(), "reason": label})
    spans.sort(key=lambda s: (s["start"], -(s["end"] - s["start"])))
    merged = []
    for s in spans:
        if merged and s["start"] < merged[-1]["end"]:
            if s["end"] > merged[-1]["end"]:
                merged[-1]["end"] = s["end"]
                merged[-1]["reason"] = merged[-1]["reason"] + "+" + s["reason"]
        else:
            merged.append(dict(s))
    parts = []
    cursor = 0
    for s in merged:
        parts.append(text[cursor:s["start"]])
        parts.append(f"[REDACTED:{s['reason']}]")
        cursor = s["end"]
    parts.append(text[cursor:])
    return "".join(parts), merged


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "redact"
    text = sys.stdin.read()
    redacted, spans = redact(text)
    if mode == "spans":
        json.dump(spans, sys.stdout)
        sys.stdout.write("\n")
    else:
        sys.stdout.write(redacted)


if __name__ == "__main__":
    main()
