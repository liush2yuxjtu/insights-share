# Changelog

All notable changes to insights-share are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project follows semver.

## [Unreleased]

### Planned

- v0.2: production server reference implementation (Postgres + REST + bearer auth).
- v0.2: nightly automation (dedup, stale flag, digest emission).
- v0.2: tag-based filtering and severity scoring.
- v0.3: marketplace publication.

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

[Unreleased]: https://github.com/V4teamBrain/insights-share/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/V4teamBrain/insights-share/releases/tag/v0.1.0
