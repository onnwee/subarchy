.pragma library
// On-screen display helpers.

// `brightnessctl -m` prints "device,class,current,percent%,max".
function brightness(line) {
  const f = String(line).trim().split(",")
  if (f.length < 5)
    return null
  const p = parseFloat(f[3])
  return isNaN(p) ? null : Math.max(0, Math.min(1, p / 100))
}

// A volume reading is a change worth showing only after the first one.
function volumeChanged(previous, current) {
  if (!previous || !current)
    return false
  return previous.volume !== current.volume || previous.muted !== current.muted
}
