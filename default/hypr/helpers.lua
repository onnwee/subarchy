-- Helpers shared by Subarchy's Hyprland defaults and user configs.
-- Borrowed in shape from Omarchy's default/hypr/helpers.lua (MIT).

sub = sub or {}

-- Run a command as a scoped systemd unit in the uwsm session (ADR 0031).
function sub.launch(command)
  return "uwsm-app -- " .. command
end

-- Bind keys to a dispatcher, or to a shell command given as a string.
-- The description feeds the keybindings list in the shell.
function sub.bind(keys, description, action, options)
  local opts = options or {}
  opts.description = description
  if type(action) == "string" then
    action = hl.dsp.exec_cmd(action)
  end
  hl.bind(keys, action, opts)
end

-- Replace an existing binding.
function sub.rebind(keys, description, action, options)
  hl.unbind(keys)
  sub.bind(keys, description, action, options)
end
