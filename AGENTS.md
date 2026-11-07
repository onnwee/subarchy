# Agent notes for Subcarchy

Subcarchy is a planned SUBCULT-branded distribution built from Omarchy. The
repository is at the inventory and review stage; nothing builds yet.

## Layout

- Top-level directories (`bin/`, `config/`, `default/`, `shell/`, `themes/`,
  `install/`, `migrations/`, `applications/`, `branding/`, `packaging/`,
  `iso/`) mirror `/usr/share/omarchy` so upstream files compare path for path.
  They hold only READMEs until build work starts.
- `docs/inventory/` holds hand-written summaries. `docs/inventory/generated/`
  is output of `tools/inventory/collect.py`; regenerate it, never edit it.
- `docs/decisions/` holds numbered ADRs. Do not rewrite an accepted ADR; add a
  superseding one.
- `docs/review/` holds checklists waiting on the owner.

## Rules

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
python3 tools/inventory/collect.py
git diff --stat docs/inventory/generated
```
