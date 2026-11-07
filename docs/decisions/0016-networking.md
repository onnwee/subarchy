---
title: "ADR 0016: Networking and Wi-Fi"
type: decision
status: accepted
adr: 16
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, system, network]
aliases: [ADR 0016, S2, Networking]
---

# ADR 0016: Networking and Wi-Fi

Decision map item S2. Accepted 2026-11-06.

## Decision

**NetworkManager** with **wpa_supplicant** for Wi-Fi. `iwd` is not installed
or is disabled.

## Options considered

| Option | Why not chosen |
|---|---|
| NetworkManager with the iwd backend | Faster connects, but occasional 802.1X enterprise Wi-Fi quirks. |
| iwd with systemd-networkd | Loses `nmcli`, VPN plugins and per-network settings that panels and tools rely on. |

## Borrowed from Omarchy

`install/hardware/network.sh` (disables `iwd`) and its Wi-Fi regulatory
domain setup (`set-wireless-regdom.sh`).

## Consequences

- Network panels and scripts use `nmcli` or NetworkManager's D-Bus API.
- Per-connection DNS policy (S3) is stored on NetworkManager connections.

Related: [[decision-map|Decision map]] · [[0015-init-system|ADR 0015]]
