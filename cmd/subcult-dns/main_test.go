package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
)

// fakeRunner answers nmcli reads for one connection, "Home", and records the
// changes. It never touches the host.
type fakeRunner struct {
	runs    []string
	reads   int
	failRun string // a Run whose line starts with this fails once
}

func (r *fakeRunner) Run(_ context.Context, argv ...string) error {
	line := strings.Join(argv, " ")
	r.runs = append(r.runs, line)
	if r.failRun != "" && strings.HasPrefix(line, r.failRun) {
		r.failRun = ""
		return errors.New("failed")
	}
	return nil
}

func (r *fakeRunner) Output(_ context.Context, argv ...string) (string, error) {
	r.reads++
	switch {
	case argv[0] == "nmcli" && strings.Contains(strings.Join(argv, " "), "--active"):
		return "Home:802-3-ethernet\ntailscale0:tun\n", nil
	case argv[0] == "nmcli" && strings.Contains(strings.Join(argv, " "), "GENERAL.DEVICES"):
		return "eth0\n", nil
	case argv[0] == "nmcli" && strings.Contains(strings.Join(argv, " "), "connection.type"):
		return "802-3-ethernet\n", nil
	case argv[0] == "nmcli":
		return "no\nno\n\n\n-1\n\n\n", nil
	case strings.Join(argv, " ") == "resolvectl dns eth0":
		return "Link 2 (eth0):\n", nil
	}
	return "Global: 9.9.9.9#dns.quad9.net\n", nil
}

func (r *fakeRunner) Has(string) bool { return true }

func runDNS(r *fakeRunner, args ...string) (code int, stdout, stderr string) {
	var out, errb bytes.Buffer
	code = run(context.Background(), args, env{runner: r, stdout: &out, stderr: &errb})
	return code, out.String(), errb.String()
}

func TestMetadataListsBothRoutes(t *testing.T) {
	_, out, _ := runDNS(&fakeRunner{}, dispatch.MetadataFlag)
	var got []dispatch.Described
	if err := json.Unmarshal([]byte(out), &got); err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || strings.Join(got[0].Words, " ") != "dns" || strings.Join(got[1].Words, " ") != "dns set" {
		t.Errorf("routes = %+v", got)
	}
}

func TestApplyDefaultMakesANewConnectionUntrusted(t *testing.T) {
	r := &fakeRunner{}
	code, out, _ := runDNS(r, "apply-default", "u1", "eth0")
	want := []string{"nmcli connection modify u1 ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes", "nmcli device reapply eth0"}
	if code != 0 || !strings.Contains(out, "untrusted") || strings.Join(r.runs, "|") != strings.Join(want, "|") {
		t.Errorf("code %d, output %q, runs %q", code, out, r.runs)
	}
	if code, _, _ := runDNS(&fakeRunner{}, "apply-default", "u1"); code != 2 {
		t.Errorf("missing device: code %d, want 2", code)
	}
}

func TestStatus(t *testing.T) {
	r := &fakeRunner{}
	code, out, _ := runDNS(r)
	if code != 0 || !strings.Contains(out, "Home: not set") {
		t.Errorf("code %d, output %q", code, out)
	}
	if len(r.runs) != 0 {
		t.Errorf("status changed the system: %v", r.runs)
	}
}

func TestRefusals(t *testing.T) {
	tests := []struct {
		name string
		args []string
	}{
		{"unknown mode", []string{"set", "opportunistic"}},
		{"upper case mode", []string{"set", "Trusted"}},
		{"no mode", []string{"set"}},
		{"unknown command", []string{"reset"}},
		{"unknown flag", []string{"set", "trusted", "--nope"}},
		{"extra argument", []string{"set", "trusted", "Home"}},
		{"servers on untrusted", []string{"set", "untrusted", "--dns", "10.0.0.200"}},
		{"bad server", []string{"set", "trusted", "--dns", "dns.example"}},
		{"empty TLS name", []string{"set", "trusted", "--dns", "10.0.0.200#"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := &fakeRunner{}
			code, _, errb := runDNS(r, tt.args...)
			if code != 2 {
				t.Errorf("code = %d, want 2 (stderr %q)", code, errb)
			}
			if len(r.runs) != 0 || r.reads != 0 {
				t.Errorf("called the system before refusing: %d reads, runs %v", r.reads, r.runs)
			}
		})
	}
}

func TestSetUntrusted(t *testing.T) {
	r := &fakeRunner{}
	code, out, errb := runDNS(r, "set", "untrusted")
	if code != 0 {
		t.Fatalf("code %d: %s", code, errb)
	}
	if !strings.Contains(out, "untrusted for Home") {
		t.Errorf("output %q", out)
	}
	if len(r.runs) != 3 || !strings.HasPrefix(r.runs[2], "resolvectl query") {
		t.Errorf("calls: %v", r.runs)
	}
}

func TestSetFailureRestoresAndExitsOne(t *testing.T) {
	r := &fakeRunner{failRun: "resolvectl query"}
	code, _, errb := runDNS(r, "set", "untrusted", "--connection", "Home")
	if code != 1 {
		t.Errorf("code = %d, want 1", code)
	}
	if !strings.Contains(errb, "restored") {
		t.Errorf("stderr %q does not say the old settings are back", errb)
	}
	last := r.runs[len(r.runs)-2:]
	if !strings.HasPrefix(last[0], "nmcli connection modify Home ipv4.ignore-auto-dns no") || last[1] != "nmcli connection up Home" {
		t.Errorf("did not end by restoring: %v", r.runs)
	}
}

func TestSetTrustedChecksTheLink(t *testing.T) {
	r := &fakeRunner{}
	if code, _, errb := runDNS(r, "set", "trusted", "--dns", "10.0.2.3"); code != 0 {
		t.Fatalf("code %d: %s", code, errb)
	}
	want := []string{
		"nmcli connection modify Home ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes ipv4.dns 10.0.2.3 ipv6.dns  connection.dns-over-tls 0 ipv4.dns-search ~. ipv6.dns-search ~.",
		"nmcli connection up Home",
		"resolvectl query --cache=no -i eth0 dns.quad9.net",
	}
	if strings.Join(r.runs, "\n") != strings.Join(want, "\n") {
		t.Errorf("calls =\n%s\nwant\n%s", strings.Join(r.runs, "\n"), strings.Join(want, "\n"))
	}
}

func TestNoCheckSkipsLookup(t *testing.T) {
	r := &fakeRunner{}
	if code, _, errb := runDNS(r, "set", "trusted", "--no-check"); code != 0 {
		t.Fatalf("code %d: %s", code, errb)
	}
	for _, l := range r.runs {
		if strings.HasPrefix(l, "resolvectl") {
			t.Errorf("looked up a name with --no-check: %v", r.runs)
		}
	}
}
