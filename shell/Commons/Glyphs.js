.pragma library
// Nerd Font glyphs for the bar (shell and look design). One place, so a
// glyph change is one edit and the bands are testable.

const menu = "\u25C6"         // ◆, the SUBCULT mark until the brand mark lands
const display = "\u{F0379}"   // nf-md-monitor
const workspaceActive = "■"  // ■, as on sputnik's bar

function clamp(x, lo, hi) {
  return Math.max(lo, Math.min(hi, x))
}

// volume is 0..1 (PipeWire may report more when amplified); 0 reads as muted.
function volume(level, muted) {
  if (muted || level <= 0)
    return "\u{F0581}" // volume_off
  const v = clamp(level, 0, 1)
  return v < 0.34 ? "\u{F057F}" : v < 0.67 ? "\u{F0580}" : "\u{F057E}"
}

function microphone(muted) {
  return muted ? "\u{F036D}" : "\u{F036C}"
}

// strength is 0..1.
function wifi(strength) {
  const s = clamp(strength, 0, 1)
  return s < 0.25 ? "\u{F091F}" : s < 0.5 ? "\u{F0922}" : s < 0.75 ? "\u{F0925}" : "\u{F0928}"
}

function wifiOff() {
  return "\u{F092E}"
}

function ethernet(connected) {
  return connected ? "\u{F0200}" : "\u{F0201}"
}

function bluetooth(enabled, connectedCount) {
  if (!enabled)
    return "\u{F00B2}"
  return connectedCount > 0 ? "\u{F00B1}" : "\u{F00AF}"
}

// percent is 0..100.
function battery(percent, charging) {
  if (charging)
    return "\u{F0084}"
  const p = clamp(Math.round(percent), 0, 100)
  if (p < 10)
    return "\u{F008E}"
  if (p >= 95)
    return "\u{F0079}"
  return String.fromCodePoint(0xF007A + Math.floor(p / 10) - 1)
}

function powerProfile(name) {
  return name === "power-saver" ? "\u{F032A}" : name === "performance" ? "\u{F14DE}" : "\u{F05D1}"
}

const idleInhibit = "\u{F0176}" // coffee
const camera = "\u{F0100}"      // camera
const screenShare = "\u{F1483}" // monitor_share
const updates = "\u{F06B0}"     // update
const calendar = "\u{F00ED}"    // calendar

function bell(unread, dnd) {
  if (dnd)
    return "\u{F009B}" // bell_off
  return unread > 0 ? "\u{F009E}" : "\u{F009A}" // bell_ring : bell
}

function brightness(level) {
  return level < 0.34 ? "\u{F00DE}" : level < 0.67 ? "\u{F00DF}" : "\u{F00E0}" // brightness_5/6/7
}

const capsLock = "\u{F0632}" // keyboard_caps
const mediaPlay = "\u{F040A}"     // play
const mediaPause = "\u{F03E4}"    // pause
const mediaNext = "\u{F04AD}"     // skip_next
const mediaPrevious = "\u{F04AE}" // skip_previous
const mediaNote = "\u{F075A}"     // music

const wallpaper = "\u{F02E9}" // image
