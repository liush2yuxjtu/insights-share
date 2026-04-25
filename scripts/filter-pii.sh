#!/usr/bin/env bash
# filter-pii.sh — Layer 1 (hard-coded regex) PII redactor.
#
# Per design doc P5 Layer 1: append-only regex filter for API keys, common
# secret patterns, $HOME paths, /private paths, JWT-shape tokens, AWS/GCP key
# shapes. Runs *before* any haiku call; never writes to network.
#
# Usage:
#   cat raw-turn.txt | filter-pii.sh                 # → redacted text
#   cat raw-turn.txt | filter-pii.sh --json-spans    # → JSON [{start,end,reason}]
#   filter-pii.sh --self-test                        # → run built-in adversarial tests
#
# Deterministic. Idempotent. Cost = $0.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PYTHON_HELPER="${PLUGIN_ROOT}/scripts/_filter_pii.py"

case "${1:-}" in
  --json-spans)
    exec python3 "$PYTHON_HELPER" spans
    ;;
  --self-test)
    # All tokens below are deliberate low-entropy EXAMPLE placeholders that
    # match Layer-1 regex patterns but DO NOT trip GitHub secret-scanning.
    self_test_input='my AWS key is AKIAEXAMPLEXXXXXXXXXX and the secret is XXXXXXXXEXAMPLEXXXXXXXXEXAMPLEXXXXXXXXXXXX
JWT: eyJEXAMPLEAAAAAA.eyJEXAMPLEBBBBB.SIGEXAMPLECCCCC
GitHub PAT: ghp_EXAMPLEXXXXXXXXXXXXXXXXX
OpenAI key: sk-proj-EXAMPLEXXXXXXXXXXXXXXXXXX
Slack token: xoxb-EXAMPLE-XXXXXXXXXXXXXXXXX
ssh -i /Users/m1/.ssh/id_rsa user@host
home path: /home/alice/.aws/credentials
mac home: /Users/m1/Documents/secret.txt
GCP key: AIzaEXAMPLEXXXXXXXXXXXXXXXXXXXXXXXXXXXX
private dir: /private/var/folders/abc
generic API: api_key="examplePlaceholderNotRealAA"
nothing sensitive here just chatting about Vue components'
    redacted=$(printf '%s' "$self_test_input" | python3 "$PYTHON_HELPER" redact)
    fail=0
    for tok in AKIAEXAMPLEXXXXXXXXXX eyJEXAMPLEAAAAAA ghp_EXAMPLEXXXXXXXXXXXXXXXXX sk-proj-EXAMPLEXXXXXXXXXXXXXXXXXX xoxb-EXAMPLE /Users/m1/.ssh /home/alice /Users/m1/Documents AIzaEXAMPLEXXXXXXXXXXXXXXXXXXXXXXXXXXXX /private/var; do
      if printf '%s' "$redacted" | grep -qF "$tok"; then
        echo "FAIL: token leaked: $tok"
        fail=1
      fi
    done
    if printf '%s' "$redacted" | grep -q "Vue components"; then
      echo "OK: benign content preserved"
    else
      echo "FAIL: benign content lost"
      fail=1
    fi
    if [[ $fail -eq 0 ]]; then
      echo "Layer-1 self-test PASS"
      exit 0
    else
      echo "--- redacted output ---"
      printf '%s\n' "$redacted"
      exit 1
    fi
    ;;
  --help|-h)
    sed -n '2,16p' "$0"
    exit 0
    ;;
esac

exec python3 "$PYTHON_HELPER" redact
