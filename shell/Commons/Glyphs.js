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
const recording = "\u{F044A}"   // record
const updates = "\u{F06B0}"     // update
