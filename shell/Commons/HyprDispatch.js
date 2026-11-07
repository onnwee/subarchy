.pragma library
// Hyprland dispatches for a Lua-configured Hyprland (ADR 0032): Quickshell's
// Hyprland.dispatch sends a Lua dispatcher expression.

function workspace(id) {
  return 'hl.dsp.focus({ workspace = "' + Number(id) + '" })'
}

// address: a window address with or without 0x; anything that is not hex
// gives an empty string, so nothing outside the address reaches Lua.
function window(address) {
  const a = String(address).replace(/^0x/, "")
  if (!/^[0-9a-fA-F]+$/.test(a))
    return ""
  return 'hl.dsp.focus({ window = hl.get_window("address:0x' + a + '") })'
}
