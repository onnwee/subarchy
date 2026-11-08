package update

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// ServicesNeedingRestart lists the systemd services whose processes still
// map files that the upgrade replaced or removed (ADR 0026 step 7): a
// "(deleted)" file-backed mapping in /proc/<pid>/maps, with the unit read
// from /proc/<pid>/cgroup. Memory-backed mappings that are always
// "(deleted)" (memfd, shared memory, /tmp, /run, System V) do not count,
// nor do scopes and slices (apps, sessions): those are the user's to
// restart. User services are marked "(user)". Nothing is restarted here.
// Run as root (the `privileged services` step): another user's maps are
// not readable, and system services would otherwise never show.
func ServicesNeedingRestart(proc string) ([]string, error) {
	entries, err := os.ReadDir(proc)
	if err != nil {
		return nil, fmt.Errorf("list processes: %w", err)
	}
	seen := map[string]bool{}
	for _, e := range entries {
		if !e.IsDir() || !isPID(e.Name()) {
			continue
		}
		dir := filepath.Join(proc, e.Name())
		if !mapsReplacedFile(filepath.Join(dir, "maps")) {
			continue
		}
		unit, user := unitOf(filepath.Join(dir, "cgroup"))
		if unit == "" {
			continue
		}
		if user {
			unit += " (user)"
		}
		seen[unit] = true
	}
	var out []string
	for u := range seen {
		out = append(out, u)
	}
	sort.Strings(out)
	return out, nil
}

func isPID(name string) bool {
	if name == "" {
		return false
	}
	for _, c := range name {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// mapsReplacedFile reports whether a process maps a deleted file that
// lives on disk. A process that went away reads as not.
func mapsReplacedFile(mapsPath string) bool {
	f, err := os.Open(mapsPath)
	if err != nil {
		return false
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 64*1024), 1024*1024)
	for sc.Scan() {
		line := sc.Text()
		if !strings.HasSuffix(line, " (deleted)") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 7 {
			continue
		}
		path := fields[5]
		if !strings.HasPrefix(path, "/") || strings.HasPrefix(path, "/memfd:") || strings.HasPrefix(path, "/dev/") ||
			strings.HasPrefix(path, "/tmp/") || strings.HasPrefix(path, "/run/") || strings.HasPrefix(path, "/SYSV") {
			continue
		}
		return true
	}
	return false
}

// unitOf reads the service a process belongs to from its cgroup path
// ("0::/system.slice/sshd.service", or under user@<uid>.service for user
// services). Scopes and slices are not services.
func unitOf(cgroupPath string) (unit string, user bool) {
	data, err := os.ReadFile(cgroupPath)
	if err != nil {
		return "", false
	}
	for _, line := range strings.Split(string(data), "\n") {
		_, path, ok := strings.Cut(line, "::")
		if !ok {
			continue
		}
		parts := strings.Split(strings.TrimSpace(path), "/")
		last := parts[len(parts)-1]
		if !strings.HasSuffix(last, ".service") {
			return "", false
		}
		for _, p := range parts[:len(parts)-1] {
			if strings.HasPrefix(p, "user@") && strings.HasSuffix(p, ".service") {
				return last, true
			}
		}
		return last, false
	}
	return "", false
}
