# Changelog

All notable changes to insights-share are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project follows semver.

## [Unreleased]

### Planned

- v0.4: production server reference implementation (Postgres + REST + bearer auth) for non-GitHub deployments.
- v0.4: nightly automation (dedup, stale flag, digest emission).
- v0.4: per-folder ACL (Open Question #2).
- v0.4: GitHub App auth, replacing per-repo PAT.

## [0.3.0] — 2026-04-26

v0.3 turns insights-share from a passive injector into a full card lifecycle
toolkit. Claude instances can now add, promote, inspect, edit, delete, trace,
resolve, and get notified about team insights from slash commands while keeping
silent hook delivery intact.

### Added

- Full insight lifecycle command surface:
  `/insight-add`, `/insight-promote`, `/insight-log`, `/insight-edit`,
  `/insight-delete`, `/insight-list`, `/insight-conflict`,
  `/insight-resolve`, `/insight-notifications`, and `/insight-view`.
- Safer `/insight-add` backing script with Layer-1 PII redaction,
  required-field validation, duplicate-card detection, and per-minute rate
  limiting before writes reach the shared store.
- Cross-session promotion, lineage, conflict detection, conflict resolution,
  notification, and card-view scripts backed by the existing local + mirror
  insight storage model.
- Zero-start Claude onboarding UAT covering marketplace discovery, install,
  enablement, fresh-session command visibility, and README guidance.

### Changed

- Prompt injection now merges remote, cached, and local cards with explicit
  `related_to`, `status`, `created_at`, `updated_at`, and `deleted_at`
  handling so delivered context stays current without leaking deleted cards.
- README installation, update, command list, file layout, and first-use
  guidance now match the 16-command plugin surface.
- `append-claude-md.sh`, `insights-client.sh`, and mirror sync behavior now
  support quieter hook delivery and cleaner status output.

### Fixed

- Mirror sync no longer leaks noisy pull/push output into user-visible hook
  paths.
- Deleted cards are excluded from search, list, and prompt injection results.
- Concurrent edits merge non-conflicting field updates while rejecting
  unauthorized authorship changes.

### Tests

- Test suite expanded to 114 assertions, covering insight lifecycle commands,
  hook-delivered prompt injection, zero-start install checks, PII redaction,
  duplicate detection, rate limiting, conflict workflows, delete/search misses,
  offline flush/retry behavior, and mirror-sync cleanliness.

## [0.2.0] — 2026-04-25

Approach-B architecture rollout per the canonical design at
`~/.gstack/projects/liush2yuxjtu-v4-team-brain/m1-main-design-20260425-132223.md`.
Every B-locked decision now has a real, self-tested implementation file —
see `docs/B-scope-impl.md` for the full design ↔ file map.

### Added

- **Two-layer PII filter pipeline** (P5).
  - Layer 1 regex (`scripts/_filter_pii.py`, 15 pattern families): AWS / GCP /
    JWT / GitHub PAT / Slack / SSH / `$HOME` paths / `/private` paths /
    email / phone / hex-hash / IP / Stripe / Anthropic / OpenAI keys.
  - Layer 2 haiku redact + topic-tag inference (`scripts/filter-haiku.sh`,
    2 s timeout, drops on `confidence < 0.8`).
- **Gate-0 corpus benchmark** (`tests/gate0/`). Strict mode requires ≥500
  turns / ≥3 buckets / ≥50 adversarial seeds. Current corpus: 654 turns /
  4 buckets / 54 adversarial / **0 leaks / 0 % FP / 98 % adversarial recall**.
- **Silent capture pipeline**.
  - `scripts/capture-async.sh` replaces the prior heuristic nudge — Stop hook
    appends to `~/.gstack/insights/<slug>/.buffer/<session>.jsonl` and spawns
    a per-session watchdog. Hot-path return < 50 ms.
  - `scripts/finalize-buffer.sh` async finalize: idle wait → Layer 1 → Layer 2
    → drop or → `lessons.jsonl` → mirror push.
  - `scripts/buffer-recover.sh` orphan recovery on plugin startup (OQ7).
  - `scripts/flush-buffer.sh` synchronous flush backing `/insight-flush`.
- **GitHub mirror storage layer**.
  - `scripts/canonical-remote.sh` normalises HTTPS == SSH origins to one
    `host__owner__repo` slug (P4 privacy boundary).
  - `scripts/sync-mirror.sh` ensure / pull / push / status against
    `<owner>/<repo>-insights`. Plain JSONL commits, no LFS.
  - `scripts/pat-auth.sh` per-repo fine-grained PATs persisted at
    `~/.gstack/insights-auth/<slug>.token` (chmod 600), with set / get / has /
    validate / forget / list.
  - `scripts/cold-start.sh` lazy mirror discovery (5 s budget, OQ8) plus a
    30-min background sync watchdog.
- **Hot-path retrieval** (UserPromptSubmit) at p95 ≤ 500 ms.
  - `scripts/inject-insights.sh` → `scripts/_inject_hot_path.py` is a single
    python invocation that resolves the canonical slug, reads
    `.mirror/lessons.jsonl` + local `lessons.jsonl`, scores topic-tag and
    bag-of-words overlap, and renders a `<insights-share>` block citing only
    `lesson_id` + topic_tags (P3 — no `solution` tag).
  - `scripts/embed-fallback.py` sentence-transformers cosine fallback with a
    TF-IDF degradation path when the heavy dependency is missing.
  - 20-iteration bench: avg ≈ 240 ms, p95 ≈ 250 ms (50 % headroom on the
    500 ms budget).
- **Two new skills** (now 7 total).
  - `/insight-rate <lesson-id> <good|bad|irrelevant> [reason]` writes to
    `ratings.jsonl` and triggers a background mirror push. Used by Gate 1.
  - `/insight-flush` forces synchronous finalize + mirror push.
- **Test suite extended to 92 / 92** (was 71). New B-pipeline sections
  cover canonical-remote HTTPS == SSH parity, Gate-0 verdict, Layer 2 self-
  test, PAT auth lifecycle, retrieve-local self-test, hot-path latency
  bench, capture-async buffer + watchdog, rate-lesson round-trip, sync-mirror
  status / ensure offline, buffer-recover idempotency, flush-buffer JSON
  shape, embed-fallback graceful degradation, hooks.json wiring, and SKILL.md
  frontmatter validity.
- `docs/B-scope-impl.md` and updated README "Architecture" section
  documenting the design ↔ implementation map.

### Changed

- `hooks/hooks.json` rewired: `UserPromptSubmit → inject-insights.sh`,
  `Stop → capture-async.sh`. SessionStart hook now also kicks off cold-start
  + buffer-recover off the hot path.

### Kept (per design P6)

- The legacy 71-assertion HTTP-server suite, statusline, force-install
  marker, marketplace setup, canned answers, and `examples/server-stub.py`
  remain unchanged.

### Security

- Per-repo PATs are written with `umask 077` and `chmod 600`. `pat-auth.sh
  validate` performs an authenticated `GET` against the mirror to confirm
  scope before any push.
- Layer 1 regex passes the Gate-0 strict gate (0 leaks) before any upload
  code runs.
- Hot path performs **no** network calls; mirror sync is strictly background.

## [0.1.0] — 2026-04-25

### Added

- Plugin manifest, marketplace wrapper, MIT license.
- 4 skills: `insight-add`, `insight-search`, `insight-install`, `insight-server`.
- 3 hooks: `SessionStart` (force-install via append-only CLAUDE.md),
  `UserPromptSubmit` (relevant-insight injection), `Stop` (lesson-capture nudge).
- Statusline frontend with `lite | full | ultra` modes; cwd-aware
  `session_relevant` count; offline indicator.
- HTTP client (`insights-client.sh`) with verbs:
  `list`, `get`, `search`, `create`, `update`, `delete`, `stats`, `ping`,
  `outbox-flush`. Offline writes queue to outbox.
- Self-host server stub (`examples/server-stub.py`) implementing the full
  v0.1 protocol contract (CRUD, search, stats, healthz).
- Protocol docs: `references/server-protocol.md`, `references/self-host.md`,
  `references/security.md`.
- Per-skill examples in `skills/<name>/examples/`.
- Quality reference at `skills/insight-add/references/quality.md`.
- Test harness at `tests/run.sh` (60+ assertions, online + offline + stress).
- `Makefile` shortcuts: `make test`, `make lint`, `make stub`, `make stop`.

### Security

- Stub server binds 127.0.0.1 by default; non-localhost requires
  `--allow-public`.
- All scripts use `set -euo pipefail`. shellcheck-clean.
- No hardcoded secrets; bearer token via `INSIGHTS_AUTH_TOKEN`.
- `_curl` uses `--fail --connect-timeout 2` to surface connection errors
  rather than silently treating HTML 404 as success.

[Unreleased]: https://github.com/liush2yuxjtu/insights-share/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/liush2yuxjtu/insights-share/releases/tag/v0.3.0
[0.2.0]: https://github.com/liush2yuxjtu/insights-share/releases/tag/v0.2.0
[0.1.0]: https://github.com/liush2yuxjtu/insights-share/releases/tag/v0.1.0
