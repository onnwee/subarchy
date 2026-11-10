-- Look and feel: the flat subcult-minimal profile (ADR 0037, ADR 0054).
-- Opaque windows, no gaps, rounding, blur, shadows, dimming or animations,
-- solid 1 px borders. Colours come from theme.lua.
--
-- The shell re-runs this file through `hyprctl eval` when the motion setting
-- or the power source changes, so everything here must be safe to apply
-- again: defaults, then the theme, then the motion gate.

local system = os.getenv("SUBCULT_PATH") or "/usr/share/subcult"

hl.config({
  general = {
    gaps_in = 0,
    gaps_out = 0,
    border_size = 1,
    resize_on_border = true,
    layout = "dwindle",
  },

  decoration = {
    rounding = 0,
    active_opacity = 1.0,
    inactive_opacity = 1.0,
    fullscreen_opacity = 1.0,
    dim_inactive = false,
    shadow = { enabled = false },
    blur = { enabled = false },
  },

  animations = {
    enabled = false,
  },

  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    background_color = "rgb(100B19)",
    force_default_wallpaper = 0,
    animate_manual_resizes = false,
    animate_mouse_windowdragging = false,
    -- A lock program that died leaves the session locked. This lets its
    -- replacement (subcult-lock.service restarts on failure) take that
    -- lock over; without it the compositor refuses every new lock and the
    -- session can only be recovered from a text console (ADR 0070).
    allow_session_lock_restore = true,
  },
})

dofile(system .. "/default/hypr/theme.lua")

-- Motion (rice port; ADR 0054): one setting, ~/.config/subcult/motion.json
-- {"mode": "auto" | "on" | "off"}, shared with the shell and the lock
-- screen. `auto` is on while on AC and off on battery. When motion is off,
-- animations, blur and shadows stay off whatever the theme asked for; when
-- on, the theme's choices stand (the flat default has none).
local function motion_mode()
  local f = io.open((os.getenv("HOME") or "") .. "/.config/subcult/motion.json", "r")
  if not f then
    return "auto"
  end
  local text = f:read("*a") or ""
  f:close()
  local mode = text:match('"mode"%s*:%s*"(%a+)"')
  if mode == "on" or mode == "off" then
    return mode
  end
  return "auto"
end

local function read_line(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local line = f:read("*l")
  f:close()
  return line
end

-- On AC: a mains supply reports online, or there is no battery at all. A
-- battery without a mains device counts as AC unless it is discharging.
local function on_ac()
  local dir = (os.getenv("SUBCULT_SYS") or "/sys") .. "/class/power_supply"
  local list = io.popen("ls -1 '" .. dir:gsub("'", "'\\''") .. "' 2>/dev/null")
  if not list then
    return true
  end
  local mains, online, discharging = false, false, false
  for name in list:lines() do
    local kind = read_line(dir .. "/" .. name .. "/type")
    if kind == "Mains" then
      mains = true
      if read_line(dir .. "/" .. name .. "/online") == "1" then
        online = true
      end
    elseif kind == "Battery" and read_line(dir .. "/" .. name .. "/status") == "Discharging" then
      discharging = true
    end
  end
  list:close()
  if mains then
    return online
  end
  return not discharging
end

local mode = motion_mode()
sub.motion = mode == "on" or (mode == "auto" and on_ac())

if not sub.motion then
  hl.config({
    animations = { enabled = false },
    decoration = { blur = { enabled = false }, shadow = { enabled = false } },
  })
end
