# B-scope implementation trace

This document maps every B-locked decision and feature in the canonical
design (`~/.gstack/projects/liush2yuxjtu-v4-team-brain/m1-main-design-20260425-132223.md`)
to the file that implements it. Used as the source-of-truth audit when
running `claudefast` against "is each wanted feature well implemented under
the boil-the-lake philosophy".

The plugin is intentionally `boil-the-lake` per the founder's bet (Approach
B was chosen against the `Approach A wedge` recommendation). Every feature
below is therefore *meant* to ship in v1, not deferred.

## B-locked decisions → implementation files

| B-locked decision (design ref)                        | Implementation file                                        | Self-test command                                                            |
|--------------------------------------------------------|-------------------------------------------------------------|------------------------------------------------------------------------------|
| Storage backend = GitHub mirror repo, plain JSONL      | `scripts/sync-mirror.sh`                                    | `bash scripts/sync-mirror.sh status <slug>`                                  |
| Auth = per-repo fine-grained PAT, chmod 600            | `scripts/pat-auth.sh`                                       | `tests/run.sh §B4`                                                           |
| Cold-start lazy mirror discovery, 5s budget            | `scripts/cold-start.sh`                                     | `bash scripts/cold-start.sh --status <slug>`                                 |
| Stop hook = silent capture (NOT nudge)                 | `scripts/capture-async.sh` + `scripts/finalize-buffer.sh`   | `tests/run.sh §B7`                                                           |
| Async finalize, 30-min idle threshold                  | `scripts/finalize-buffer.sh`                                | `tests/run.sh §B7` (watchdog spawn)                                          |
| Routing latency budget ≤500ms p95, hot path local-only | `scripts/inject-insights.sh` → `scripts/_inject_hot_path.py`| `tests/run.sh §B6` (20-iter bench, p95 reported)                             |
| Topic tags inferred at capture by haiku Layer 2        | `scripts/filter-haiku.sh`                                   | `bash scripts/filter-haiku.sh --self-test`                                   |
| Filter test corpus (Gate 0)                            | `tests/gate0/run-gate0.sh` + `tests/gate0/seed-corpus.py`   | `bash tests/gate0/run-gate0.sh --strict`                                     |
| Rating capture (`/insight-rate`)                       | `skills/insight-rate/SKILL.md` + `scripts/rate-lesson.sh`   | `tests/run.sh §B8`                                                           |
| Scaffolding kept (71 tests + 28 UAT + …)               | `tests/run.sh` (extended to 92), `tests/gate0/`, `examples/`| `bash tests/run.sh`                                                          |

## P-premise → implementation

| Premise                                              | Implementation                                                                                          |
|------------------------------------------------------|----------------------------------------------------------------------------------------------------------|
| **P3** no `solution` tag — only good/bad + raw       | `_inject_hot_path.py:render()` cites `lesson_id` + topic tags only; no solution field anywhere in schema. |
| **P4** carrier = canonical git remote (HTTPS = SSH)  | `scripts/canonical-remote.sh` (verified by `tests/run.sh §B1`).                                          |
| **P5 Layer 1** hard-coded regex PII filter           | `scripts/_filter_pii.py` (15 pattern families); driver in `scripts/filter-pii.sh`.                       |
| **P5 Layer 2** haiku redact + topic tags, 2s timeout | `scripts/filter-haiku.sh`. Drops on timeout / confidence < 0.8.                                          |
| **P5 hard gate (Gate 0)**                            | `tests/gate0/run-gate0.sh` — strict mode requires ≥500 turns, ≥3 buckets, ≥50 adversarial seeds.         |
| **P6** scaffolding kept                              | All previously-existing files retained; new B-pipeline appended without rewriting `examples/server-stub.py`. |

## Open questions (deferred per design doc)

| OQ # | Topic                          | Status                                                                                       |
|------|--------------------------------|-----------------------------------------------------------------------------------------------|
| 1    | Lesson decay/staleness policy  | Schema includes `model_version` + `captured_at`; downweight logic deferred to /plan-eng-review. |
| 2    | Per-folder ACL                 | Out-of-scope for v1 (P4 v1 = trust ≈ remote-access).                                          |
| 3    | Topic-tag drift                | Tracked at Gate 1 via `ratings.jsonl`; embedding fallback covers misses (`scripts/embed-fallback.py`). |
| 4    | Multi-org engineer             | Per-remote install isolates correctly (verified `tests/run.sh §B1`).                          |
| 5    | Auto-create mirror             | Current fallback: `sync-mirror.sh ensure` warns + prints `gh repo create` hint.               |
| 6    | PAT rotation                   | Manual via `pat-auth.sh forget`; v2 → GitHub App.                                             |
| 7    | Buffer crash recovery          | `scripts/buffer-recover.sh` (verified `tests/run.sh §B10`).                                   |
| 8    | Background clone timeout       | `INSIGHTS_COLDSTART_BUDGET_S=5` in `cold-start.sh`.                                           |

## Gate 0 evidence

Latest run (`bash tests/gate0/run-gate0.sh --strict`):

- **Verdict:** PASS
- **Turns:** 654 (≥500 required)
- **Buckets:** adversarial, data, infra, web (≥3 required)
- **Adversarial seeds:** 54 (≥50 required), recall 98.15%
- **Leaks:** 0 (threshold: 0)
- **False-positive rate:** 0.0% (threshold: ≤2%)

## Latency evidence

Latest hot-path bench (`tests/run.sh §B6`, 20 iterations):

- **avg ≈ 240ms**
- **p95 ≈ 250ms**
- **budget = 500ms** ✅
