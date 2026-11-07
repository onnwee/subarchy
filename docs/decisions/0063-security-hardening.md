---
title: "ADR 0063: Security hardening"
type: decision
status: accepted
adr: 63
created: 2026-11-07
updated: 2026-11-07
tags: [decision, adr, security]
aliases: [ADR 0063, Hardening]
---

# ADR 0063: Security hardening

Accepted 2026-11-07. The owner asked for best practice and the agent's
recommendations.

## Decision

| Area | Setting |
|---|---|
| Mandatory access control | **AppArmor** enabled (`lsm=landlock,lockdown,yama,integrity,apparmor,bpf` on the kernel command line) with Arch's profiles; enforce mode for profiles that ship tested, complain mode otherwise |
| Kernel lockdown | `integrity` mode when Secure Boot is on ([[0012-secure-boot\|ADR 0012]]) |
| `sysctl` | `kernel.kptr_restrict=2`, `kernel.dmesg_restrict=1`, `kernel.unprivileged_bpf_disabled=1`, `net.core.bpf_jit_harden=2`, `kernel.kexec_load_disabled=1`, `fs.protected_fifos=2`, `fs.protected_regular=2`; reverse-path filtering, SYN cookies, no ICMP redirects, no source routing |
| Core dumps | Kept by systemd-coredump for crash reports ([[0056-quality-of-life\|ADR 0056]]), size-limited, setuid dumps off |
| Firewall | ufw default deny incoming ([[0019-firewall\|ADR 0019]]) |
| SSH server | Off unless the user runs the setup wizard; key-only when on |
| USB devices | No USBGuard: it blocks docks and peripherals on a laptop that changes desks; screen lock and disk encryption cover the theft case |
| Security updates | The stable channel lags Arch by about two weeks ([[0026-update-model\|ADR 0026]]). Packages named in Arch Security Advisories (security.archlinux.org) are fast-tracked to stable as soon as CI passes, and the update check flags them |

## Options considered

| Option | Why not chosen |
|---|---|
| SELinux | Little Arch support; AppArmor has Arch profiles and tooling. |
| `linux-hardened` kernel | Conflicts with the `linux-zen` choice ([[0004-kernel\|ADR 0004]]) and breaks some DKMS modules. |
| USBGuard | Too much friction for docks and peripherals. |

## Consequences

- AppArmor profiles can break apps after updates; complain mode for
  untested profiles limits that.
- `unprivileged_bpf_disabled` and `kptr_restrict` can affect profiling tools;
  a documented override exists for development sessions.
- The security fast path needs CI to watch the advisory feed.

## Progress

- 2026-11-07: AppArmor via `lsm=` with `apparmor.service`, the sysctl list
  above (`/usr/lib/sysctl.d/90-subarchy-hardening.conf`), size-limited core
  dumps, and ufw enabled with incoming denied. The VM test checks each. Not
  yet: per-profile enforce/complain choices, kernel lockdown with Secure
  Boot, the SSH wizard, and fast-tracked security updates.

Related: [[decision-map|Decision map]] · [[0062-privilege-policy|ADR 0062]] · [[0012-secure-boot|ADR 0012]]
