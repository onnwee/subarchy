.pragma library
// Widget manifest rules (ADR 0068). tools/shell/gen-index.py applies the
// same rules at build time, and its tests run both on the same manifests.
// Types are strict on both sides: "60", true or ["subcult.x"] is not a
// number or a string here either.

function isObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v)
}

// absent maps a missing or null value to the empty one.
function absent(v, empty) {
  return v === undefined || v === null ? empty : v
}

function validate(m, apiVersion) {
  if (!isObject(m))
    return ["manifest is not an object"]
  const errors = []
  if (m.api !== apiVersion)
    errors.push("api is " + m.api + ", the shell speaks " + apiVersion)
  if (["bar-widget", "service"].indexOf(m.kind) < 0)
    errors.push("kind must be bar-widget or service, not " + m.kind)
  if (typeof m.id !== "string" || !/^subcult\.[a-z0-9-]+$/.test(m.id))
    errors.push("id " + m.id + " must look like subcult.<name>")
  const cost = absent(m.cost, {})
  if (!isObject(cost))
    return errors.concat(["cost must be an object"])
  const timers = absent(cost.timers, [])
  if (!Array.isArray(timers))
    errors.push("cost.timers must be a list")
  else
    for (const t of timers) {
      const positive = k => typeof t[k] === "number" && t[k] > 0
      if (!isObject(t) || typeof t.name !== "string" || !positive("ac") || !positive("battery"))
        errors.push("timer " + (isObject(t) ? t.name : t) + " needs a name and positive ac and battery seconds")
    }
  const hosts = absent(cost.network, [])
  if (!Array.isArray(hosts))
    errors.push("cost.network must be a list")
  else
    for (const h of hosts)
      if (typeof h !== "string" || !/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/.test(h))
        errors.push("network host " + h + " is not a hostname")
  return errors
}
