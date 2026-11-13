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

// The baseline for a sink just made the default: its reading when PipeWire
// already has it (the audio panel tracks every sink, so no first reading
// will come), and none while it is still loading, whose first reading is
// then not a change.
function baseline(sink) {
  if (!sink || !sink.ready || !sink.audio)
    return null
  return { volume: sink.audio.volume, muted: sink.audio.muted }
}

// The OSD's volume state: switchTo(sink) when the default sink changes,
// then reading(sink) at each volume or mute signal, which says whether the
// reading is a change to show. The state lives here, not in Osd.qml, so the
// tests cover what a switch does.
function volumeTracker() {
  let last = null
  return {
    switchTo: function (sink) { last = baseline(sink) },
    reading: function (sink) {
      const now = { volume: sink.audio.volume, muted: sink.audio.muted }
      const changed = volumeChanged(last, now)
      last = now
      return changed
    }
  }
}

// The caps-lock label from the `brightness` of every caps-lock LED under
// /sys/class/leds, one per line: on when any is lit. A machine without such
// an LED gets the plain name, since the state is unknown.
function capsLabel(leds) {
  const lines = String(leds).split("\n").map(l => l.trim()).filter(l => /^[0-9]+$/.test(l))
  if (lines.length === 0)
    return "Caps Lock"
  return lines.some(l => Number(l) > 0) ? "Caps Lock on" : "Caps Lock off"
}
