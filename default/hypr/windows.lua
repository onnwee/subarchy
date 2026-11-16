-- Files and tools open as centred floating windows. Sizes follow the
-- monitor's logical dimensions, so they fit scaled laptop displays too.
hl.window_rule({
  name = "subcult-files",
  match = { initial_class = "org\\.kde\\.dolphin", modal = false, float = false },
  float = true,
  center = true,
  size = { "monitor_w*0.72", "monitor_h*0.72" },
})

hl.window_rule({
  name = "subcult-tools",
  match = { initial_class = "subcult-utility" },
  float = true,
  center = true,
  size = { "monitor_w*0.66", "monitor_h*0.65" },
  -- Terminals may restore a maximised window from their previous run.
  suppress_event = "maximize",
})

hl.window_rule({
  name = "subcult-dialogs",
  match = { modal = true },
  float = true,
  center = true,
})

hl.window_rule({
  name = "subcult-floating-centre",
  match = { float = true },
  center = true,
})
