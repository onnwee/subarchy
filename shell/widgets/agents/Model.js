.pragma library
// The agents widget's data (ADR 0047): the JSON of `subcult agent usage
// --json`, which reads Claude Code's and Codex's local files. Tokens today
// and this week, the pace over the last hour, and the rate limits a provider
// last wrote to disk (Codex); Claude Code keeps none locally.

const INITIALS = { claude: "C", codex: "X" }

// The report, or null when the text is not one.
function parse(text) {
  try {
    const r = JSON.parse(text)
    if (!r || !Array.isArray(r.agents))
      return null
    return r
  } catch (e) {
    return null
  }
}

// The agents to show: the configured ids, in that order, that have files.
function shown(report, ids) {
  if (!report)
    return []
  const want = Array.isArray(ids) ? ids.map(String) : []
  return want.map(id => report.agents.find(a => a.id === id && a.found)).filter(a => a !== undefined)
}

function initial(agent) {
  return INITIALS[agent.id] || String(agent.name || agent.id || "?").charAt(0).toUpperCase()
}

// 1234 -> "1.2k", 2345678 -> "2.3M", 3456789012 -> "3.5G".
function tokens(n) {
  n = Number(n) || 0
  if (n >= 1e9)
    return (n / 1e9).toFixed(1) + "G"
  if (n >= 1e6)
    return (n / 1e6).toFixed(1) + "M"
  if (n >= 1e3)
    return (n / 1e3).toFixed(1) + "k"
  return String(n)
}

// The tightest limit, when the provider reports any.
function limit(agent) {
  const ls = Array.isArray(agent.limits) ? agent.limits : []
  let best = null
  for (const l of ls)
    if (!best || Number(l.usedPercent) > Number(best.usedPercent))
      best = l
  return best
}

// One agent in the bar: its initial and the tightest limit's percentage, or
// the tokens used today when it reports no limits.
function label(agent) {
  const l = limit(agent)
  return initial(agent) + " " + (l ? Math.round(Number(l.usedPercent)) + "%" : tokens(agent.today ? agent.today.total : 0))
}

function barLabel(agents) {
  return agents.map(label).join(" · ")
}

// "resets in 2h 10m", "resets Wed 02:00" when more than a day away, "" when unknown.
function resets(l, now) {
  const at = new Date(l.resetsAt)
  if (isNaN(at.getTime()) || at.getTime() <= 0)
    return ""
  const ms = at.getTime() - now.getTime()
  if (ms <= 0)
    return "resets now"
  if (ms > 24 * 3600000)
    return "resets " + Qt.formatDateTime(at, "ddd hh:mm")
  const h = Math.floor(ms / 3600000)
  const m = Math.floor((ms % 3600000) / 60000)
  return "resets in " + (h > 0 ? h + "h " : "") + m + "m"
}

// A limit's window: "5 h", "7 d".
function window(l) {
  const min = Number(l.windowMinutes) || 0
  if (min >= 1440)
    return Math.round(min / 1440) + " d"
  if (min >= 60)
    return Math.round(min / 60) + " h"
  return min + " min"
}

function tooltip(agents) {
  return agents.map(a => a.name + ": " + tokens(a.today ? a.today.total : 0) + " today, " + tokens(a.paceHour) + "/h").join("\n")
}
