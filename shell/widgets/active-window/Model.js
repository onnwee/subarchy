.pragma library
// The focused window's title for the bar; empty when nothing is focused.

function title(toplevel) {
  return toplevel && typeof toplevel.title === "string" ? toplevel.title : ""
}
