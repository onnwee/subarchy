---
title: "ADR 0055: Containers"
type: decision
status: accepted
adr: 55
created: 2026-11-07
updated: 2026-11-13
tags: [decision, adr, system, security]
aliases: [ADR 0055, S11, Containers, Docker]
---

# ADR 0055: Containers

Decision map item S11, added 2026-11-07 because
[[0019-firewall|ADR 0019]] assumed Docker without a decision behind it.
Accepted 2026-11-07.

## Decision

- **Docker** is preinstalled with `docker-compose` and `docker-buildx`.
- The daemon is **socket-activated**: `docker.socket` is enabled and
  `docker.service` is not, so the daemon starts only when a command or
  container needs it ([[0054-lightweight-battery-first|ADR 0054]]).
- The user is **not** in the `docker` group, because membership is
  equivalent to passwordless root. `docker` runs through `sudo`, lazydocker
  reaches the daemon through a polkit prompt, and a setup command grants
  sudoless access behind a warning.
- `ufw-docker` filters published ports ([[0019-firewall|ADR 0019]]).

## Options considered

| Option | Why not chosen |
|---|---|
| Podman, daemonless | No idle daemon at all, but drops `ufw-docker` and some compose setups need changes. |
| None preinstalled | The owner wanted containers ready. |
| User in the `docker` group by default | Any user process could become root. |
| Rootless Docker | Privileged containers, low ports and some networking do not work. |

## Borrowed from Omarchy

`install/config/docker.sh` and its reasoning about the `docker` group,
`docker.socket` in `install/config/enable-services.sh`, and
`omarchy setup security sudoless docker`. `sputnik` runs this way:
`docker.socket` enabled, `docker.service` disabled (2026-11-07).

## Consequences

- The first `docker` command after boot waits for the daemon to start.
- Docker 29.9.2 is in Arch's `extra` (2026-11-07).

## Progress

- 2026-11-13: lazydocker reaches the daemon through polkit. `subcult docker
  tui`, the launcher's lazydocker entry and the `lzd` alias run lazydocker
  directly when the user can write the Docker socket (after `sudo subcult
  docker sudoless` and a new login), and otherwise `pkexec
  /usr/lib/subcult/lazydocker-root`. The polkit action
  `tv.subcult.docker.tui` names that program and asks for an
  administrator's password, kept a few minutes (`auth_admin_keep`). pkexec
  clears the environment, TERM included, so the root side takes the
  terminal type as its only argument. The socket keeps its owner and mode
  (`root:docker`, 0660). lazydocker then runs as root, with root's
  lazydocker config, starting in root's home instead of the current folder.

Related: [[decision-map|Decision map]] · [[0019-firewall|ADR 0019]] · [[app-list|App list]]
