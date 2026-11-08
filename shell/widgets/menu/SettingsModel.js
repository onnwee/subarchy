.pragma library
// The settings panel's data (rice port, issue #79; ADR 0048). Settings are
// described by default/shell/settings.json, not by pages: each names a
// user override file under ~/.config/subcult and a path in its JSON, or
// (fonts) the `subcult font set` flags. The panel shows the current
// values, previews pending changes, applies them to the user files only,
// and undoes the last apply from a record of the values it replaced.

function isObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v)
}

// The schema's settings, dropping entries that cannot be used.
function schema(text) {
  let d
  try {
    d = JSON.parse(text)
  } catch (e) {
    return []
  }
  if (!d || !Array.isArray(d.settings))
    return []
  return d.settings.filter(s => s && typeof s.id === "string" && s.id !== "" && typeof s.kind === "string"
    && (s.kind === "font" ? typeof s.role === "string" : typeof s.file === "string" && Array.isArray(s.path) && s.path.length > 0))
}

function groups(settings) {
  const out = []
  for (const s of settings) {
    const g = String(s.group || "Other")
    if (out.indexOf(g) < 0)
      out.push(g)
  }
  return out
}

function valueAt(obj, path, fallback) {
  let cur = obj
  for (const key of path) {
    if (!isObject(cur) || !(key in cur))
      return fallback
    cur = cur[key]
  }
  return cur === undefined ? fallback : cur
}

// A copy of obj with the value at path set; missing objects are created.
function withValue(obj, path, value) {
  const out = isObject(obj) ? JSON.parse(JSON.stringify(obj)) : {}
  let cur = out
  for (let i = 0; i < path.length - 1; i++) {
    if (!isObject(cur[path[i]]))
      cur[path[i]] = {}
    cur = cur[path[i]]
  }
  cur[path[path.length - 1]] = value
  return out
}

function parseJSON(text) {
  try {
    const d = JSON.parse(text)
    return isObject(d) ? d : {}
  } catch (e) {
    return {}
  }
}

// `subcult font current` lines → { role: family }: "monospace   Iosevka",
// "sans-serif  (default)  resolves to Liberation Sans".
function fonts(text) {
  const out = {}
  for (const line of String(text || "").split("\n")) {
    const m = /^(\S+)\s+(.*)$/.exec(line.trim())
    if (!m)
      continue
    let rest = m[2]
    const r = /resolves to\s+(.+?)(\s+mismatch.*)?$/.exec(rest)
    if (r)
      rest = r[1]
    out[m[1]] = rest.trim()
  }
  return out
}

// The current value of each setting: bar layout from the merged config,
// files from the user's JSON (or the schema default), fonts from `font
// current`.
function current(settings, barConfig, files, fontMap) {
  const out = {}
  for (const s of settings) {
    if (s.kind === "font")
      out[s.id] = (fontMap || {})[s.role] || ""
    else if (s.kind === "widgets")
      out[s.id] = valueAt(barConfig, s.path, [])
    else
      out[s.id] = valueAt(parseJSON((files || {})[s.file]), s.path, s.default)
  }
  return out
}

// A typed value for a setting, or null with a reason.
function coerce(s, text, widgetIds) {
  const t = String(text === undefined || text === null ? "" : text).trim()
  switch (s.kind) {
  case "widgets": {
    const ids = t.split(/[\s,]+/).filter(x => x !== "")
    const unknown = ids.filter(id => (widgetIds || []).indexOf(id) < 0)
    if (unknown.length > 0)
      return { value: null, error: "unknown widget " + unknown.join(", ") }
    return { value: ids, error: "" }
  }
  case "number": {
    if (!/^-?\d+$/.test(t))
      return { value: null, error: "a whole number" }
    const n = parseInt(t, 10)
    if ((s.min !== undefined && n < s.min) || (s.max !== undefined && n > s.max))
      return { value: null, error: "between " + s.min + " and " + s.max }
    return { value: n, error: "" }
  }
  case "choice": {
    const hit = (s.choices || []).find(c => String(c) === t)
    if (hit === undefined)
      return { value: null, error: "one of " + (s.choices || []).join(", ") }
    return { value: hit, error: "" }
  }
  case "font":
    return t === "" ? { value: null, error: "a font family" } : { value: t, error: "" }
  }
  return { value: null, error: "unknown kind" }
}

function show(v) {
  return Array.isArray(v) ? v.join(" ") : String(v === undefined || v === null ? "" : v)
}

function same(a, b) {
  return JSON.stringify(a) === JSON.stringify(b)
}

// The preview lines for the pending changes: what changes and what is
// written or run.
function preview(settings, pending, current) {
  const lines = []
  for (const s of settings) {
    if (!(s.id in pending) || same(pending[s.id], current[s.id]))
      continue
    const target = s.kind === "font" ? "runs subcult font set " + show(pending[s.id]) + " " + (s.flags || []).join(" ")
      : "writes ~/.config/subcult/" + s.file + (s.after ? ", then runs " + s.after.join(" ") : "")
    lines.push(s.label + ": " + show(current[s.id]) + " → " + show(pending[s.id]) + "  (" + target.trim() + ")")
  }
  return lines
}

// The writes and commands that apply the pending values, and the record
// that undoes them. files maps a setting's file to its user text now.
function plan(settings, pending, current, files) {
  const docs = {}
  const commands = []
  const after = []
  const undo = {}
  for (const s of settings) {
    if (!(s.id in pending) || same(pending[s.id], current[s.id]))
      continue
    undo[s.id] = current[s.id]
    if (s.kind === "font") {
      commands.push(["subcult", "font", "set", show(pending[s.id])].concat(s.flags || []))
      continue
    }
    if (!(s.file in docs))
      docs[s.file] = parseJSON((files || {})[s.file])
    docs[s.file] = withValue(docs[s.file], s.path, pending[s.id])
    if (s.after && !after.some(a => same(a, s.after)))
      after.push(s.after)
  }
  const writes = Object.keys(docs).map(f => ({ file: f, text: JSON.stringify(docs[f], null, 2) + "\n" }))
  return { writes: writes, commands: commands.concat(after), undo: undo }
}
