.pragma library
// The update count that `subcult update check` writes (ADR 0026).

function count(text) {
  const n = parseInt(String(text).trim(), 10)
  return isNaN(n) || n < 0 ? 0 : n
}

function hidden(n) {
  return n <= 0
}
