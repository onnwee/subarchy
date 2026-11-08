.pragma library
// SomaFM radio (shell plan 2): the channel list from somafm.com's
// channels.json, the stream for a channel, and the lines mpv's JSON IPC
// sends while it plays. Both the playlist URL and anything mpv is given are
// checked to be https on a somafm.com host.

const MAX_URL = 200

function isSomaUrl(url) {
  const m = /^https:\/\/([a-z0-9.-]+)\//i.exec(String(url || ""))
  if (!m || String(url).length > MAX_URL)
    return false
  const host = m[1].toLowerCase()
  return host === "somafm.com" || host.endsWith(".somafm.com")
}

// channels.json -> [{ id, title, description, genre, dj, listeners, playlists }], by title.
// Throws on anything that is not the document, so the caller shows an error.
function parseChannels(text) {
  const doc = JSON.parse(text)
  if (!doc || !Array.isArray(doc.channels))
    throw new Error("no channels")
  const out = []
  for (const c of doc.channels) {
    if (!c || typeof c.id !== "string" || !/^[a-z0-9-]+$/i.test(c.id))
      continue
    const playlists = (Array.isArray(c.playlists) ? c.playlists : [])
      .filter(p => p && isSomaUrl(p.url))
      .map(p => ({ url: String(p.url), format: String(p.format || ""), quality: String(p.quality || "") }))
    if (playlists.length === 0)
      continue
    out.push({
      id: c.id, title: String(c.title || c.id), description: String(c.description || ""),
      genre: String(c.genre || ""), dj: String(c.dj || ""), listeners: Number(c.listeners) || 0,
      lastPlaying: String(c.lastPlaying || ""), playlists: playlists
    })
  }
  out.sort((a, b) => a.title.localeCompare(b.title))
  return out
}

// The playlist to play: the wanted format at the highest quality, else mp3,
// else the first. "" when the channel has none.
function streamUrl(channel, format) {
  if (!channel || !Array.isArray(channel.playlists) || channel.playlists.length === 0)
    return ""
  const rank = q => q === "highest" ? 0 : q === "high" ? 1 : 2
  const pick = f => channel.playlists.filter(p => p.format === f).sort((a, b) => rank(a.quality) - rank(b.quality))[0]
  const p = pick(String(format || "aac")) || pick("mp3") || channel.playlists[0]
  return p && isSomaUrl(p.url) ? p.url : ""
}

function find(channels, id) {
  return (channels || []).find(c => c.id === id) || null
}

// Channels whose title, genre, description or DJ contains the query.
function filter(channels, query) {
  const q = String(query || "").trim().toLowerCase()
  if (q === "")
    return channels || []
  return (channels || []).filter(c => [c.title, c.genre, c.description, c.dj].some(s => s.toLowerCase().indexOf(q) >= 0))
}

// One line of mpv's IPC: { name, data } for a property change, null otherwise.
function ipcEvent(line) {
  try {
    const d = JSON.parse(line)
    if (d && d.event === "property-change" && typeof d.name === "string")
      return { name: d.name, data: d.data === undefined ? null : d.data }
  } catch (e) {
  }
  return null
}

// mpv's media-title: the song once the stream sends one; the playlist file
// name or the stream's own name until then, which read as nothing.
function nowPlaying(title) {
  const t = String(title || "").trim()
  if (t === "" || /\.pls$/i.test(t) || /^[a-z0-9]+-\d+-(aac|aacp|mp3)$/i.test(t))
    return ""
  return t
}

function elide(s, max) {
  s = String(s || "")
  return s.length > max ? s.slice(0, max - 1) + "…" : s
}

// The bar: "Groove Salad · Artist - Title", or the channel alone.
function label(channel, song) {
  if (!channel)
    return ""
  return elide(song ? channel.title + " · " + song : channel.title, 44)
}

// The mpv command for a stream.
function mpvCommand(url, socketPath) {
  return ["mpv", "--no-video", "--no-terminal", "--really-quiet", "--audio-display=no", "--input-ipc-server=" + socketPath, "--", url]
}

function observe() {
  return '{"command":["observe_property",1,"media-title"]}\n{"command":["observe_property",2,"core-idle"]}\n'
}
