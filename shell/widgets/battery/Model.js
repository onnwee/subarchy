.pragma library
// Shown only for a present laptop battery; mice, headsets and UPSes have
// their own UPower devices. The panel's texts come from here too.

function visible(device) {
  return !!device && !!device.isPresent && !!device.isLaptopBattery
}

// UPower reports 0..1 through Quickshell; accept 0..100 too.
function percent(p) {
  const v = Number(p) || 0
  return Math.round(v <= 1 ? v * 100 : v)
}

// UPowerDeviceState values as Quickshell numbers them.
const CHARGING = 1
const DISCHARGING = 2
const EMPTY = 3
const FULL = 4
const PENDING_CHARGE = 5
const PENDING_DISCHARGE = 6

function stateText(state) {
  switch (Number(state)) {
  case CHARGING: return "Charging"
  case DISCHARGING: return "Discharging"
  case EMPTY: return "Empty"
  case FULL: return "Fully charged"
  case PENDING_CHARGE: return "Not charging (charge limit)"
  case PENDING_DISCHARGE: return "Not discharging"
  }
  return "Unknown"
}

// "2 h 05 min" from seconds; "" for nothing useful.
function duration(seconds) {
  const s = Number(seconds) || 0
  if (s <= 0)
    return ""
  const m = Math.round(s / 60)
  if (m < 60)
    return m + " min"
  const h = Math.floor(m / 60)
  const rest = m % 60
  return h + " h " + (rest < 10 ? "0" : "") + rest + " min"
}

// What the time estimate means for the state; "" when UPower has none yet.
function remainingText(state, timeToEmpty, timeToFull) {
  const st = Number(state)
  if (st === DISCHARGING) {
    const d = duration(timeToEmpty)
    return d ? d + " left" : "Estimating time left"
  }
  if (st === CHARGING) {
    const d = duration(timeToFull)
    return d ? d + " to full" : "Estimating time to full"
  }
  return ""
}

// The charge or discharge rate in watts, signed by the state.
function rateText(changeRate, state) {
  const w = Math.abs(Number(changeRate) || 0)
  if (w < 0.05)
    return ""
  const sign = Number(state) === CHARGING ? "+" : Number(state) === DISCHARGING ? "−" : ""
  return sign + w.toFixed(1) + " W"
}

function healthText(healthPercentage) {
  const h = Number(healthPercentage) || 0
  return h > 0 ? "Health " + Math.round(h) + " %" : ""
}

// The profile choices, in order; performance only where the hardware has it.
function profiles(hasPerformance) {
  const list = [{ id: "power-saver", name: "Power saver" }, { id: "balanced", name: "Balanced" }]
  if (hasPerformance)
    list.push({ id: "performance", name: "Performance" })
  return list
}
