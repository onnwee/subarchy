.pragma library
// Widget manifest rules (ADR 0068). tools/shell/gen-index.py applies the
// same rules at build time.

function validate(m, apiVersion) {
  const errors = []
  if (m === null || typeof m !== "object")
    return ["manifest is not an object"]
  if (m.api !== apiVersion)
    errors.push("api is " + m.api + ", the shell speaks " + apiVersion)
  if (["bar-widget", "service"].indexOf(m.kind) < 0)
    errors.push("kind must be bar-widget or service, not " + m.kind)
  if (!/^subcult\.[a-z0-9-]+$/.test(String(m.id)))
    errors.push("id " + m.id + " must look like subcult.<name>")
  const cost = m.cost || {}
  const timers = Array.isArray(cost.timers) ? cost.timers : []
  for (let i = 0; i < timers.length; i++) {
    const t = timers[i]
    if (!t || typeof t.name !== "string" || !(t.ac > 0) || !(t.battery > 0))
      errors.push("timer " + (t && t.name) + " needs a name and positive ac and battery seconds")
  }
  const hosts = Array.isArray(cost.network) ? cost.network : []
  for (let i = 0; i < hosts.length; i++) {
    if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/.test(String(hosts[i])))
      errors.push("network host " + hosts[i] + " is not a hostname")
  }
  return errors
}
