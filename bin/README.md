# bin

Bash commands for the `subcult` dispatcher ([ADR 0046](../docs/decisions/0046-distribution-cli.md)).
Each command is an executable named `subcult-<group>-<action>`, installed to
`/usr/bin`. `subcult <group> <action> [args]` (or `sub …`) runs it with the
remaining arguments. Commands written in Go register the same way.

Every script starts with a metadata header, which `subcult commands --json`,
the launcher and the user manual read:

```bash
#!/usr/bin/env bash
# subcult:summary=Apply a theme
# subcult:args=<theme-id>
# subcult:examples=subcult theme set subcult-minimal | subcult theme list
# subcult:requires-sudo=true    # optional
# subcult:dangerous=true        # optional: the launcher asks before running it
# subcult:silent=true           # optional: no output to read; the launcher opens no terminal
# subcult:hidden=true           # optional: left out of `subcult commands`
```

Only comment lines before the first line of code are read. The dispatcher is
`cmd/subcult` and `internal/dispatch`.

## Compiled commands

A compiled command can serve several routes. The dispatcher runs it with
`--subcult-metadata` (2 s limit) and reads a JSON array of
`{"words": [...], "summary": ..., "args": ..., "examples": [...], ...}`,
keeping only routes under the binary's own name. `subcult-app` reports
`app list`, `app install` and so on; `subcult app install steam` then runs
`subcult-app install steam`. The Go commands live in `cmd/`.
