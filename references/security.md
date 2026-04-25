# insights-share — security notes (v0.1)

This is the contract Claude instances on a team will rely on. The threat
model and defenses below apply to v0.1 (client + stub) and feed forward into
the v0.2 production server design.

## Threat model

- **Adversary**: another process on the same host, a misbehaving teammate's
  Claude instance, or an unauthenticated network actor on the same LAN.
- **Goal**: inject false insights into the team's prompt stream
  (effectively prompt-injection-as-a-service), exfiltrate insights from
  private repos, or DoS the server.
- **Out of scope (v0.1)**: end-to-end encryption, multi-tenant isolation
  between teams, fine-grained ACLs.

## Mitigations shipped in v0.1

| Concern | Mitigation |
|---|---|
| Stub server reachable from LAN | Binds `127.0.0.1` by default. Public bind requires `--allow-public` and is documented as stub-only. |
| Auth absent | Optional bearer via `INSIGHTS_AUTH_TOKEN`. Never logged; passed only via `Authorization` header. |
| Token leaks | `.gitignore` excludes `.claude/*.local.md` and `.env*`. Token is read from env, never from a tracked file. |
| Curl returns HTML 200 from a hijacked port | Client uses `--fail --connect-timeout 2` so any non-2xx surfaces and falls back to local cache. |
| Prompt-injection via stored cards | Cards are wrapped in `<insights-share>` system-reminder block before injection — Claude treats them as untrusted data, not user instructions. |
| Cache corruption | All client paths tolerate malformed JSON: `search` returns `[]`, `stats` returns sane defaults. |
| Race during concurrent hook firings | Cache writes are atomic at the curl/stub-server boundary; hooks read cache only and never mutate it. |
| Append-CLAUDE.md tampering | Append-only, idempotent via marker line. The hook never deletes or rewrites prior content. |
| Malicious JSON in POST | Stub validates `title` presence and JSON parseability; rejects with 400. |
| DoS via giant payloads | v0.1 stub has no rate-limit; mitigated by binding loopback. v0.2 will add server-side limits. |

## Operational guidance

- Do not commit `~/.claude/insights/cache.json` or `outbox/` to any repo.
- Rotate `INSIGHTS_AUTH_TOKEN` after onboarding/offboarding teammates.
- Review insights before promoting `scope: project` to `scope: global`. A
  global card touches every Claude instance on every repo.
- When a teammate leaves, audit `author` field to drop or re-attribute
  cards they authored.

## Reporting

Security issues: open a GitHub security advisory on the repo. Do not file
public issues that include a working exploit.
