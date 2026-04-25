# insight-add — quality criteria

A useful card is **specific, evidenced, and actionable**. Every card you write
will be force-injected into a future Claude instance's prompt; weak cards
become noise that teammates learn to ignore. Apply the rubric below before
POSTing any card.

## The rubric

A card SHIPS if and only if:

1. **The trap is concrete.** It names a specific surface that looks correct
   but is actually wrong. "Check error handling" does not pass. "Wrapping a
   `rescue Exception` around the migration step swallows DDL errors and
   leaves the schema half-applied" does.

2. **The fix is operational.** A reader can execute the fix without further
   judgement. "Be careful with X" does not pass. "Pass `--require-clean=true`
   to migrate; refuse to start when `pg_is_in_recovery()` returns t" does.

3. **The evidence exists outside the card.** Cite the file:line, error text,
   PR, or commit that proves the trap is real. No anecdote-only cards.

4. **The trap is non-obvious.** A future Claude reading the affected code
   would not notice this on its own. If the linter or type-checker would
   catch it, do not write a card.

5. **The scope is honest.** Use `project` for repo-specific lessons.
   Reserve `global` for genuinely cross-repo gotchas (build tooling,
   language quirks, common library footguns).

## Tags

Pick at least one **domain** tag and one **surface** tag.

- Domain: `auth`, `migration`, `ingest`, `billing`, `ui`, `infra`, ...
- Surface: `hook`, `cli`, `script`, `library`, `config`, `cron`, ...

Bad: `["important", "tricky"]`.
Good: `["migration", "cli", "concurrency"]`.

## Title

≤ 80 chars, imperative, leads with the verb. The title is the first thing
the next Claude will read; it must be self-contained.

- Bad: `bug in deploy script`
- Good: `Refuse to deploy when PG is_in_recovery — bg replica caused 12m outage`

## Length

Trap + fix together should be readable in 15 seconds. If they exceed ~60
words combined, you are recording two cards. Split them.

## When NOT to write a card

- The fix is "be careful" / "pay attention" / "remember to" — these decay
  to noise.
- The trap is taste ("I prefer dataclasses to dicts here").
- The trap is already stated in the file's comments or in CLAUDE.md.
- The trap is recoverable in <30 seconds by re-reading the failing test.

## Anti-templates (never ship)

```
trap: be careful with concurrency
fix:  use locks
```

```
trap: edge case in parsing
fix:  add more tests
```

```
trap: this code is fragile
fix:  refactor it
```
