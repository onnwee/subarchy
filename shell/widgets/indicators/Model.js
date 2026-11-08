.pragma library
// Privacy marks: what reads the microphone, a camera or the screen, from
// PipeWire. A device in use has a link from it to a client stream, and
// device nodes carry PwNodeType flags, so a microphone link (from an
// Audio|Source node that is not a stream) or a camera link (from a
// Video|Source node) needs no node tracking. A monitor capture of desktop
// audio links from a sink and lights nothing.
//
// Screen capture is a client stream reading video (media.class
// Stream/Input/Video) linked from something other than a camera: the
// screencast producer. Quickshell 0.3.2 gives video streams no PwNodeType
// flags (spike #42), so the class is the signal. Reading a node's
// properties means tracking it, which costs work per node; only nodes that
// could be a video stream are tracked: untyped ones (type 0) that are not
// PipeWire's drivers or a MIDI bridge. Audio streams, devices and sinks
// carry flags and are never tracked.

// PwNodeType flags.
const AUDIO = 1
const VIDEO = 2
const STREAM = 4
const SOURCE = 8

const NOT_A_STREAM = /^(Dummy-Driver|Freewheel-Driver|Midi-Bridge)$|midi/i

function candidate(node) {
  if (!node || Number(node.type) !== 0)
    return false
  return !NOT_A_STREAM.test(String(node.name || ""))
}

// The ids of tracked candidates that turned out to be video captures.
function captures(candidates) {
  return (candidates || []).filter(n => n && n.mediaClass === "Stream/Input/Video").map(n => n.id)
}

// A capture device of one medium: has the medium's flag and Source, and is
// not itself a stream.
function device(type, medium) {
  const t = Number(type) || 0
  return (t & (medium | SOURCE)) === (medium | SOURCE) && !(t & STREAM)
}

// links: [{ sourceType, targetId }] for every PipeWire link; captures: the
// ids from captures(). Any link counts, paused or active: a client holding
// the device has access to it.
function marks(links, captures) {
  const caps = new Set(captures || [])
  const m = { microphone: false, camera: false, screen: false }
  for (const l of links || []) {
    if (!l)
      continue
    if (device(l.sourceType, AUDIO))
      m.microphone = true
    else if (device(l.sourceType, VIDEO))
      m.camera = true
    else if (caps.has(l.targetId))
      m.screen = true
  }
  return m
}
