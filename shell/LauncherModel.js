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
