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

// What a query asks for: "=" is the calculator, "@" web search, "." files,
// ":" symbols and emoji; anything else is root search.
function parseQuery(query) {
  const q = String(query || "")
  if (q.startsWith("="))
    return { mode: "calc", text: q.slice(1).trim() }
  if (q.startsWith("@"))
    return { mode: "web", text: q.slice(1).trim() }
  if (q.startsWith("."))
    return { mode: "files", text: q.slice(1).trim() }
  if (q.startsWith(":"))
    return { mode: "symbols", text: q.slice(1).trim() }
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

// --- Script commands, aliases and snippets --------------------------------

// Script commands from the launcher's folder listing: each file starts with
// "\x1e<path>" and is followed by its first lines. A script needs a title in
// a `@raycast.<key>` or `@subcult.<key>` comment; Raycast's keys are read
// as they are, so Raycast script commands run unchanged.
function scripts(text) {
  const out = []
  for (const chunk of String(text || "").split("\x1e")) {
    const nl = chunk.indexOf("\n")
    if (nl < 0)
      continue
    const s = scriptHeader(chunk.slice(0, nl), chunk.slice(nl + 1).split("\n"))
    if (s)
      out.push(s)
  }
  return out
}

function scriptHeader(path, lines) {
  const meta = {}
  for (const line of lines) {
    const m = /^\s*(?:#|\/\/|--|;)\s*@(?:raycast|subcult)\.([A-Za-z0-9]+)\s+(.*?)\s*$/.exec(line)
    if (m)
      meta[m[1]] = m[2]
  }
  if (!meta.title || path === "")
    return null
  const args = []
  for (const key of ["argument1", "argument2", "argument3"]) {
    if (!meta[key])
      break
    let a = {}
    try {
      a = JSON.parse(meta[key]) || {}
    } catch (e) {
      a = {}
    }
    args.push({ placeholder: String(a.placeholder || key), optional: a.optional === true, percentEncoded: a.percentEncoded === true })
  }
  const file = path.slice(path.lastIndexOf("/") + 1)
  const dir = path.slice(0, path.lastIndexOf("/"))
  return {
    kind: "script",
    id: "script:" + file,
    path: path,
    name: meta.title,
    genericName: meta.description || meta.packageName || "Script command",
    keywords: [file].concat(meta.packageName ? [meta.packageName] : []),
    icon: "utilities-terminal",
    mode: ["fullOutput", "compact", "silent"].indexOf(meta.mode) >= 0 ? meta.mode : "compact",
    params: args,
    dangerous: meta.needsConfirmation === "true",
    dir: meta.currentDirectoryPath || dir
  }
}

// How many arguments a script must get before it can run.
function requiredArgs(script) {
  return (script.params || []).filter(p => !p.optional).length
}

// Words typed after a script's alias become its arguments; the last
// argument takes the rest of the line.
function splitArgs(text, count) {
  const words = String(text || "").trim().split(/\s+/).filter(w => w !== "")
  if (count <= 0 || words.length <= count)
    return count <= 0 ? [] : words
  return words.slice(0, count - 1).concat([words.slice(count - 1).join(" ")])
}

// The argv that runs a script in its mode: fullOutput in a terminal that
// stays open, compact with its last output line as a notification, silent
// with no output. dir may start with "~" (Raycast's currentDirectoryPath).
function scriptArgv(script, args, home) {
  const dir = String(script.dir || "").replace(/^~(?=\/|$)/, home)
  const values = (args || []).map((v, i) => script.params && script.params[i] && script.params[i].percentEncoded ? encodeURIComponent(v) : v)
  if (script.mode === "fullOutput")
    return ["uwsm-app", "--", "xdg-terminal-exec", "sh", "-c",
      'cd "$1" || exit; shift; "$@"; s=$?; printf "\\n[exit %d] Press Enter to close." "$s"; read -r _', "sh", dir, script.path].concat(values)
  if (script.mode === "silent")
    return ["sh", "-c", 'cd "$1" || exit; shift; exec "$@" >/dev/null 2>&1', "sh", dir, script.path].concat(values)
  return ["sh", "-c", 'cd "$1" || exit; t=$2; shift 2; out=$("$@" 2>&1); notify-send -a Launcher -- "$t" "$(printf "%s\\n" "$out" | tail -n 1)"',
    "sh", dir, script.name, script.path].concat(values)
}

// The user's aliases: a name for any launcher item, by id ("subcult update",
// an app id, "script:hello.sh", "snippet:Sign-off").
function aliases(text) {
  try {
    const d = JSON.parse(text)
    const out = {}
    if (d && d.aliases && typeof d.aliases === "object") {
      for (const name of Object.keys(d.aliases)) {
        if (/^[A-Za-z0-9_-]+$/.test(name) && typeof d.aliases[name] === "string" && d.aliases[name] !== "")
          out[name] = d.aliases[name]
      }
    }
    return out
  } catch (e) {
    return {}
  }
}

// A query whose first word is an alias: its item and the rest of the line.
function resolveAlias(names, items, query) {
  const q = String(query || "").trim()
  const first = q.split(/\s+/)[0]
  if (!first || !names || !Object.prototype.hasOwnProperty.call(names, first))
    return null
  const item = (items || []).find(i => i.id === names[first])
  return item ? { name: first, item: item, rest: q.slice(first.length).trim() } : null
}

// Snippets from the system and user files ({"snippets": [{name, keyword,
// text}]}), the user's after the system's.
function snippets(systemText, userText) {
  const out = []
  for (const t of [systemText, userText]) {
    let d = null
    try {
      d = JSON.parse(t)
    } catch (e) {
      continue
    }
    if (!d || !Array.isArray(d.snippets))
      continue
    for (const s of d.snippets) {
      if (!s || typeof s.name !== "string" || s.name === "" || typeof s.text !== "string")
        continue
      out.push({
        kind: "snippet",
        id: "snippet:" + s.name,
        name: s.name,
        genericName: s.text.replace(/\s+/g, " ").slice(0, 80),
        keywords: typeof s.keyword === "string" && s.keyword !== "" ? [s.keyword] : [],
        icon: "edit-paste",
        text: s.text
      })
    }
  }
  return out
}

function pad(n) {
  return (n < 10 ? "0" : "") + n
}

// A snippet's text with {date} (2026-11-07), {time} (14:05) and
// {clipboard} filled in; other braces stay.
function expand(text, date, clipboard) {
  const d = date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
  const t = pad(date.getHours()) + ":" + pad(date.getMinutes())
  return String(text).split("{date}").join(d).split("{time}").join(t).split("{clipboard}").join(String(clipboard || ""))
}

// --- Files and symbols ----------------------------------------------------

// The file search (ADR 0056: fd on demand, no index): file and folder names
// under home containing the text, case-insensitive, hidden and ignored
// files skipped, at most 60. Each line of output is "d <path>" or
// "f <path>".
function fdArgv(text, home) {
  return ["sh", "-c", 'fd --color never --fixed-strings --ignore-case --type f --type d --max-results 60 -- "$1" "$2"'
    + ' | while IFS= read -r f; do if [ -d "$f" ]; then printf "d %s\\n" "$f"; else printf "f %s\\n" "$f"; fi; done',
    "sh", text, home]
}

// A path with home shortened to "~".
function tilde(path, home) {
  const p = String(path || "")
  return home && (p === home || p.startsWith(home + "/")) ? "~" + p.slice(home.length) : p
}

const IMAGE = /\.(png|jpe?g|gif|webp|svg|bmp|avif)$/i

function isImage(path) {
  return IMAGE.test(String(path || ""))
}

function fileIcon(path) {
  const p = String(path || "")
  if (isImage(p))
    return "image-x-generic"
  if (/\.(mp4|mkv|webm|mov|avi)$/i.test(p))
    return "video-x-generic"
  if (/\.(mp3|flac|ogg|opus|wav|m4a)$/i.test(p))
    return "audio-x-generic"
  if (/\.pdf$/i.test(p))
    return "application-pdf"
  return "text-x-generic"
}

// Rows from the file search's output, in fd's order.
function files(output, home) {
  const out = []
  for (const line of String(output || "").split("\n")) {
    const m = /^([df]) (.+)$/.exec(line)
    if (!m)
      continue
    const path = m[2]
    const slash = path.lastIndexOf("/")
    const dir = slash > 0 ? path.slice(0, slash) : "/"
    const isDir = m[1] === "d"
    out.push({ kind: "file", id: path, name: path.slice(slash + 1), genericName: tilde(dir, home),
      icon: isDir ? "folder" : fileIcon(path), path: path, isDir: isDir })
  }
  return out
}

// The preview of a file: a folder's first entries, a text file's first
// lines, or a binary file's size.
function previewArgv(path) {
  return ["sh", "-c", 'if [ -d "$1" ]; then ls -1A -- "$1" | head -n 12; elif grep -qI . -- "$1" 2>/dev/null; then head -c 1500 -- "$1" | head -n 12; else stat -c "%s bytes, binary" -- "$1"; fi',
    "sh", path]
}

function symbol(ch, name, group) {
  return { kind: "symbol", id: "symbol:" + ch, name: name, genericName: group, icon: "", char: ch }
}

// Emoji from Unicode's emoji-test.txt (the unicode-emoji package): the
// fully-qualified ones, named, with their group as the second line.
function emoji(text) {
  const out = []
  let group = ""
  for (const line of String(text || "").split("\n")) {
    if (line.startsWith("# group: ")) {
      group = line.slice(9).trim()
      continue
    }
    const m = /^[0-9A-F ]+;\s*fully-qualified\s*#\s*(\S+)\s+E\d+\.\d+\s+(.+)$/.exec(line)
    if (m)
      out.push(symbol(m[1], m[2].trim(), group))
  }
  return out
}

// The symbols file ({"symbols": [{"char", "name", "group"}]}).
function symbols(text) {
  try {
    const d = JSON.parse(text)
    if (!d || !Array.isArray(d.symbols))
      return []
    return d.symbols.filter(s => s && typeof s.char === "string" && s.char !== "" && typeof s.name === "string" && s.name !== "")
      .map(s => symbol(s.char, s.name, typeof s.group === "string" ? s.group : "Symbols"))
  } catch (e) {
    return []
  }
}
