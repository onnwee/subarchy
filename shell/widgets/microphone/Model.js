.pragma library
// The default input's tooltip: its description (or node name), and "(muted)"
// while it is muted. Empty without an input, so no empty tooltip shows.

function tooltip(source, muted) {
  if (!source)
    return ""
  return (source.description || source.name || "") + (muted ? " (muted)" : "")
}
