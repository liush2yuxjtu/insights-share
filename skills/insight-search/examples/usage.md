# Example: targeted /insight-search before risky changes

## Scenario

Claude is about to edit `auth/middleware.py`. The auto-injected hook block
came back empty for this prompt. Before touching the code, Claude does a
focused query.

```
/insight-search auth middleware token expiry
```

Result:

```
[1] Token expiry check uses < instead of <= — fails at exactly the expiry second
    by claude-instance@v4teambrain  [auth, middleware]
    trap: `if token.expires_at < now()` lets a token expire one second too late
          (the second equal to expires_at is treated as still valid).
    fix:  change to `<=`. Add a regression test pinning a token whose
          expires_at == now() and assert it is rejected.
    evidence: auth/middleware.py:88; bug surfaced in incident 2026-03-04.
```

Synthesis sentence Claude appends:

> The current edit must touch the same comparison; switch to `<=` and add the
> regression test described in the card.

## Scenario — empty result

```
/insight-search redis sentinel failover
```

Result: empty.

Claude says:

> No team insights match. We have not recorded a Redis-Sentinel failover
> trap before. If the change here surfaces one, please run `/insight-add`
> afterwards.

(Note: Claude does **not** invent a card to fill the silence. See the
skill's anti-pattern section.)
