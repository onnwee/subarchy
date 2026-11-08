.pragma library
// Media players over MPRIS (rice port: media controls). The active player
// is the one the user chose while it is still there, else the first one
// playing, else the first. Artwork shows only from local files: a remote
// artwork URL is never fetched (privacy).

function pick(players, chosenId) {
  const list = players || []
  if (list.length === 0)
    return null
  const chosen = chosenId ? list.find(p => p.id === chosenId) : null
  if (chosen)
    return chosen
  return list.find(p => p.playing) || list[0]
}

function artSource(url) {
  const u = String(url || "")
  return u.startsWith("file://") ? u : ""
}

// "Artist – Title", "Title", or the player's name; cut to cap.
function label(title, artist, identity, cap) {
  const t = String(title || "").trim()
  const a = String(artist || "").trim()
  let s = t === "" ? String(identity || "").trim() : (a === "" ? t : a + " – " + t)
  s = s.replace(/\s+/g, " ")
  return cap > 0 && s.length > cap ? s.slice(0, cap - 1) + "…" : s
}
