package update

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// fakeProc writes one process into a fake /proc tree.
func fakeProc(t *testing.T, proc, pid, cgroup string, maps ...string) {
	t.Helper()
	dir := filepath.Join(proc, pid)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	body := ""
	for _, m := range maps {
		body += m + "\n"
	}
	if err := os.WriteFile(filepath.Join(dir, "maps"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "cgroup"), []byte("0::"+cgroup+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}

const (
	libOK      = "7f00 r-xp 00000000 00:1e 1 /usr/lib/libc.so.6"
	libGone    = "7f01 r-xp 00000000 00:1e 2 /usr/lib/libssl.so.3 (deleted)"
	binGone    = "5500 r-xp 00000000 00:1e 3 /usr/bin/sshd (deleted)"
	memfdGone  = "7f02 rw-s 00000000 00:01 4 /memfd:pulseaudio (deleted)"
	shmGone    = "7f03 rw-s 00000000 00:01 5 /dev/shm/wayland (deleted)"
	tmpGone    = "7f04 rw-s 00000000 00:01 6 /tmp/.X11-unix/x (deleted)"
	sysvGone   = "7f05 rw-s 00000000 00:01 7 /SYSV00000000 (deleted)"
	runUserOld = "7f06 rw-s 00000000 00:01 8 /run/user/1000/pulse/shm (deleted)"
)

func TestServicesNeedingRestart(t *testing.T) {
	proc := t.TempDir()
	fakeProc(t, proc, "100", "/system.slice/sshd.service", libOK, libGone)
	fakeProc(t, proc, "101", "/system.slice/sshd.service", binGone) // the same unit twice
	fakeProc(t, proc, "102", "/system.slice/NetworkManager.service", libOK)
	fakeProc(t, proc, "103", "/user.slice/user-1000.slice/user@1000.service/session.slice/pipewire.service", libGone)
	fakeProc(t, proc, "104", "/user.slice/user-1000.slice/user@1000.service/app.slice/app-kitty-1.scope", libGone) // not a service
	fakeProc(t, proc, "105", "/system.slice/dbus.service", memfdGone, shmGone, tmpGone, sysvGone, runUserOld)
	fakeProc(t, proc, "106", "/system.slice/system-getty.slice/getty@tty1.service", libGone)
	fakeProc(t, proc, "self", "/system.slice/subcult.service", libGone) // not a pid
	if err := os.WriteFile(filepath.Join(proc, "uptime"), []byte("1 1\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	got, err := ServicesNeedingRestart(proc)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"getty@tty1.service", "pipewire.service (user)", "sshd.service"}
	if !slices.Equal(got, want) {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestServicesNeedingRestartUnreadable(t *testing.T) {
	proc := t.TempDir()
	fakeProc(t, proc, "200", "/system.slice/a.service", libGone)
	// A process that went away between listing and reading: no maps file.
	if err := os.MkdirAll(filepath.Join(proc, "201"), 0o755); err != nil {
		t.Fatal(err)
	}
	got, err := ServicesNeedingRestart(proc)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(got, []string{"a.service"}) {
		t.Errorf("got %q", got)
	}
	if _, err := ServicesNeedingRestart(filepath.Join(proc, "missing")); err == nil {
		t.Error("a missing proc tree must be an error")
	}
}

func TestReportServicesInSummary(t *testing.T) {
	r := Report{ServicesToRestart: []string{"sshd.service", "pipewire.service (user)"}}
	s := r.Summary()
	if !strings.Contains(s, "Services using replaced files: sshd.service, pipewire.service (user). Restart them, or reboot.") {
		t.Errorf("summary = %q", s)
	}
	if strings.Contains(Report{}.Summary(), "Services") {
		t.Error("no services, no line")
	}
}
