.pragma library
// Wallpaper rotation (stage 3; reference dizziee.auto-wallpaper, written
// fresh). The list is the folder's images in name order; sequential goes
// to the next one after the current, shuffle to a random other one.

const IMAGE = /\.(png|jpe?g|webp|avif)$/i

function images(names) {
  return (names || []).filter(n => IMAGE.test(String(n))).map(String).sort()
}

// The next wallpaper's name, or "" when the folder has none. random is a
// function returning [0, 1), so tests can fix it.
function next(list, current, mode, random) {
  const l = list || []
  if (l.length === 0)
    return ""
  if (l.length === 1)
    return l[0]
  const i = l.indexOf(current)
  if (mode === "shuffle") {
    const r = typeof random === "function" ? random() : Math.random()
    let j = Math.floor(r * (l.length - 1))
    if (i >= 0 && j >= i)
      j += 1
    return l[Math.min(j, l.length - 1)]
  }
  return l[(i + 1) % l.length]
}

// Whether the rotation runs: on AC always, on battery only by choice.
function active(onBattery, allowOnBattery) {
  return !onBattery || !!allowOnBattery
}

function fileName(path) {
  const s = String(path || "")
  return s.slice(s.lastIndexOf("/") + 1)
}
