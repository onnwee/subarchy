.pragma library
// Layered config (ADR 0048): defaults under the user's file, merged key by
// key. Objects merge recursively; arrays and scalars from the user replace.

function isObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v)
}

function clone(v) {
  return v === undefined ? undefined : JSON.parse(JSON.stringify(v))
}

function merge(defaults, user) {
  const out = clone(defaults) || {}
  if (!isObject(user))
    return out
  for (const key in user) {
    if (isObject(out[key]) && isObject(user[key]))
      out[key] = merge(out[key], user[key])
    else
      out[key] = clone(user[key])
  }
  return out
}

// parse returns the merged config, or the defaults and a warning when the
// user's text is not a JSON object.
function parse(text, defaults) {
  if (text === undefined || text === null || String(text).trim() === "")
    return { config: clone(defaults), warning: "" }
  try {
    const user = JSON.parse(text)
    if (!isObject(user))
      return { config: clone(defaults), warning: "config is not a JSON object; using the defaults" }
    return { config: merge(defaults, user), warning: "" }
  } catch (e) {
    return { config: clone(defaults), warning: "config is not valid JSON (" + e.message + "); using the defaults" }
  }
}

// withWidgetSetting returns a copy of the user's config with one setting of
// one widget changed; nothing else is touched (the scoped write of ADR 0068).
function withWidgetSetting(user, widgetId, key, value) {
  const out = isObject(user) ? clone(user) : {}
  if (!isObject(out.widgets))
    out.widgets = {}
  if (!isObject(out.widgets[widgetId]))
    out.widgets[widgetId] = {}
  out.widgets[widgetId][key] = value
  return out
}
