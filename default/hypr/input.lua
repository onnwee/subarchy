-- Keyboard and pointer defaults. The layout follows the one chosen at
-- install (ADR 0024), read from /etc/vconsole.conf.

local function vconsole()
  local values = {}
  local file = io.open("/etc/vconsole.conf", "r")
  if not file then
    return values
  end
  for line in file:lines() do
    local key, value = line:match("^%s*([%w_]+)%s*=%s*\"?(.-)\"?%s*$")
    if key then
      values[key] = value
    end
  end
  file:close()
  return values
end

local console = vconsole()

hl.config({
  input = {
    kb_layout = console.XKBLAYOUT or "us",
    kb_variant = console.XKBVARIANT or "",
    follow_mouse = 1,
    sensitivity = 0,
    touchpad = {
      natural_scroll = true,
      disable_while_typing = true,
    },
  },
})
