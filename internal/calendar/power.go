package calendar

import (
	"os"
	"path/filepath"
	"strings"
)

// OnBattery reads the power source from sysfs: no mains adapter online
// while a battery is present. A desktop (no battery) counts as AC.
func OnBattery(powerSupply string) bool {
	entries, _ := os.ReadDir(powerSupply)
	mainsOnline, battery := false, false
	for _, e := range entries {
		dir := filepath.Join(powerSupply, e.Name())
		typ, _ := os.ReadFile(filepath.Join(dir, "type"))
		switch strings.TrimSpace(string(typ)) {
		case "Mains":
			online, _ := os.ReadFile(filepath.Join(dir, "online"))
			if strings.TrimSpace(string(online)) == "1" {
				mainsOnline = true
			}
		case "Battery":
			// A peripheral's battery (mouse, headset) has scope Device.
			scope, _ := os.ReadFile(filepath.Join(dir, "scope"))
			if strings.TrimSpace(string(scope)) != "Device" {
				battery = true
			}
		}
	}
	return battery && !mainsOnline
}
