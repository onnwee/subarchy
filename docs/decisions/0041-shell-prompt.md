---
title: "ADR 0041: Interactive shell and prompt"
type: decision
status: accepted
adr: 41
created: 2026-11-06
updated: 2026-11-07
tags: [decision, adr, apps]
aliases: [ADR 0041, A2, zsh]
---

# ADR 0041: Interactive shell and prompt

Decision map item A2. Accepted 2026-11-06; revised 2026-11-07 to make zsh
the login shell, after the owner asked for zsh to work without the bash
handoff Omarchy users need.

## Decision

- **zsh is the login shell** for the user the installer creates
  (`useradd -s /usr/bin/zsh`). root keeps bash. There is no bash-to-zsh
  handoff.
- **starship** prompt and **atuin** history, as before.
- **The session never depends on shell startup files.** Environment for the
  desktop session comes from uwsm's environment files and systemd's
  `environment.d` ([[0031-session-manager|ADR 0031]]), so changing the login
  shell cannot break login.
- **Subarchy's shell integration ships for zsh and bash**, layered like other
  config ([[0048-config-ownership|ADR 0048]]):
  - `/usr/share/subcult/default/shell/aliases.sh` and `functions.sh` in
    POSIX syntax, sourced by both shells;
  - `/usr/share/subcult/default/shell/zshrc` and `bashrc` for per-shell
    setup: starship, zoxide, atuin, fzf key bindings, mise, completions;
  - the user's `~/.zshrc` is a short file that sources the default and then
    holds the user's own additions.
- **Subarchy's own scripts** start with `#!/usr/bin/env bash` and never
  depend on the user's shell or its aliases.
- The `subcult` CLI ships completions for zsh and bash.
- `subcult shell set zsh|bash` switches with `chsh` and keeps both
  integrations installed. fish is not supported.
- kitty starts the login shell (its default), so terminals need no per-shell
  setting.

## Why this works on Arch with SDDM

Checked on `sputnik`, 2026-11-07:

- SDDM's `/usr/share/sddm/scripts/wayland-session` has a zsh branch: when
  `$SHELL` is zsh it re-executes itself as a zsh login shell.
- Arch's `zsh` package owns `/etc/zsh/zprofile`, which contains
  `emulate sh -c 'source /etc/profile'`, so `/etc/profile.d/*.sh` is applied
  as under bash.
- The session starts with `uwsm start … hyprland.desktop` from SDDM, not from
  `~/.bash_profile`.

## Why Omarchy needs a workaround

From the community guide
([omacom/omarchy discussion 2495](https://github.com/omacom/omarchy/discussions/2495)):
Omarchy's user environment comes through `~/.bash_profile` → `~/.bashrc` →
its `default/bash/rc`, its aliases and functions are bash files, and its
helpers are bash scripts. Users keep bash as the login shell and either set
each terminal to start zsh or add an `exec zsh` handoff to `~/.bashrc`. With
fish as login shell, users reported a black screen after the LUKS prompt.

## Options considered

| Option | Why not chosen |
|---|---|
| bash login shell with a zsh handoff (first version of this ADR; the owner's Estate Config does this on `sputnik`) | Needed only because Omarchy's environment lives in bash files. |
| bash only (Omarchy) | Fewer interactive features. |
| fish | Does not read `/etc/profile`; SDDM's session script has no fish branch. |

## Borrowed from Omarchy

Omarchy 4.5's `default/bash/` (`aliases`, `functions`, `fns/`, `envs`,
`init`, `completions`, `inputrc`): the aliases (`ls`/`lt` with eza, `ff`,
`cd` with zoxide, `n`, git shortcuts) and functions, rewritten as POSIX for
both shells; tool initialisation moved into the per-shell files; environment
variables moved to uwsm and `environment.d`. Also `config/starship.toml`.

## Consequences

- The Estate Config bash-to-zsh handoff is not needed on Subarchy machines.
- Aliases must stay POSIX-compatible; anything zsh-only goes in the zsh file.
- atuin history sync stays off by default; it would send history to a server.

Related: [[decision-map|Decision map]] · [[0040-terminal|ADR 0040]] · [[0031-session-manager|ADR 0031]] · [[0048-config-ownership|ADR 0048]]
