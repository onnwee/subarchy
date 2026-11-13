# Agent notes for Subarchy

Subarchy is a SUBCULT-branded Arch distribution, built from scratch and
borrowing from Omarchy. It is in development with no release: the live ISO
builds in CI, boots in a VM and installs from that image into an encrypted VM
disk, and it runs on one laptop (`sputnik`).

GitHub `subculture-collective/subarchy` is the source: branches, pull
requests and issues live there. Gitea (`git.subcult.tv`) is a fast-forward
mirror of `main` that runs the main-branch CI (ADR 0051,
`docs/decisions/0051-hosting-ci.md`).

## Layout

- Top-level directories (`bin/`, `config/`, `default/`, `shell/`, `themes/`,
  `install/`, `migrations/`, `applications/`, `branding/`, `packaging/`,
  `iso/`) mirror `/usr/share/omarchy` so upstream files compare path for path.
  Each has a README saying what it holds.
- `cmd/` holds the Go commands (`subcult`, `subarchy-setup`, `subcult-*`) and
  `internal/` the Go packages behind them. `lock/` is the lock screen,
  a separate Quickshell program. `tools/` holds the build, CI, test, ISO,
  theme, roadmap and inventory scripts.
- `.github/workflows/` runs pull-request CI on GitHub; `.gitea/workflows/`
  runs the main-branch jobs (packages, ISO, VM install test) on Gitea.
- `docs/inventory/` holds hand-written summaries. `docs/inventory/generated/`
  is output of `tools/inventory/collect.py`; regenerate it, never edit it.
- `docs/decisions/` holds numbered ADRs. Do not rewrite an accepted ADR; add a
  dated progress note or a superseding one.
- `docs/review/` holds checklists waiting on the owner. `docs/plans/` holds
  implementation plans.
- The repository root is an Obsidian vault; `.obsidian/` holds shared config.
  Read `docs/vault-conventions.md` before adding or renaming notes.

## Rules

- Notes in `docs/` use wikilinks and the frontmatter schema in
  `docs/vault-conventions.md`. Keep note names unique; never add another
  `README.md` under `docs/`. The root and build-folder READMEs use Markdown
  links because the forge reads them.
- Do not commit `.obsidian/workspace*.json` or plugin code. Change plugin
  versions in `tools/obsidian/plugins.json` with fresh SHA-256 values.

- Never edit `/usr/share/omarchy`; read it freely.
- The collector must not record configuration values, tokens or remote-URL
  credentials. Keep it to names, versions, origins and counts.
- Inventory claims carry the date and host they were observed on. Re-verify
  before restating them as current.
- Related sources: `~/Work/Forks/subcult-omarchy-rice` (SUBCULT rice),
  `~/Work/Tools/omarchy-*` (own plugins), the SUBCULT vault for brand voice,
  and Machinum's `10-inventory/Host Briefings/sputnik.md` for host history.

## Check

```bash
make verify                      # gofmt, vet, tests, build, smoke tests, shellcheck, docs check
python3 tools/obsidian/check-vault.py
python3 tools/inventory/collect.py   # on an Omarchy machine, then:
git diff --stat docs/inventory/generated
```
