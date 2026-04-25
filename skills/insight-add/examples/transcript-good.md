# Example: a clean /insight-add interaction

User: "we just spent 40 min on this, save it as a team insight"

Claude (after diagnosing a CI flake caused by stale Docker layer cache):

> Drafting the card. Please review:
>
> ```json
> {
>   "title": "CI flake — Docker layer cache survives across release tags, masks Dockerfile changes",
>   "trap": "Our CI reuses Docker layer cache keyed on Dockerfile path, not content. After a Dockerfile edit, runs against an old release tag will silently use the stale cached layer — tests pass but the produced image is wrong.",
>   "fix": "Add Dockerfile content hash to the cache key. In `.github/workflows/ci.yml`, set `cache-from: type=registry,ref=...:${{ hashFiles('Dockerfile') }}`. Also: drop the layer cache when the Dockerfile FROM line changes.",
>   "evidence": ".github/workflows/ci.yml:74; flake first observed in run #4127 (2026-04-19); root cause confirmed in PR #2103.",
>   "tags": ["ci", "docker", "cache"],
>   "scope": "project",
>   "author": "claude-instance@v4teambrain"
> }
> ```
>
> Confirm to POST?

User: "yes"

Claude POSTs and reports:

> Stored as `ins_e72df4abc910`. Future Claude instances editing CI or
> Dockerfile in this repo will see this card injected into their prompt.
