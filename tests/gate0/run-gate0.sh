#!/usr/bin/env bash
# run-gate0.sh — Gate 0 PII benchmark per design doc.
#
# Hard gate before any raw jsonl flows live. Spec:
#   ≥500 real jsonl turns from founder's own ~/.claude/projects/ history,
#   manually labeled for PII.
#   ≥3 different project types (web/infra/data) AND ≥50 deliberate-injection
#   adversarial patterns founder seeds.
#   PASS = 0 PII leaks AND ≤2% false positive rate.
#
# This runner is the framework. It:
#   1. Reads tests/gate0/corpus/*.jsonl (one record per line: {text, labels: [{start,end,reason}]}).
#   2. Pipes each text through scripts/filter-pii.sh --json-spans.
#   3. Compares span coverage against labels:
#        - leak  = labeled span NOT covered by any predicted span.
#        - false-positive = predicted span overlapping zero labeled chars.
#   4. Aggregates and prints a verdict line + JSON summary.
#
# Usage:
#   tests/gate0/run-gate0.sh                       # default corpus path
#   tests/gate0/run-gate0.sh --corpus path/glob    # alternate corpus
#   tests/gate0/run-gate0.sh --strict              # require ≥500 turns + ≥3 buckets

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
CORPUS_GLOB="${PLUGIN_ROOT}/tests/gate0/corpus/*.jsonl"
strict=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --corpus)  CORPUS_GLOB="$2"; shift 2 ;;
    --strict)  strict=1; shift ;;
    *)         echo "ERROR: unknown $1" >&2; exit 2 ;;
  esac
done

PLUGIN_ROOT="$PLUGIN_ROOT" \
CORPUS_GLOB="$CORPUS_GLOB" \
STRICT="$strict" \
python3 - <<'PYEOF'
import glob
import json
import os
import subprocess
import sys

plugin_root = os.environ["PLUGIN_ROOT"]
corpus_glob = os.environ["CORPUS_GLOB"]
strict = os.environ["STRICT"] == "1"
filter_sh = os.path.join(plugin_root, "scripts", "filter-pii.sh")

files = sorted(glob.glob(corpus_glob))
if not files:
    print(json.dumps({"error":"no_corpus","glob":corpus_glob}))
    sys.exit(2)

records = []
buckets = set()
for f in files:
    bucket = os.path.basename(f).split("__")[0]
    buckets.add(bucket)
    with open(f) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            obj["__bucket"] = bucket
            records.append(obj)

n = len(records)
if strict and (n < 500 or len(buckets) < 3):
    print(json.dumps({
        "verdict":"FAIL",
        "reason":"strict mode requires ≥500 turns + ≥3 buckets",
        "turns": n,
        "buckets": sorted(buckets),
    }))
    sys.exit(1)

leaks = 0
false_positives = 0
total_pred_spans = 0
total_label_spans = 0
adversarial_total = 0
adversarial_caught = 0

for r in records:
    text = r.get("text","")
    labels = r.get("labels", [])
    is_adversarial = bool(r.get("adversarial"))
    if is_adversarial:
        adversarial_total += 1
    res = subprocess.run(
        ["bash", filter_sh, "--json-spans"],
        input=text, capture_output=True, text=True, timeout=10,
    )
    try:
        pred = json.loads(res.stdout or "[]")
    except Exception:
        pred = []
    total_pred_spans += len(pred)
    total_label_spans += len(labels)

    pred_set = set()
    for p in pred:
        pred_set.update(range(p["start"], p["end"]))

    label_set = set()
    for l in labels:
        label_set.update(range(l["start"], l["end"]))

    if labels:
        # leak = any labeled char missed by predictions
        if label_set - pred_set:
            leaks += 1
        else:
            if is_adversarial:
                adversarial_caught += 1

    # false positive = a prediction span with ZERO overlap with any label.
    # (Predictions that EXTEND past a label are conservative, not false-positive.)
    has_zero_overlap_pred = False
    for p in pred:
        p_chars = set(range(p["start"], p["end"]))
        if p_chars and not (p_chars & label_set):
            has_zero_overlap_pred = True
            break
    if has_zero_overlap_pred:
        false_positives += 1

fp_rate = (false_positives / max(1, n))
adv_recall = (adversarial_caught / max(1, adversarial_total)) if adversarial_total else 1.0

verdict = "PASS" if (leaks == 0 and fp_rate <= 0.02) else "FAIL"

summary = {
    "verdict": verdict,
    "turns": n,
    "buckets": sorted(buckets),
    "labeled_spans": total_label_spans,
    "predicted_spans": total_pred_spans,
    "leaks": leaks,
    "false_positives": false_positives,
    "false_positive_rate": round(fp_rate, 4),
    "adversarial_total": adversarial_total,
    "adversarial_caught": adversarial_caught,
    "adversarial_recall": round(adv_recall, 4),
    "thresholds": {"leaks": 0, "fp_rate": 0.02},
}
print(json.dumps(summary, indent=2))
sys.exit(0 if verdict == "PASS" else 1)
PYEOF
