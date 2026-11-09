.pragma library
// Palette roles (Theme Tender's names) to the shell's colour tokens. A role
// that is missing or not #RRGGBB comes from the fallback palette.

const map = {
  base: "base", mantle: "mantle", crust: "crust", surface: "surface0",
  text: "text", subtext: "subtext0", muted: "overlay0", accent: "green",
  border: "mauve", borderInactive: "surface0", selection: "selection_bg",
  warning: "yellow", error: "red"
}

function valid(v) {
  return typeof v === "string" && /^#[0-9A-Fa-f]{6}$/.test(v)
}

function tokens(palette, fallback) {
  const p = palette || {}
  const f = fallback || {}
  const out = {}
  for (const token in map) {
    const role = map[token]
    out[token] = valid(p[role]) ? p[role] : f[role]
  }
  return out
}
