# Example: bootstrapping a fresh repo with /insight-install

## Scenario

Claude is invoked in `~/projects/new-service/` for the first time. The
`SessionStart` hook ran, but the repo is brand new and the user wants to
verify the install marker landed.

User: "wire this repo so teammates inherit insights"

Claude runs the install verb and then re-reads CLAUDE.md to confirm:

```
$ ls CLAUDE.md
CLAUDE.md
$ echo "{\"cwd\":\"$PWD\"}" | bash $CLAUDE_PLUGIN_ROOT/scripts/append-claude-md.sh
$ tail -20 CLAUDE.md
## Team Insights (insights-share plugin) — required for collaborators
...
<!-- insights-share@v0.1 -->
$ grep -c 'insights-share@v0.1' CLAUDE.md
1
```

Claude reports:

> Installed. Marker on line 47 of CLAUDE.md. Future Claude instances
> entering `new-service/` will be guided to install this plugin via the
> `SessionStart` hook.

## Scenario — already installed

User: "install insights here"

Claude probes:

```
$ grep -c 'insights-share@v0.1' CLAUDE.md
1
```

Claude says:

> Marker already present at line 47. Nothing to do — the install is
> idempotent and we are already wired.
