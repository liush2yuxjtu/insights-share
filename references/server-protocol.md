# insights-share — server protocol (v0.1)

> Status: **contract only**. The production backend is deferred. The client and hooks in this plugin speak this protocol; any conforming server (self-hosted or hosted) is a drop-in target.

## Transport

- HTTP/1.1 over TCP. JSON request/response bodies. UTF-8.
- Optional bearer token in `Authorization: Bearer <token>` (`INSIGHTS_AUTH_TOKEN`).
- Base URL is `INSIGHTS_SERVER_URL`, default `http://localhost:7777`.

## Endpoints

### `GET /healthz`

Liveness probe. Returns `200 OK` with body `ok`. Anything else is treated as offline.

### `GET /insights`

Returns the full insight list as a JSON array (small teams; pagination deferred).

```json
[
  { "id": "ins_01H...", "title": "...", "trap": "...", "fix": "...",
    "evidence": "...", "tags": ["..."], "scope": "project", "author": "...",
    "created_at": "2026-04-25T07:00:00Z", "updated_at": "2026-04-25T07:00:00Z" },
  ...
]
```

### `GET /insights/search?q=<keyword>`

Returns up to 25 cards whose `title`, `trap`, `fix`, or `tags` contain the keyword (case-insensitive). Empty result is `[]`.

### `POST /insights`

Body: a single insight card (without `id`, `created_at`, `updated_at`). Server assigns those.

```json
{
  "title": "...",
  "trap": "...",
  "fix": "...",
  "evidence": "...",
  "tags": ["..."],
  "scope": "project",
  "author": "..."
}
```

Response: the stored card with assigned `id` and timestamps. Idempotency key (optional): `Idempotency-Key` header — if a card with that key was created in the last hour, the server returns the existing record.

### `GET /stats`

```json
{
  "total": 42,
  "new": 3,
  "session_relevant": 0,
  "online": true,
  "last_sync_seconds_ago": 12
}
```

`new` = cards the calling client has not yet acknowledged (opaque cursor maintained server-side per token).
`session_relevant` is reserved — clients may pass `?cwd=<path>` to receive a count filtered by `tags` matching path components.

## Error model

Non-2xx responses return:

```json
{ "error": "code", "message": "human-readable" }
```

Clients treat `5xx` and connection refused as offline; they fall back to local cache.

## Versioning

The server SHOULD advertise its version in `X-Insights-Server-Version` header. Clients ignore unknown fields. New required fields require a bump from `v0.1` → `v0.2`.
