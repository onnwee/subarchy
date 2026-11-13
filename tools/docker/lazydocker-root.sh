#!/usr/bin/env bash
# The root side of `subcult docker tui` (ADR 0055), installed as
# /usr/lib/subcult/lazydocker-root and named by the polkit action
# tv.subcult.docker.tui. pkexec starts it with a clean environment; the one
# argument is the caller's terminal type, so lazydocker can draw. Anything
# else is ignored.
set -euo pipefail

term=${1:-}
[[ $term =~ ^[A-Za-z0-9._+-]{1,64}$ ]] || term=xterm-256color
exec env TERM="$term" /usr/bin/lazydocker
