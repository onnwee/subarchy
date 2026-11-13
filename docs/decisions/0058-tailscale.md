---
title: "ADR 0058: Tailscale"
type: decision
status: accepted
adr: 58
created: 2026-11-07
updated: 2026-11-13
tags: [decision, adr, system, network]
aliases: [ADR 0058, S12, Tailscale, Taildrop]
---

# ADR 0058: Tailscale

Decision map item S12, added 2026-11-07. Accepted 2026-11-07.

## Decision

- **Tailscale** is preinstalled (`tailscale` from Arch's `extra`, 1.104.2 on
  2026-11-07). `tailscaled` is enabled; the user signs in when they want it.
- A **bar panel** shows status, lets the user switch exit nodes and browse
  machines, and copies addresses, as Omarchy's `omarchy.tailscale` panel does.
- **Taildrop**: files sent to the machine land in `~/Downloads`
  automatically, through a small user service.
- MagicDNS and Tailscale's split DNS stay on Tailscale's own link
  ([[0020-dns|ADR 0020]]).

## Options considered

| Option | Why not chosen |
|---|---|
| Not preinstalled | The owner's fleet uses Tailscale on every machine. |

## Borrowed from Omarchy

The `omarchy.tailscale` shell panel, `omarchy-tailscale-receive.service` and
its receive script (staging directory under Downloads), and the exit-node
pause during captive portal sign-in.

## Consequences

- `tailscaled` runs all the time once enabled; it is idle when not signed in.
  ([[0054-lightweight-battery-first|ADR 0054]] counts it.)
- The Taildrop receiver runs only while signed in.
- Proton VPN is also preinstalled ([[app-list|App list]]). When connected it
  sets its own DNS and can block traffic outside the tunnel, which overrides
  the DNS trust policy ([[0020-dns|ADR 0020]]) and can conflict with a
  Tailscale exit node. At home, the owner's gateway already routes through
  Proton, so connecting the app there tunnels twice. Test both together
  before relying on them.
- Firewall: Tailscale manages its own `tailscale0` interface. Omarchy's
  firewall script has no Tailscale rule; check whether ufw needs one when
  implementing ([[0019-firewall|ADR 0019]]).

## Progress

- 2026-11-13: The bar has a Tailscale widget and panel
  (`shell/widgets/tailscale`): connection state, this machine's name and
  address, the other machines with their addresses (a click copies one),
  on and off, sign-in, the exit node, and sending files with Taildrop
  through the desktop portal's file picker (`subcult tailscale send`). It
  is in the default bar and reads `tailscale status --json` every minute on
  AC and five on battery, and when the panel opens.
- 2026-11-13: Privileges. tailscaled refuses `up`, `down`, `set`, `file
  get` and `file cp` to a user who is neither root nor its operator (seen
  with tailscale 1.104.7). Making the user the operator would also let
  any program they run turn on Tailscale SSH, a root SSH server, without
  the local password, so no account is the operator. Decided 2026-11-13
  by the lead under the owner's delegated authority (no operator grant; a
  root helper under polkit); the policy and its reasons are in
  [[0062-privilege-policy|ADR 0062]]. The panel and `subcult tailscale
  send` run `pkexec /usr/lib/subcult/tailscale-helper` with one of `up`,
  `login`, `down`, `exit-node <address>` and `send <address> <name>`;
  polkit action `tv.subcult.tailscale` lets the active session do that
  without a password. Reading `tailscale status --json` needs no rights
  and stays the user's.
- 2026-11-13: Sign-in. The helper's `login` runs plain `tailscale up`,
  prints the sign-in link and leaves. With 1.104.7 the pending sign-in,
  its link and the wish to connect stay in tailscaled after `tailscale up`
  stops, so the browser completes the sign-in there (not yet tried with a
  real account). The panel opens the link and reads
  the status every three seconds, for ten minutes at most, until it shows
  the machine connected. Signed in, the helper runs plain `up`: any flag
  would make it check every setting against its default again. An exit
  node picked in the panel keeps the local network reachable
  (`--exit-node-allow-lan-access=true`); stopping it puts both settings
  back. The panel addresses a machine by its Tailscale address for the
  exit node and for Taildrop. Signed out after an earlier sign-in (a
  sign-out or an expired sign-in), `tailscale up` refuses to run without
  every setting that differs from its default, so `up` and `login` read
  `tailscale debug prefs` and repeat the exit node and the local-network
  setting; without that, an exit node picked earlier made sign-in fail
  until someone ran `tailscale up` with sudo. When tailscaled no longer
  knows the exit node's address, the helper drops both settings, as
  `tailscale up` would drop the exit node anyway. Found in review of PR
  #157 and checked with tailscale 1.104.7 in a container.
- 2026-11-13: Taildrop receive. The Decision's "small user service" became
  a system one, since `tailscale file get` needs root:
  `subcult-taildrop@<user>.service`, enabled by the installer for the
  account it makes and by a migration on older installs. It runs
  `/usr/lib/subcult/taildrop-receive` as root: `tailscale file get --wait
  --conflict=rename` into its own folder under `/var/lib/subcult-taildrop`
  (mode 0700), then each file goes to the user as standard input of the
  same script run as the user (`setpriv`), which writes it to a hidden
  name in `~/Downloads`, gives it a free name (a taken name gets -1, -2
  ...) and announces it. Root never writes in the user's home. `file get`
  writes each file under its final name and then drops it from the inbox,
  so each get uses its own folder, delivered only after the get succeeds;
  a folder from a get that was cut off is thrown away at the next start,
  and tailscaled hands its files over again. That is also why it is
  `--wait` once per round and not `--loop`. Signed out, tailscaled
  answers `file get` with "no storage directory" at once; the receiver
  then waits in `tailscale wait`, which returns once tailscaled is
  connected, and tries again a minute later. "Runs only while signed in"
  became "sleeps while signed out". Only the installed account receives
  files: tailscaled has one inbox per machine. The unit is wanted by
  `tailscaled.service`, so it starts whenever tailscaled does, also when
  an administrator starts tailscaled again after stopping it. It keeps only
  the capabilities to become the user (`CAP_SETUID`, `CAP_SETGID`), with
  `NoNewPrivileges` and a read-only `/usr` and `/etc`; checked under
  systemd in a container, including a `~/Downloads` that links to `/etc`.
  A name in `~/Downloads` taken by a link that points nowhere counts as
  taken, and a numbered name is shortened to fit 255 bytes. A file that
  cannot be saved is announced ("Could not save ...") and stays in the
  staging folder until the next file arrives; nothing removes old files
  there, since they are the user's.
- 2026-11-13, later: a get that fails or is cut off keeps the files it
  finished. In tailscale 1.104.7 `file get` drops each file from the inbox
  as soon as it is written, not at the end of the get, so throwing away
  the folder of a failed get lost those files for good. The receiver now
  runs `file get --verbose`, which logs each file once it is written and
  before it leaves the inbox; the files the log names are delivered, even
  when the get failed or an earlier run was stopped, and only a file it
  does not name (cut off halfway, still in the inbox) is dropped. The
  receiver reads that output from memory, so a full disk that keeps the
  log from being written does not lose a file; the log on disk is only
  for a get that a stop cut off. A file whose removal from the inbox
  failed, or was cut off by a stop, can arrive twice. A folder or a
  link to a folder in `~/Downloads` now also counts as a taken name
  (`ln -T`), and a send to an IPv6 address passes it to `tailscale file
  cp` in brackets, which tailscale requires. Found in review of PR #157.
- Still open: the exit-node pause during captive portal sign-in
  ([[0020-dns|ADR 0020]]) and whether ufw needs a `tailscale0` rule.

Related: [[decision-map|Decision map]] · [[0020-dns|ADR 0020]] · [[0016-networking|ADR 0016]]
