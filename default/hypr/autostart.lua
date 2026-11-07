-- Session start. Long-running desktop services are systemd user units bound
-- to graphical-session.target (ADR 0031), not started from here; this only
-- hands the session environment to systemd and D-Bus.

hl.on("hyprland.start", function()
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")
end)
