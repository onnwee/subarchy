.pragma library
// Media downloads with yt-dlp (stage 3; reference ussego.otoru, written
// fresh). Pure parts: the URL a pasted text holds, yt-dlp's progress lines,
// and the queue.

// The http(s) URL in a pasted text, else "". Trailing punctuation from a
// sentence is dropped; a bare host gets https://.
function url(text) {
  const t = String(text || "").trim()
  if (t === "")
    return ""
  const m = /https?:\/\/\S+/i.exec(t)
  const strip = s => s.replace(/[.,;:!?)\]}"']+$/, "")
  if (m)
    return strip(m[0])
  if (!/\s/.test(t) && t.indexOf(".") > 0 && t.indexOf("/") !== 0)
    return "https://" + strip(t)
  return ""
}

// yt-dlp --newline progress: "[download]  12.3% of 10.00MiB at 1.00MiB/s ETA 00:05".
// Returns { percent, size, speed, eta } or null for other lines.
function progress(line) {
  const m = /^\[download\]\s+([0-9.]+)%(?:\s+of\s+~?\s*(\S+))?(?:\s+in\s+\S+)?(?:\s+at\s+(.+?))?(?:\s+ETA\s+(\S+))?\s*$/.exec(String(line || ""))
  if (!m)
    return null
  return { percent: Math.max(0, Math.min(100, parseFloat(m[1]))), size: m[2] || "", speed: m[3] || "", eta: m[4] || "" }
}

// The file a finished download landed in, from `--print after_move:filepath`
// (a line that is a path), which yt-dlp also prints for a file it already
// had. Its "has already been downloaded" note goes to stderr under the quiet
// mode --print implies, so stdout never carries it.
function finishedPath(line) {
  const s = String(line || "").trim()
  return s.startsWith("/") ? s : ""
}

// The yt-dlp command for a job. --print implies --quiet, which also turns
// progress off, so --progress brings the [download] lines back.
function command(u, directory, audioOnly) {
  const args = ["yt-dlp", "--newline", "--progress", "--no-colors", "--no-playlist", "--print", "after_move:filepath",
    "--no-simulate", "-P", directory, "-o", "%(title).150B [%(id)s].%(ext)s"]
  if (audioOnly)
    args.push("-x", "--audio-format", "best")
  else
    args.push("-f", "bestvideo*+bestaudio/best", "--merge-output-format", "mp4")
  args.push("--", u)
  return args
}

function expandHome(path, home) {
  const p = String(path || "")
  return p.startsWith("~") ? String(home || "") + p.slice(1) : p
}

// Queue entries are { url, status, percent, ... }. The next one to run.
function nextQueued(jobs) {
  return (jobs || []).find(j => j.status === "queued") || null
}

function fileName(path) {
  const s = String(path || "")
  return s.slice(s.lastIndexOf("/") + 1)
}
