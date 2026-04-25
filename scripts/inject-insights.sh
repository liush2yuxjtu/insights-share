#!/usr/bin/env bash
# inject-insights.sh — UserPromptSubmit hook (B-architecture).
#
# Per design doc:
#   - Hot-path = local cache only, no git fetch, ≤500ms p95.
#   - Background: cold-start (mirror clone discovery) + buffer-recover.
#
# This wrapper is intentionally thin — all work happens in
# scripts/_inject_hot_path.py to keep python startup amortized to a single
# invocation per call.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
exec python3 "${PLUGIN_ROOT}/scripts/_inject_hot_path.py"
