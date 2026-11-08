.pragma library
// Workspace names (rice port: subcult.workspace-names). A workspaces file is
// {"workspaces": [{"id": 3, "name": "Workbench", "short": "WRK"}]}; the
// user's entries replace the system's by id. Names are bounded and plain.

const NAME_CAP = 48
const SHORT_CAP = 4

function clean(s, cap) {
  return String(s === undefined || s === null ? "" : s).replace(/[\x00-\x1f\x7f]/g, "").trim().slice(0, cap)
}

function read(text) {
  try {
    const d = JSON.parse(text)
    return d && Array.isArray(d.workspaces) ? d.workspaces : []
  } catch (e) {
    return []
  }
}

// id -> { name, short } for ids 1..10, the user's file over the system's.
function parse(systemText, userText) {
  const out = {}
  for (const list of [read(systemText), read(userText)]) {
    for (const w of list) {
      const id = Number(w && w.id)
      if (!(id >= 1 && id <= 10) || id !== Math.floor(id))
        continue
      const name = clean(w.name, NAME_CAP)
      const short = clean(w.short, SHORT_CAP).toUpperCase()
      if (name === "" && short === "")
        continue
      out[id] = { name: name, short: short }
    }
  }
  return out
}

// The compact label for the bar: the short token, else the first three
// letters of the name, else the number (10 shows as 0).
function label(names, id) {
  const n = (names || {})[id]
  if (n && n.short !== "")
    return n.short
  if (n && n.name !== "")
    return n.name.replace(/[^\p{L}\p{N}]/gu, "").slice(0, 3).toUpperCase() || number(id)
  return number(id)
}

function number(id) {
  return id === 10 ? "0" : String(id)
}

// The full name for tooltips and the switch overlay: "3 · Workbench", or
// the number alone.
function title(names, id) {
  const n = (names || {})[id]
  return n && n.name !== "" ? number(id) + " · " + n.name : "Workspace " + number(id)
}
