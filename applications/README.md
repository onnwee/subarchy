# applications

Default desktop entries and web-app launchers, installed to
`/usr/share/applications/`. Omarchy ships 15 in
`/usr/share/omarchy/applications/` (Basecamp, HEY, WhatsApp, YouTube and
others); see [the layout inventory](../docs/inventory/generated/omarchy-layout.md).

| Entry | What |
|---|---|
| `subcult-lazydocker.desktop` | lazydocker in a terminal through `subcult docker tui`, which asks for the password through polkit while the user is not in the `docker` group ([ADR 0055](../docs/decisions/0055-containers.md)) |
| `discord.desktop` | Discord as a Chromium app window ([ADR 0042](../docs/decisions/0042-browser.md)); the Vencord Web extension comes from `default/chromium/extensions/`. The same entry is what `subcult app webapp install` writes for any site, into `~/.local/share/applications/` |

The rest of the default set is undecided; see [the review checklist](../docs/review/review-index.md).
