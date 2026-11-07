.pragma library
// World clock without Intl (QML's JavaScript has none): each zone's UTC
// offset comes from `date +%z` (see Widget.qml); this formats a time at an
// offset.

function pad(n) {
  return (n < 10 ? "0" : "") + n
}

function formatAt(utcMillis, offsetMinutes, label) {
  const t = new Date(utcMillis + offsetMinutes * 60000)
  return label + " " + pad(t.getUTCHours()) + ":" + pad(t.getUTCMinutes())
}

// "+0900" → 540, "-0330" → -210; anything else → null.
function parseOffset(text) {
  const m = String(text).trim().match(/^([+-])(\d\d)(\d\d)$/)
  if (!m)
    return null
  const minutes = Number(m[2]) * 60 + Number(m[3])
  return m[1] === "-" ? -minutes : minutes
}

// "America/Argentina/Buenos_Aires" → "Buenos Aires"
function label(zone) {
  const parts = String(zone).split("/")
  return parts[parts.length - 1].replace(/_/g, " ")
}
