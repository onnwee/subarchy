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
# subcult:hidden=true           # optional: left out of `subcult commands`
```

Only comment lines before the first line of code are read. The dispatcher is
`cmd/subcult` and `internal/dispatch`.
