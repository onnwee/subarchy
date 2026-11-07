.pragma library
// Shown only for a present laptop battery; mice, headsets and UPSes have
// their own UPower devices.

function visible(device) {
  return !!device && !!device.isPresent && !!device.isLaptopBattery
}

// UPower reports 0..1 through Quickshell; accept 0..100 too.
function percent(p) {
  const v = Number(p) || 0
  return Math.round(v <= 1 ? v * 100 : v)
}
