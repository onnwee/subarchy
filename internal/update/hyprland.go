package update

import (
	"context"
	"encoding/json"
	"fmt"
	"time"
)

// pauseReload keeps Hyprland from reading a partially replaced Lua tree.
// Restore the previous setting even if an upgrade fails or is interrupted.
func (u *Updater) pauseReload(ctx context.Context) (restore func(), paused bool, err error) {
	restore = func() {}
	if !u.O.HyprlandSession || !u.R.Has("hyprctl") {
		return restore, false, nil
	}
	out, err := u.R.Output(ctx, "hyprctl", "-j", "getoption", "misc:disable_autoreload")
	if err != nil {
		return restore, false, fmt.Errorf("read Hyprland auto-reload setting: %w", err)
	}
	var option struct {
		Bool *bool `json:"bool"`
	}
	if err := json.Unmarshal([]byte(out), &option); err != nil || option.Bool == nil {
		return restore, false, fmt.Errorf("Hyprland did not return its auto-reload setting")
	}
	wasDisabled := *option.Bool
	restore = func() {
		// Ctrl+C cancels package work, but must not strand the file watcher.
		restoreCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
		defer cancel()
		config := fmt.Sprintf("hl.config({ misc = { disable_autoreload = %t } })", wasDisabled)
		if err := u.R.Run(restoreCtx, "hyprctl", "eval", config); err != nil {
			fmt.Fprintf(u.O.Stdout, "warning: Hyprland auto-reload could not be restored: %v\n", err)
		}
	}
	if !wasDisabled {
		if err := u.R.Run(ctx, "hyprctl", "eval", "hl.config({ misc = { disable_autoreload = true } })"); err != nil {
			restore()
			return func() {}, false, fmt.Errorf("pause Hyprland auto-reload: %w", err)
		}
	}
	// A final reload can reset runtime options, including an already disabled
	// watcher. Reapply its original value even when we did not need to pause it.
	return restore, !wasDisabled, nil
}
