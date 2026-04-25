# Example: cards that should NOT be saved

## 1. Fix is "be careful"

User: "log this — async deletes are tricky"

Claude:

> This is a good gut feeling but does not meet the rubric in
> `references/quality.md`. The fix would be "be careful with async deletes",
> which decays to noise. If you can name a specific deletion that produced
> ghost rows or a specific check that prevents it, I will write the card.
> Otherwise let's skip.

## 2. Already covered in CLAUDE.md

User: "remember that we run tests with --no-cov in CI"

Claude:

> That convention is already documented in `CLAUDE.md:42`. A team-insight
> card would duplicate it and rot when CLAUDE.md changes. Skipping.

## 3. Linter would catch it

User: "save: don't shadow built-in `list` with a variable name"

Claude:

> Pyright and ruff both flag this (`A001`). A future Claude editing this
> code will see the diagnostic before reading our cards. Not worth a card.
