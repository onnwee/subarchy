---
title: "Roadmap"
type: plan
status: draft
created: 2026-11-06
updated: 2026-11-06
tags: [plan]
---

# Roadmap

Phases assume [[0001-fork-strategy|ADR 0001]] option B is
accepted. If it is not, phases 2 to 4 change.

## Phase 0: inventory (this commit)

- [x] Regenerable inventory of Omarchy 4.5.0 and `sputnik` additions
- [x] Component map, branding surfaces, rice summary
- [x] Fork strategy proposal, triage and open questions
- [ ] Owner review of ADR 0001, [[triage|triage]] and
      [[open-questions|open questions]]

## Phase 1: identity

- Settle the name, `os-release` fields and publisher.
- Produce the missing assets from [[brand-identity|brand identity]]: ASCII
  wordmark, sized icons, Plymouth splash, SDDM theme, Limine branding.
- Check asset and community-plugin licences.

Done when every row in [[branding-surfaces|branding surfaces]] has
a replacement asset or an explicit "keep".

## Phase 2: fork and packages

- Fork `omacom/omarchy` to `git.subcult.tv`; decide whether this repository is
  that fork (ADR 0001 open question).
- Apply the branding diff and the shell overlay fix.
- Build `subcarchy` and `subcarchy-settings` with `provides`/`conflicts` on
  the Omarchy packages.
- Package the SUBCULT theme, the kept rice parts and the kept plugins.
- Stand up a signed Subcarchy pacman repository listed before `[omarchy]`.
- Add CI that builds packages and runs the rice's validation where it applies.

Done when a stock Omarchy 4.5 install can switch to Subcarchy packages with
`pacman` and boot with Subcarchy branding end to end.

## Phase 3: upstream tracking

- Script the upstream merge and record each merge's conflicts.
- Re-run `tools/inventory/collect.py` after each merge and review the diff of
  `docs/inventory/generated/` for new commands, plugins and packages.
- Decide the merge cadence from the first few merges.

## Phase 4: install image

- Choose between Omarchy's ISO builder with Subcarchy package lists and a
  convert-in-place installer.
- Build and boot-test on `sputnik`, then on a clean machine or VM.

Related: [[0001-fork-strategy|ADR 0001]] · [[open-questions|Open questions]]
