-- Default key bindings, a small subset of Omarchy's (MIT) so muscle memory
-- carries over. The launcher (Super+Space, ADR 0057) and menus arrive with
-- the Quickshell shell.

sub.bind("SUPER + RETURN", "Terminal", sub.launch("xdg-terminal-exec"))
sub.bind("SUPER + SHIFT + B", "Browser", sub.launch("xdg-open https://"))
sub.bind("SUPER + SHIFT + F", "File manager", sub.launch("dolphin"))

sub.bind("SUPER + W", "Close window", hl.dsp.window.close())
sub.bind("SUPER + Q", "Close window", hl.dsp.window.close())
sub.bind("SUPER + J", "Toggle window split", hl.dsp.layout("togglesplit"))
sub.bind("SUPER + T", "Toggle floating", hl.dsp.window.float({ action = "toggle" }))
sub.bind("SUPER + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
sub.bind("SUPER + ALT + F", "Full width", hl.dsp.window.fullscreen({ mode = "maximized" }))

sub.bind("SUPER + LEFT", "Focus left", hl.dsp.focus({ direction = "l" }))
sub.bind("SUPER + RIGHT", "Focus right", hl.dsp.focus({ direction = "r" }))
sub.bind("SUPER + UP", "Focus up", hl.dsp.focus({ direction = "u" }))
sub.bind("SUPER + DOWN", "Focus down", hl.dsp.focus({ direction = "d" }))

for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9) -- 1..0 on the number row
  local id = tostring(workspace)
  sub.bind("SUPER + " .. key, "Workspace " .. id, hl.dsp.focus({ workspace = id }))
  sub.bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. id, hl.dsp.window.move({ workspace = id }))
end

sub.bind("SUPER + S", "Scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))

sub.bind("SUPER + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
sub.bind("SUPER + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })

-- Leave the session cleanly through uwsm (ADR 0031).
sub.bind("SUPER + SHIFT + ESCAPE", "Log out", "uwsm stop")
