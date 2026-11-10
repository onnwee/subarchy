package update

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// fake records commands and answers queries from a table.
type fake struct {
	tools   map[string]bool
	outputs map[string]string   // joined argv -> output
	series  map[string][]string // joined argv -> one output per call, in order
	fail    map[string]bool     // joined argv -> error
	ran     []string
}

func (f *fake) Run(ctx context.Context, argv ...string) error {
	key := strings.Join(argv, " ")
	f.ran = append(f.ran, key)
	if err := ctx.Err(); err != nil {
		return err
	}
	if f.fail[key] {
		return errors.New("failed")
	}
	return nil
}

func (f *fake) Output(_ context.Context, argv ...string) (string, error) {
	key := strings.Join(argv, " ")
	if f.fail[key] {
		return "", errors.New("failed")
	}
	if s := f.series[key]; len(s) > 0 {
		f.series[key] = s[1:]
		return s[0], nil
	}
	out, ok := f.outputs[key]
	if !ok && strings.HasPrefix(key, "pacman -Qdtq") {
		return "", errors.New("exit 1") // no orphans
	}
	return out, nil
}

func (f *fake) Has(name string) bool { return f.tools[name] }

func modulesDir(t *testing.T, kernels ...string) string {
	t.Helper()
	dir := t.TempDir()
	for _, k := range kernels {
		if err := os.MkdirAll(filepath.Join(dir, k), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, k, "pkgbase"), []byte("linux\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func newUpdater(t *testing.T, f *fake, yes bool) (*Updater, *bytes.Buffer) {
	t.Helper()
	out := &bytes.Buffer{}
	return &Updater{R: f, O: Options{
		Yes:        yes,
		Version:    "0.0.0",
		ModulesDir: modulesDir(t, "7.2.14-zen1-1-zen", "6.18.60-1-lts"),
		Migrations: Migrations{Dir: t.TempDir(), StateDir: filepath.Join(t.TempDir(), "state")},
		Stdin:      strings.NewReader(""),
		Stdout:     out,
		Privileged: []string{"sudo", "/usr/bin/subcult-update", "privileged"},
	}}, out
}

const snapshotCmd = "sudo /usr/bin/subcult-update privileged snapshot"

func TestRunOrder(t *testing.T) {
	f := &fake{
		tools:   map[string]bool{"snapper": true, "paccache": true, "mise": true},
		outputs: map[string]string{snapshotCmd: "7\n", "uname -r": "7.2.14-zen1-1-zen\n"},
	}
	u, _ := newUpdater(t, f, true)
	rep, err := u.Run(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"sudo /usr/bin/subcult-update privileged upgrade --noconfirm", "mise upgrade",
		"sudo /usr/bin/subcult-update privileged prune"}
	if !slices.Equal(f.ran, want) {
		t.Errorf("ran %q, want %q", f.ran, want)
	}
	if rep.Snapshot != "7" || rep.RebootNeeded {
		t.Errorf("report = %+v", rep)
	}
	if !strings.Contains(rep.Summary(), "Snapshot 7") || !strings.Contains(rep.Summary(), "No reboot needed") {
		t.Errorf("summary = %q", rep.Summary())
	}
}

const shellRestart = "systemctl --user try-restart subcult-shell.service"
const displayRestart = "systemctl --user try-restart subcult-display.service"

const pauseReload = "hyprctl eval hl.config({ misc = { disable_autoreload = true } })"
const resumeReload = "hyprctl eval hl.config({ misc = { disable_autoreload = false } })"

func TestUpdatePausesHyprlandReload(t *testing.T) {
	for _, tt := range []struct {
		name, option, failure string
		wantError             bool
	}{
		{name: "successful upgrade", option: `{"bool":false}`},
		{name: "already disabled", option: `{"bool":true}`},
		{name: "failed upgrade restores", option: `{"bool":false}`, failure: "sudo /usr/bin/subcult-update privileged upgrade --noconfirm", wantError: true},
		{name: "failed migration restores", option: `{"bool":false}`, failure: "bash -euo pipefail", wantError: true},
		{name: "cannot pause stops upgrade", option: `{"bool":false}`, failure: pauseReload, wantError: true},
		{name: "unknown option stops upgrade", option: `{}`, wantError: true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			f := &fake{tools: map[string]bool{"hyprctl": true}, outputs: map[string]string{"hyprctl -j getoption misc:disable_autoreload": tt.option}, fail: map[string]bool{tt.failure: true}}
			u, _ := newUpdater(t, f, true)
			u.O.HyprlandSession = true
			if tt.option == `{"bool":true}` {
				f.series = map[string][]string{"pacman -Q subarchy": {"subarchy 1", "subarchy 2"}}
			}
			if tt.failure == "bash -euo pipefail" {
				script := filepath.Join(u.O.Migrations.Dir, "1794256000.sh")
				if err := os.WriteFile(script, []byte("false\n"), 0o644); err != nil {
					t.Fatal(err)
				}
				delete(f.fail, tt.failure)
				f.fail["bash -euo pipefail "+script] = true
			}
			_, err := u.Run(context.Background())
			if (err != nil) != tt.wantError {
				t.Fatalf("error %v, wantError %v", err, tt.wantError)
			}
			upgrade := slices.Index(f.ran, "sudo /usr/bin/subcult-update privileged upgrade --noconfirm")
			pause := slices.Index(f.ran, pauseReload)
			if tt.failure == pauseReload || tt.option == `{}` {
				if upgrade >= 0 {
					t.Fatalf("unprotected upgrade: %v", f.ran)
				}
				return
			}
			if tt.option == `{"bool":true}` {
				if slices.Contains(f.ran, resumeReload) {
					t.Fatalf("enabled owner's disabled watcher: %v", f.ran)
				}
				if slices.Index(f.ran, pauseReload) <= slices.Index(f.ran, "hyprctl reload") {
					t.Fatalf("did not preserve disabled setting across reload: %v", f.ran)
				}
				return
			}
			resume := slices.Index(f.ran, resumeReload)
			if pause < 0 || upgrade <= pause || resume <= upgrade {
				t.Fatalf("watcher protection order: %v", f.ran)
			}
			if !tt.wantError && slices.Index(f.ran, "hyprctl reload") <= upgrade {
				t.Fatalf("no final reload: %v", f.ran)
			}
			if tt.wantError && slices.Contains(f.ran, "hyprctl reload") {
				t.Fatalf("reloaded incomplete update: %v", f.ran)
			}
		})
	}
}

func TestRunRestartsShellWhenSubarchyChanged(t *testing.T) {
	f := &fake{
		tools:  map[string]bool{},
		series: map[string][]string{"pacman -Q subarchy": {"subarchy 0.1.0-1\n", "subarchy 0.2.0-1\n"}},
	}
	u, _ := newUpdater(t, f, true)
	rep, err := u.Run(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(f.ran, shellRestart) {
		t.Errorf("ran %q, want the shell restarted", f.ran)
	}
	if !rep.ShellRestarted || !strings.Contains(rep.Summary(), "The desktop shell was restarted.") {
		t.Errorf("report = %+v, summary = %q", rep, rep.Summary())
	}
	if i := slices.Index(f.ran, shellRestart); i != len(f.ran)-1 {
		t.Errorf("the restart must come last, after migrations and cleanup: %q", f.ran)
	}
	// The monitor watcher is a long-running program from the same package;
	// left alone it runs the old binary and the report names it every time.
	if !slices.Contains(f.ran, displayRestart) {
		t.Errorf("ran %q, want the monitor watcher restarted", f.ran)
	}
}

func TestRunLeavesShellWhenSubarchyUnchanged(t *testing.T) {
	f := &fake{
		tools:   map[string]bool{},
		outputs: map[string]string{"pacman -Q subarchy": "subarchy 0.1.0-1\n"},
	}
	u, _ := newUpdater(t, f, true)
	rep, err := u.Run(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if slices.Contains(f.ran, shellRestart) || slices.Contains(f.ran, displayRestart) || rep.ShellRestarted {
		t.Errorf("the shell was restarted for an unchanged package: %q", f.ran)
	}
	if strings.Contains(rep.Summary(), "shell") {
		t.Errorf("summary mentions the shell: %q", rep.Summary())
	}
}

func TestHyprlandReloadFailureDoesNotClaimSuccessOrSkipShell(t *testing.T) {
	f := &fake{
		tools:   map[string]bool{"hyprctl": true},
		outputs: map[string]string{"hyprctl -j getoption misc:disable_autoreload": `{"bool":false}`},
		series:  map[string][]string{"pacman -Q subarchy": {"subarchy 0.0.0-1", "subarchy 0.0.0-421"}},
		fail:    map[string]bool{"hyprctl reload": true},
	}
	u, out := newUpdater(t, f, true)
	u.O.HyprlandSession = true
	rep, err := u.Run(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if rep.HyprlandReloaded || strings.Contains(rep.Summary(), "The Hyprland configuration was reloaded.") {
		t.Errorf("failed reload reported success: %+v", rep)
	}
	if !strings.Contains(out.String(), "Hyprland reload: failed (continuing)") || !rep.ShellRestarted {
		t.Errorf("reload failure hid the error or skipped shell recovery: %s, %+v", out, rep)
	}
}

func TestHyprlandWatcherRestoresAfterCancellation(t *testing.T) {
	f := &fake{tools: map[string]bool{"hyprctl": true}, outputs: map[string]string{"hyprctl -j getoption misc:disable_autoreload": `{"bool":false}`}}
	u, out := newUpdater(t, f, true)
	u.O.HyprlandSession = true
	ctx, cancel := context.WithCancel(context.Background())
	restore, paused, err := u.pauseReload(ctx)
	if err != nil || !paused {
		t.Fatalf("pause = %v, %v", paused, err)
	}
	cancel()
	restore()
	if !slices.Contains(f.ran, resumeReload) || strings.Contains(out.String(), "could not be restored") {
		t.Fatalf("canceled update left watcher paused: %v, %s", f.ran, out)
	}
}

func TestHyprlandWatcherRestoreFailureWarns(t *testing.T) {
	f := &fake{tools: map[string]bool{"hyprctl": true}, outputs: map[string]string{"hyprctl -j getoption misc:disable_autoreload": `{"bool":false}`}, fail: map[string]bool{resumeReload: true}}
	u, out := newUpdater(t, f, true)
	u.O.HyprlandSession = true
	if _, err := u.Run(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "auto-reload could not be restored") {
		t.Fatalf("missing recovery warning: %s", out)
	}
}

func TestSnapshotFailureStops(t *testing.T) {
	f := &fake{tools: map[string]bool{"snapper": true}, fail: map[string]bool{snapshotCmd: true}}
	u, _ := newUpdater(t, f, true)
	if _, err := u.Run(context.Background()); err == nil || !strings.Contains(err.Error(), "--no-snapshot") {
		t.Fatalf("err = %v", err)
	}
	if len(f.ran) != 0 {
		t.Errorf("ran %q after a failed snapshot", f.ran)
	}
}

func TestNoSnapshotAndPackageFailure(t *testing.T) {
	f := &fake{tools: map[string]bool{"snapper": true}, fail: map[string]bool{"sudo /usr/bin/subcult-update privileged upgrade": true}}
	u, _ := newUpdater(t, f, false)
	u.O.NoSnapshot = true
	_, err := u.Run(context.Background())
	if err == nil || !strings.HasPrefix(err.Error(), "packages:") {
		t.Fatalf("err = %v", err)
	}
}

func TestOptionalFailureContinues(t *testing.T) {
	f := &fake{
		tools: map[string]bool{"yay": true, "fwupdmgr": true},
		fail:  map[string]bool{"fwupdmgr update": true},
	}
	u, out := newUpdater(t, f, true)
	if _, err := u.Run(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(f.ran, "yay -Sua --noconfirm") || !strings.Contains(out.String(), "firmware: failed (continuing)") {
		t.Errorf("ran %q, out %q", f.ran, out)
	}
}

func TestOrphans(t *testing.T) {
	for _, tt := range []struct {
		name, stdin string
		yes, remove bool
	}{
		{"yes flag", "", true, true},
		{"answered y", "y\n", false, true},
		{"answered no", "n\n", false, false},
		{"no answer", "", false, false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			f := &fake{outputs: map[string]string{"pacman -Qdtq": "a\nb\n"}}
			u, _ := newUpdater(t, f, tt.yes)
			u.O.Stdin = strings.NewReader(tt.stdin)
			if _, err := u.Run(context.Background()); err != nil {
				t.Fatal(err)
			}
			removed := slices.Contains(f.ran, "sudo pacman -Rns --noconfirm a b")
			if removed != tt.remove {
				t.Errorf("removed = %v, ran %q", removed, f.ran)
			}
		})
	}
}

func TestCheckDKMSCoversEvdi(t *testing.T) {
	status := "evdi/1.15.1, 7.2.14-zen1-1-zen, x86_64: installed\nnvidia/580.196.07, 7.2.14-zen1-1-zen, x86_64: installed\nnvidia/580.196.07, 6.18.60-1-lts, x86_64: installed\n"
	got := CheckDKMS(status, []string{"7.2.14-zen1-1-zen", "6.18.60-1-lts"})
	if !slices.Equal(got, []string{"evdi/1.15.1 for 6.18.60-1-lts"}) {
		t.Errorf("got %q", got)
	}
}

func TestCheckDKMS(t *testing.T) {
	kernels := []string{"6.18.60-1-lts", "7.2.14-zen1-1-zen"}
	status := "nvidia/580.95.05, 7.2.14-zen1-1-zen, x86_64: installed\n" +
		"nvidia/580.95.05, 6.18.60-1-lts, x86_64: built\n" +
		"evdi/1.15.1: added\n" +
		"v4l2loopback/0.15, 7.2.14-zen1-1-zen, x86_64: installed\n" +
		"v4l2loopback/0.15, 6.18.60-1-lts, x86_64: installed (WARNING! Diff between built and installed module!)\n"
	got := CheckDKMS(status, kernels)
	want := []string{
		"evdi/1.15.1 for 6.18.60-1-lts", "evdi/1.15.1 for 7.2.14-zen1-1-zen",
		"nvidia/580.95.05 for 6.18.60-1-lts",
	}
	if !slices.Equal(got, want) {
		t.Errorf("CheckDKMS = %q, want %q", got, want)
	}
	if got := CheckDKMS("", kernels); len(got) != 0 {
		t.Errorf("empty status: %q", got)
	}
}

func TestDKMSStepAndReboot(t *testing.T) {
	f := &fake{
		tools: map[string]bool{"dkms": true},
		outputs: map[string]string{
			"dkms status": "nvidia/1, 7.2.14-zen1-1-zen, x86_64: installed\n",
			"uname -r":    "7.2.11-zen1-1-zen\n",
		},
	}
	u, _ := newUpdater(t, f, true)
	rep, err := u.Run(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(rep.DKMSProblems, []string{"nvidia/1 for 6.18.60-1-lts"}) {
		t.Errorf("DKMS = %q", rep.DKMSProblems)
	}
	if !rep.RebootNeeded || !strings.Contains(rep.Summary(), "Reboot needed") {
		t.Errorf("reboot = %v, summary %q", rep.RebootNeeded, rep.Summary())
	}
}

func TestInstalledKernelsSkipsUnpackaged(t *testing.T) {
	dir := modulesDir(t, "7.2.14-zen1-1-zen")
	if err := os.MkdirAll(filepath.Join(dir, "extramodules-old"), 0o755); err != nil {
		t.Fatal(err)
	}
	got, err := InstalledKernels(dir)
	if err != nil || !slices.Equal(got, []string{"7.2.14-zen1-1-zen"}) {
		t.Errorf("kernels = %q, %v", got, err)
	}
	if _, err := InstalledKernels(filepath.Join(dir, "missing")); err == nil {
		t.Error("want error for missing modules dir")
	}
}

func TestDryRunner(t *testing.T) {
	out := &bytes.Buffer{}
	d := DryRunner{Runner: &fake{}, Out: out}
	if err := d.Run(context.Background(), "sudo", "pacman", "-Syu"); err != nil {
		t.Fatal(err)
	}
	if out.String() != "would run: sudo pacman -Syu\n" {
		t.Errorf("out = %q", out)
	}
}

func TestPrivilegedSteps(t *testing.T) {
	steps := PrivilegedSteps("1.2.3")
	if got := strings.Join(steps["snapshot"], " "); !strings.HasSuffix(got, "--description subcult update 1.2.3") {
		t.Errorf("snapshot = %q", got)
	}
	for step, argv := range steps {
		if strings.HasPrefix(argv[0], "/") || argv[0] == "sudo" || argv[0] == "sh" || argv[0] == "bash" {
			t.Errorf("%s runs %q", step, argv[0])
		}
	}
}
