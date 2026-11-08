.pragma library
// Screen capture in progress: a client stream reading video (a screen
// recorder or screen share), seen as a PipeWire node with media.class
// Stream/Input/Video.
//
// Quickshell 0.3.2 gives video streams no PwNodeType flags (spike #42), so
// the class is the signal. Reading a node's properties means tracking it,
// which costs work per node; only nodes that could be a video stream are
// tracked: untyped ones (type 0) that are not PipeWire's drivers or a MIDI
// bridge. Audio streams, devices and sinks carry flags and are never
// tracked.

const NOT_A_STREAM = /^(Dummy-Driver|Freewheel-Driver|Midi-Bridge)$|midi/i

function candidate(node) {
  if (!node || Number(node.type) !== 0)
    return false
  return !NOT_A_STREAM.test(String(node.name || ""))
}

function recording(candidates) {
  return (candidates || []).some(n => n && n.mediaClass === "Stream/Input/Video")
}
