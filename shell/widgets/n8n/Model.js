.pragma library
// n8n workflow status (shell plan 2): the server's REST API, read with the
// key from the keyring. The widget passes the server URL to a shell snippet
// that looks the key up with secret-tool and hands it to curl through a
// config file on stdin, so the key is never on a command line.

const SERVICE = "subcult-n8n"
const MARK = "---subcult---"

// The server from the settings: http(s)://host[:port][/path], no trailing
// slash, or "" when unset or not a URL.
function serverUrl(settings) {
  const s = String((settings && settings.server) || "").trim().replace(/\/+$/, "")
  return /^https?:\/\/[A-Za-z0-9.-]+(:\d{1,5})?(\/[A-Za-z0-9._~\/-]*)?$/.test(s) ? s : ""
}

// Exit codes of the fetch snippet.
const EXIT_NO_KEY = 3
const EXIT_UNREACHABLE = 4
const EXIT_REFUSED = 5 // an HTTP error: the key was not accepted

function fetchCommand(server) {
  const script = [
    "key=$(secret-tool lookup service " + SERVICE + ") || exit " + EXIT_NO_KEY,
    '[ -n "$key" ] || exit ' + EXIT_NO_KEY,
    // A key with a quote, backslash or line break cannot go into curl's config.
    "case $key in *\\\"*|*\\\\*) exit " + EXIT_NO_KEY + ";; esac",
    "[ \"$(printf '%s' \"$key\" | wc -l)\" -eq 0 ] || exit " + EXIT_NO_KEY,
    "get() { printf 'header = \"X-N8N-API-KEY: %s\"\\n' \"$key\" | curl -sf --max-time 10 -K - \"$1\"; rc=$?; [ \"$rc\" -eq 0 ] && return 0; [ \"$rc\" -eq 22 ] && exit " + EXIT_REFUSED + "; exit " + EXIT_UNREACHABLE + "; }",
    'get "$1/api/v1/workflows?limit=100"',
    "printf '\\n" + MARK + "\\n'",
    'get "$1/api/v1/executions?status=error&limit=10"'
  ].join("\n")
  return ["sh", "-c", script, "sh", server]
}

// The command to store a key, shown to the user.
function storeHint() {
  return "secret-tool store --label='n8n API key' service " + SERVICE
}

// The snippet's output: { workflows: [{ id, name, active, updatedAt }],
// failed: [{ id, workflowId, startedAt, stoppedAt }] }, or null.
function parse(text) {
  const parts = String(text || "").split(MARK)
  if (parts.length !== 2)
    return null
  try {
    const w = JSON.parse(parts[0])
    const e = JSON.parse(parts[1])
    if (!w || !Array.isArray(w.data) || !e || !Array.isArray(e.data))
      return null
    return {
      workflows: w.data.filter(x => x && x.id !== undefined).map(x => ({
        id: String(x.id), name: String(x.name || x.id), active: x.active === true, updatedAt: String(x.updatedAt || "")
      })).sort((a, b) => (a.active === b.active ? a.name.localeCompare(b.name) : a.active ? -1 : 1)),
      failed: e.data.filter(x => x && x.id !== undefined).map(x => ({
        id: String(x.id), workflowId: String(x.workflowId || ""), startedAt: String(x.startedAt || ""), stoppedAt: String(x.stoppedAt || "")
      }))
    }
  } catch (err) {
    return null
  }
}

function workflowName(data, workflowId) {
  const w = data && data.workflows.find(x => x.id === workflowId)
  return w ? w.name : "workflow " + workflowId
}

// "3/5" active workflows, " ✗2" when executions failed.
function label(data) {
  if (!data)
    return ""
  const active = data.workflows.filter(w => w.active).length
  return active + "/" + data.workflows.length + (data.failed.length > 0 ? " \u2717" + data.failed.length : "")
}

function errorText(code) {
  if (code === EXIT_NO_KEY)
    return "No API key in the keyring"
  if (code === EXIT_UNREACHABLE)
    return "The server did not answer"
  if (code === EXIT_REFUSED)
    return "The server refused the key"
  return code === 0 ? "" : "The check failed (" + code + ")"
}

// "3 min ago", "2 h ago", "4 d ago" for an ISO time; "" when unknown.
function ago(iso, now) {
  const t = new Date(iso)
  if (isNaN(t.getTime()))
    return ""
  const s = Math.max(0, Math.round((now.getTime() - t.getTime()) / 1000))
  if (s < 90)
    return "just now"
  if (s < 3600)
    return Math.round(s / 60) + " min ago"
  if (s < 86400)
    return Math.round(s / 3600) + " h ago"
  return Math.round(s / 86400) + " d ago"
}
