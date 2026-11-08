.pragma library
// On-screen display helpers.

// A backlight level, 0..1, from the text of sysfs `brightness` and
// `max_brightness`.
function level(raw, max) {
  const r = String(raw).trim()
  const m = String(max).trim()
  if (!/^[0-9]+$/.test(r) || !/^[0-9]+$/.test(m) || Number(m) === 0)
    return null
  return Math.min(1, Number(r) / Number(m))
}

// A volume reading is a change worth showing only after the first one.
function volumeChanged(previous, current) {
  if (!previous || !current)
    return false
  return previous.volume !== current.volume || previous.muted !== current.muted
}
