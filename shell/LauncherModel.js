.pragma library
// The launcher's search and ranking (ADR 0057): pinned favorites first in
// their fixed order, then everything else by frecency (how often and how
// recently it was used), then by how well it matches, then by name.
// An app is { id, name, genericName, keywords }; history maps an id to
// { count, last } with last in epoch milliseconds.

const DAY = 86400000

// How well an app matches the query: 0 for no match, higher is better.
// Every word of the query must match somewhere.
function match(app, query) {
  const words = String(query || "").toLowerCase().split(/\s+/).filter(w => w !== "")
  if (words.length === 0)
    return 1
  const name = String(app.name || "").toLowerCase()
  const other = [app.genericName || "", app.id || ""].concat(app.keywords || []).join(" ").toLowerCase()
  let total = 0
  for (const w of words) {
    let s = 0
    if (name.startsWith(w))
      s = 4
    else if (name.split(/[\s\-_.]+/).some(part => part.startsWith(w)))
      s = 3
    else if (name.indexOf(w) >= 0)
      s = 2
    else if (other.indexOf(w) >= 0)
      s = 1
    if (s === 0)
      return 0
    total += s
  }
  return total
}

// Use counts weighted by age: recent use counts for more.
function frecency(entry, nowMs) {
  if (!entry || !(entry.count > 0))
    return 0
  const age = nowMs - (entry.last || 0)
  const weight = age < 4 * DAY ? 100 : age < 14 * DAY ? 70 : age < 31 * DAY ? 50 : age < 90 * DAY ? 30 : 10
  return entry.count * weight
}

// The history after one launch, keeping at most cap entries (the least
// frecent go first).
function record(history, id, nowMs, cap) {
  const next = Object.assign({}, history || {})
  const old = next[id] || { count: 0, last: 0 }
  next[id] = { count: old.count + 1, last: nowMs }
  const ids = Object.keys(next)
  if (ids.length > cap) {
    ids.sort((a, b) => frecency(next[b], nowMs) - frecency(next[a], nowMs) || next[b].last - next[a].last)
    for (const drop of ids.slice(cap))
      delete next[drop]
  }
  return next
}

// Results for a query. An empty query is the home screen: the favorites
// only, in their order.
function rank(apps, favorites, history, query, nowMs, limit) {
  const list = apps || []
  const fav = favorites || []
  const hist = history || {}
  const empty = String(query || "").trim() === ""
  const byId = {}
  for (const a of list)
    byId[a.id] = a
  const pinned = fav.filter((id, i) => byId[id] && fav.indexOf(id) === i)
    .filter(id => empty || match(byId[id], query) > 0)
    .map(id => byId[id])
  if (empty)
    return pinned.slice(0, limit)
  const rest = list.filter(a => fav.indexOf(a.id) < 0)
    .map(a => ({ app: a, score: match(a, query), use: frecency(hist[a.id], nowMs) }))
    .filter(r => r.score > 0)
  rest.sort((a, b) => b.use - a.use || b.score - a.score || String(a.app.name).localeCompare(String(b.app.name)))
  return pinned.concat(rest.map(r => r.app)).slice(0, limit)
}

// The favorites list from a launcher config file's text, or null when the
// text is empty or not a config ({"favorites": ["app-id", ...]}).
function favorites(text) {
  if (!text || String(text).trim() === "")
    return null
  try {
    const d = JSON.parse(text)
    if (!d || !Array.isArray(d.favorites))
      return null
    return d.favorites.filter(id => typeof id === "string" && id !== "").map(id => id.replace(/\.desktop$/, ""))
  } catch (e) {
    return null
  }
}

// The history file's text as a history; anything unreadable is empty.
function parseHistory(text) {
  if (!text || String(text).trim() === "")
    return {}
  try {
    const d = JSON.parse(text)
    const out = {}
    if (d && typeof d === "object" && !Array.isArray(d)) {
      for (const id of Object.keys(d)) {
        const e = d[id]
        if (e && e.count > 0 && typeof e.last === "number")
          out[id] = { count: Math.floor(e.count), last: e.last }
      }
    }
    return out
  } catch (e) {
    return {}
  }
}

// Moves a selection by step within count results, without wrapping.
function move(index, step, count) {
  if (count <= 0)
    return -1
  return Math.max(0, Math.min(count - 1, index + step))
}

// --- Commands, calculator and web search ---------------------------------

// What a query asks for: "=" is the calculator, "@" web search; anything
// else is root search.
function parseQuery(query) {
  const q = String(query || "")
  if (q.startsWith("="))
    return { mode: "calc", text: q.slice(1).trim() }
  if (q.startsWith("@"))
    return { mode: "web", text: q.slice(1).trim() }
  return { mode: "root", text: q.trim() }
}

// Root search asks the calculator only for what looks like math: a digit
// and an operator, or a unit conversion ("5 km to mi").
function looksLikeMath(text) {
  const t = String(text || "")
  return /[0-9]/.test(t) && (/[-+*/^%×÷()]/.test(t) || /\s(to|in)\s+\S/i.test(t))
}

// qalc's terse answer, or "" when it has none: an error, or the
// expression handed back unevaluated ("1 / 0").
function calcAnswer(output, expr) {
  const lines = String(output || "").split("\n").map(l => l.trim()).filter(l => l !== "")
  if (lines.length === 0)
    return ""
  const last = lines[lines.length - 1]
  if (/^(error|warning):/i.test(last) || lines.some(l => /^error:/i.test(l)))
    return ""
  const bare = s => s.replace(/\s+/g, "")
  return bare(last) === bare(String(expr || "")) ? "" : last
}

// Launcher items from `subcult commands --json`. Each is ranked like an
// app; its id is the route ("subcult font set").
function commands(text) {
  try {
    const d = JSON.parse(text)
    if (!d || !Array.isArray(d.commands))
      return []
    return d.commands.filter(c => c && typeof c.route === "string" && c.route.startsWith("subcult ") && !c.hidden)
      .map(c => ({
        kind: "command",
        id: c.route,
        name: c.route.slice("subcult ".length),
        genericName: c.summary || "",
        keywords: ["subcult"].concat(c.group ? [c.group] : []),
        args: c.args || "",
        dangerous: c.dangerous === true,
        icon: "utilities-terminal"
      }))
  } catch (e) {
    return []
  }
}

// A query that starts with a whole command's words runs that command, with
// the rest as its arguments ("font set Iosevka"). The longest route wins.
function commandCall(cmds, query) {
  const words = String(query || "").trim().split(/\s+/).filter(w => w !== "")
  if (words.length > 0 && words[0] === "subcult")
    words.shift()
  let best = null
  for (const c of cmds || []) {
    const route = c.name.split(" ")
    if (route.length > words.length)
      continue
    if (route.every((w, i) => words[i] === w) && (!best || route.length > best.route.length))
      best = { command: c, route: route, args: words.slice(route.length) }
  }
  return best ? { command: best.command, args: best.args } : null
}

// The quicklinks: the system file's, then the user's added or replacing
// them by keyword. Each is { name, url }; a url with {query} searches.
function quicklinks(systemText, userText) {
  const read = t => {
    try {
      const d = JSON.parse(t)
      return d && typeof d === "object" ? d : {}
    } catch (e) {
      return {}
    }
  }
  const sys = read(systemText)
  const user = read(userText)
  const links = {}
  for (const src of [sys.quicklinks, user.quicklinks]) {
    if (!src || typeof src !== "object")
      continue
    for (const key of Object.keys(src)) {
      const l = src[key]
      if (l && typeof l.url === "string" && /^https?:\/\//.test(l.url))
        links[key] = { name: typeof l.name === "string" && l.name !== "" ? l.name : key, url: l.url }
    }
  }
  const def = [user.default, sys.default].find(k => typeof k === "string" && links[k] && links[k].url.indexOf("{query}") >= 0)
  return { default: def || "", links: links }
}

function fill(url, query) {
  return url.split("{query}").join(encodeURIComponent(query))
}

// Where a web query goes: a keyword and words search that quicklink
// ("yt cats"); a keyword alone opens a plain link; anything else searches
// the default engine. null when there is nothing to open.
function webTarget(ql, text) {
  const t = String(text || "").trim()
  if (t === "" || !ql)
    return null
  const words = t.split(/\s+/)
  const link = ql.links[words[0]]
  const rest = words.slice(1).join(" ")
  if (link && link.url.indexOf("{query}") >= 0 && rest !== "")
    return { key: words[0], name: link.name, query: rest, url: fill(link.url, rest) }
  if (link && link.url.indexOf("{query}") < 0 && rest === "")
    return { key: words[0], name: link.name, query: "", url: link.url }
  const def = ql.links[ql.default]
  if (!def)
    return null
  return { key: ql.default, name: def.name, query: t, url: fill(def.url, t) }
}
