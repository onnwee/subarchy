.pragma library
// The tooltip of the display glyph: the name of the output the bar is on.

function tooltip(screen) {
  return screen && typeof screen.name === "string" ? screen.name : ""
}
