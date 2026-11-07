.pragma library
// Screen capture in progress: a client stream reading video (a screen
// recorder or screen share). A camera or screen source alone is not one.

function recording(nodes) {
  return (nodes || []).some(n => n.isStream && n.mediaClass === "Stream/Input/Video")
}
