.pragma library
// The audio devices for the panel: PipeWire's audio nodes that are
// devices, not streams, split into outputs (sinks) and inputs (sources).
// A node is { id, type, isStream, isSink }; type bit 1 is Audio.

function devices(nodes) {
  const audio = (nodes || []).filter(n => n && (Number(n.type) & 1) && !n.isStream)
  return { sinks: audio.filter(n => n.isSink), sources: audio.filter(n => !n.isSink) }
}

// A volume from a click or drag at x across a bar of width, 0..1.
function volumeAt(x, width) {
  if (!(width > 0))
    return 0
  return Math.max(0, Math.min(1, x / width))
}
