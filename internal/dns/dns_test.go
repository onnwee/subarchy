package dns

import (
	"context"
	"errors"
	"slices"
	"strings"
	"testing"
)

// fake stands in for the system. Output answers read-only queries from
// answers (keyed by the joined argv); Run records every change and fails the
// ones whose line starts with a key of fail, once each, and every one that
// starts with a key of stuck. Nothing here touches the host.
type fake struct {
	answers map[string]string
	fail    map[string]error
	stuck   map[string]error
	runs    []string
}

func (f *fake) Run(_ context.Context, argv ...string) error {
	line := strings.Join(argv, " ")
	f.runs = append(f.runs, line)
	for prefix, err := range f.fail {
		if strings.HasPrefix(line, prefix) {
			delete(f.fail, prefix)
			return err
		}
	}
	for prefix, err := range f.stuck {
		if strings.HasPrefix(line, prefix) {
			return err
		}
	}
	return nil
}

func (f *fake) Output(_ context.Context, argv ...string) (string, error) {
	line := strings.Join(argv, " ")
	if out, ok := f.answers[line]; ok {
		return out, nil
	}
	return "", errors.New("unexpected query: " + line)
}

func (f *fake) Has(string) bool { return true }

const readHome = "nmcli -e no -g ipv4.ignore-auto-dns,ipv6.ignore-auto-dns,ipv4.dns,ipv6.dns,connection.dns-over-tls,ipv4.dns-search,ipv6.dns-search connection show Home"

// homeProfile is a profile that uses the network's DNS, as NetworkManager
// creates it.
const homeProfile = "no\nno\n\n\n-1\n\n\n"

// untrustedProfile is what `set untrusted` leaves.
const untrustedProfile = "yes\nyes\n\n\n-1\n\n\n"

// The reads the post-switch check makes for Home, whose device is wlan0.
const (
	devHome  = "nmcli -e no -g GENERAL.DEVICES connection show Home"
	dnsWlan0 = "resolvectl dns wlan0"
)

// checked returns a fake that knows Home's profile and device, with resolved
// listing linkDNS as wlan0's servers.
func checked(profile, linkDNS string) *fake {
	return &fake{answers: map[string]string{readHome: profile, devHome: "wlan0\n", dnsWlan0: "Link 3 (wlan0):" + linkDNS + "\n"}}
}

func TestParseMode(t *testing.T) {
	tests := []struct {
		in      string
		want    Mode
		invalid bool
	}{
		{"untrusted", Untrusted, false},
		{"trusted", Trusted, false},
		{"Trusted", "", true},
		{"", "", true},
		{"quad9", "", true},
		{"off", "", true},
	}
	for _, tt := range tests {
		t.Run(tt.in, func(t *testing.T) {
			got, err := ParseMode(tt.in)
			if tt.invalid {
				if !errors.Is(err, ErrInvalid) {
					t.Fatalf("ParseMode(%q) error = %v, want ErrInvalid", tt.in, err)
				}
				return
			}
			if err != nil || got != tt.want {
				t.Errorf("ParseMode(%q) = %q, %v; want %q", tt.in, got, err, tt.want)
			}
		})
	}
}

func TestParseServers(t *testing.T) {
	tests := []struct {
		name        string
		in          []string
		v4, v6      string
		tls         string
		wantInvalid bool
	}{
		{"none", nil, "", "", "0", false},
		{"plain LAN", []string{"10.0.0.200", "10.0.0.57"}, "10.0.0.200,10.0.0.57", "", "0", false},
		{"named", []string{"10.0.0.200#dns.home.example"}, "10.0.0.200#dns.home.example", "", "2", false},
		{"named v6", []string{"2620:fe::9#dns.quad9.net"}, "", "2620:fe::9#dns.quad9.net", "2", false},
		{"mixed names stay plaintext", []string{"10.0.0.200#dns.home.example", "10.0.0.57"}, "10.0.0.200#dns.home.example,10.0.0.57", "", "0", false},
		{"both families", []string{"10.0.0.200", "fd00::1"}, "10.0.0.200", "fd00::1", "0", false},
		{"not an address", []string{"dns.example"}, "", "", "", true},
		{"empty TLS name", []string{"10.0.0.200#"}, "", "", "", true},
		{"empty entry", []string{""}, "", "", "", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			v4, v6, tls, err := ParseServers(tt.in)
			if tt.wantInvalid {
				if !errors.Is(err, ErrInvalid) {
					t.Fatalf("error = %v, want ErrInvalid", err)
				}
				return
			}
			if err != nil || v4 != tt.v4 || v6 != tt.v6 || tls != tt.tls {
				t.Errorf("got %q, %q, %q, %v; want %q, %q, %q", v4, v6, tls, err, tt.v4, tt.v6, tt.tls)
			}
		})
	}
}

func TestModeOf(t *testing.T) {
	tests := []struct {
		name   string
		values string
		want   Mode
	}{
		{"untrusted", untrustedProfile, Untrusted},
		{"untrusted with a leftover search domain", "yes\nyes\n\n\n-1\nlan\n\n", Untrusted},
		{"never switched", homeProfile, Unset},
		{"never switched, DHCP search domain", "no\nno\n\n\n-1\nlan\n\n", Unset},
		{"network DNS, trusted", "no\nno\n\n\n0\n~.\n~.\n", Trusted},
		{"own servers, trusted", "yes\nyes\n10.0.0.200\n\n0\n~.\n~.\n", Trusted},
		{"~. among other domains", "no\nno\n\n\n0\nlan,~.\n\n", Trusted},
		{"own servers without ~.", "yes\nyes\n10.0.0.200\n\n0\n\n\n", Unset},
		{"only IPv4 ignored", "yes\nno\n\n\n-1\n\n\n", Unset},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p, err := parseProfile("Home", tt.values)
			if err != nil {
				t.Fatal(err)
			}
			if got := ModeOf(p); got != tt.want {
				t.Errorf("ModeOf = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestParseProfileRejectsShortOutput(t *testing.T) {
	if _, err := parseProfile("Home", "yes\nyes\n"); err == nil {
		t.Error("want an error when nmcli prints fewer values than were asked for")
	}
}

func TestSwitchUntrusted(t *testing.T) {
	// Undoing trust clears the link's "~." so the global servers answer;
	// the check then sees no link servers and a working lookup.
	f := checked("no\nno\n\n\n0\n~.\n~.\n", "")
	err := Switch(context.Background(), f, []string{"Home"}, Untrusted, nil, true)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		"nmcli connection modify Home ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes ipv4.dns  ipv6.dns  connection.dns-over-tls -1 ipv4.dns-search  ipv6.dns-search ",
		"nmcli connection up Home",
		"resolvectl query --cache=no dns.quad9.net",
	}
	if !slices.Equal(f.runs, want) {
		t.Errorf("calls =\n%s\nwant\n%s", strings.Join(f.runs, "\n"), strings.Join(want, "\n"))
	}
}

func TestSwitchUntrustedFailsWhileTheLinkKeepsServers(t *testing.T) {
	// If resolved still lists servers for the link, the network's DNS could
	// answer, so the switch is undone.
	f := checked(homeProfile, " 192.168.1.1")
	err := Switch(context.Background(), f, []string{"Home"}, Untrusted, nil, true)
	if err == nil || !strings.Contains(err.Error(), "still has DNS servers: 192.168.1.1") || !strings.Contains(err.Error(), "restored") {
		t.Fatalf("error = %v, want one naming the leftover server and the restore", err)
	}
	for _, r := range f.runs {
		if strings.HasPrefix(r, "resolvectl query") {
			t.Errorf("looked up a name although the link kept servers: %v", f.runs)
		}
	}
}

func TestSwitchTrustedWithServers(t *testing.T) {
	f := checked(untrustedProfile, " 10.0.0.200 10.0.0.57")
	err := Switch(context.Background(), f, []string{"Home"}, Trusted, []string{"10.0.0.200", "10.0.0.57"}, true)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		"nmcli connection modify Home ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes ipv4.dns 10.0.0.200,10.0.0.57 ipv6.dns  connection.dns-over-tls 0 ipv4.dns-search ~. ipv6.dns-search ~.",
		"nmcli connection up Home",
		// The lookup is restricted to the link, so only its servers answer.
		"resolvectl query --cache=no -i wlan0 dns.quad9.net",
	}
	if !slices.Equal(f.runs, want) {
		t.Errorf("calls =\n%s\nwant\n%s", strings.Join(f.runs, "\n"), strings.Join(want, "\n"))
	}
}

func TestSwitchTrustedNetworkDNS(t *testing.T) {
	// Without servers the network's own DNS is used, in plaintext: strict
	// DNS-over-TLS would fail against a router that does not listen on 853.
	f := &fake{answers: map[string]string{readHome: untrustedProfile}}
	if err := Switch(context.Background(), f, []string{"Home"}, Trusted, nil, false); err != nil {
		t.Fatal(err)
	}
	want := "nmcli connection modify Home ipv4.ignore-auto-dns no ipv6.ignore-auto-dns no ipv4.dns  ipv6.dns  connection.dns-over-tls 0 ipv4.dns-search ~. ipv6.dns-search ~."
	if f.runs[0] != want {
		t.Errorf("first call = %q, want %q", f.runs[0], want)
	}
}

func TestSwitchTrustedFailsWhenTheLinkDoesNotAnswer(t *testing.T) {
	f := checked(untrustedProfile, "")
	f.fail = map[string]error{"resolvectl query --cache=no -i wlan0": errors.New("no appropriate name servers")}
	err := Switch(context.Background(), f, []string{"Home"}, Trusted, []string{"10.0.0.200"}, true)
	if err == nil || !strings.Contains(err.Error(), "wlan0's own DNS servers") || !strings.Contains(err.Error(), "restored") {
		t.Fatalf("error = %v, want a failed link lookup and a restore", err)
	}
	last := f.runs[len(f.runs)-2]
	if last != "nmcli connection modify Home ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes ipv4.dns  ipv6.dns  connection.dns-over-tls -1 ipv4.dns-search  ipv6.dns-search " {
		t.Errorf("restore call = %q", last)
	}
}

func TestSwitchRejectsBadInputBeforeAnyCall(t *testing.T) {
	tests := []struct {
		name    string
		names   []string
		mode    Mode
		servers []string
	}{
		{"unknown mode", []string{"Home"}, Mode("opportunistic"), nil},
		{"empty mode", []string{"Home"}, Mode(""), nil},
		{"servers on untrusted", []string{"Home"}, Untrusted, []string{"10.0.0.200"}},
		{"bad server", []string{"Home"}, Trusted, []string{"nope"}},
		{"no connections", nil, Untrusted, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f := &fake{}
			err := Switch(context.Background(), f, tt.names, tt.mode, tt.servers, true)
			if !errors.Is(err, ErrInvalid) {
				t.Fatalf("error = %v, want ErrInvalid", err)
			}
			if len(f.runs) != 0 {
				t.Errorf("changed the system before refusing: %v", f.runs)
			}
		})
	}
}

func TestSwitchLeavesNothingChangedWhenReadFails(t *testing.T) {
	f := &fake{} // no answer for the read
	err := Switch(context.Background(), f, []string{"Home"}, Untrusted, nil, true)
	if err == nil {
		t.Fatal("want an error")
	}
	if len(f.runs) != 0 {
		t.Errorf("changed the system without a saved copy of the old settings: %v", f.runs)
	}
}

func TestSwitchRestoresOnFailure(t *testing.T) {
	restore := "nmcli connection modify Home ipv4.ignore-auto-dns no ipv6.ignore-auto-dns no ipv4.dns  ipv6.dns  connection.dns-over-tls -1 ipv4.dns-search  ipv6.dns-search "
	tests := []struct {
		name string
		fail map[string]error
		want []string
	}{
		{
			"lookup fails after the switch",
			map[string]error{"resolvectl query": errors.New("no answer")},
			[]string{"nmcli connection modify Home ipv4.ignore-auto-dns yes", "nmcli connection up Home", "resolvectl query", restore, "nmcli connection up Home"},
		},
		{
			"reactivation fails",
			map[string]error{"nmcli connection up Home": errors.New("activation failed")},
			[]string{"nmcli connection modify Home ipv4.ignore-auto-dns yes", "nmcli connection up Home", restore, "nmcli connection up Home"},
		},
		{
			"modify fails",
			map[string]error{"nmcli connection modify Home ipv4.ignore-auto-dns yes": errors.New("denied")},
			[]string{"nmcli connection modify Home ipv4.ignore-auto-dns yes", restore, "nmcli connection up Home"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f := checked(homeProfile, "")
			f.fail = tt.fail
			err := Switch(context.Background(), f, []string{"Home"}, Untrusted, nil, true)
			if err == nil || !strings.Contains(err.Error(), "restored") {
				t.Fatalf("error = %v, want one that says the old settings were restored", err)
			}
			if len(f.runs) != len(tt.want) {
				t.Fatalf("calls =\n%s\nwant %d calls starting\n%s", strings.Join(f.runs, "\n"), len(tt.want), strings.Join(tt.want, "\n"))
			}
			for i, w := range tt.want {
				if !strings.HasPrefix(f.runs[i], w) {
					t.Errorf("call %d = %q, want prefix %q", i, f.runs[i], w)
				}
			}
		})
	}
}

func TestSwitchReportsWhenRestoreFailsToo(t *testing.T) {
	f := checked(homeProfile, "")
	f.fail = map[string]error{"resolvectl query": errors.New("no answer")}
	f.stuck = map[string]error{"nmcli connection up Home": errors.New("link down")}
	err := Switch(context.Background(), f, []string{"Home"}, Untrusted, nil, true)
	if err == nil || !strings.Contains(err.Error(), "could not restore") {
		t.Fatalf("error = %v, want one that says the restore failed", err)
	}
}

func TestSwitchRestoresEveryConnection(t *testing.T) {
	readWork := strings.Replace(readHome, "Home", "Work", 1)
	f := &fake{
		answers: map[string]string{readHome: homeProfile, readWork: "no\nno\n10.1.0.1\n\n0\n~.\n~.\n"},
		fail:    map[string]error{"nmcli connection up Work": errors.New("activation failed")},
	}
	err := Switch(context.Background(), f, []string{"Home", "Work"}, Untrusted, nil, false)
	if err == nil {
		t.Fatal("want an error")
	}
	var restoredHome, restoredWork bool
	for _, r := range f.runs {
		restoredHome = restoredHome || strings.HasPrefix(r, "nmcli connection modify Home ipv4.ignore-auto-dns no")
		restoredWork = restoredWork || r == "nmcli connection modify Work ipv4.ignore-auto-dns no ipv6.ignore-auto-dns no ipv4.dns 10.1.0.1 ipv6.dns  connection.dns-over-tls 0 ipv4.dns-search ~. ipv6.dns-search ~."
	}
	if !restoredHome || !restoredWork {
		t.Errorf("both connections should be restored; calls:\n%s", strings.Join(f.runs, "\n"))
	}
}

func TestActiveConnections(t *testing.T) {
	out := "Debian: LAN:802-3-ethernet\ntailscale0:tun\nCafe WiFi:802-11-wireless\nbr0:bridge\nlo:loopback\nVPN:wireguard\n"
	f := &fake{answers: map[string]string{"nmcli -t -e no -f NAME,TYPE connection show --active": out}}
	got, err := Active(context.Background(), f)
	if err != nil {
		t.Fatal(err)
	}
	// Escaping is off, so a colon in a name stays; only the last one splits.
	want := []string{"Debian: LAN", "Cafe WiFi"}
	if !slices.Equal(got, want) {
		t.Errorf("Active = %q, want %q", got, want)
	}
}

func TestStatusNamesTheModeOfEachConnection(t *testing.T) {
	f := &fake{answers: map[string]string{
		"nmcli -t -e no -f NAME,TYPE connection show --active": "Home:802-3-ethernet\nCafe:802-11-wireless\nNew:802-11-wireless\n",
		readHome: "no\nno\n\n\n0\n~.\n~.\n",
		strings.Replace(readHome, "Home", "Cafe", 1): untrustedProfile,
		strings.Replace(readHome, "Home", "New", 1):  homeProfile,
		"resolvectl dns": "Global: 9.9.9.9#dns.quad9.net\n",
	}}
	got, err := Status(context.Background(), f)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"Home: trusted (network DNS)", "Cafe: untrusted", "New: not set", "9.9.9.9#dns.quad9.net"} {
		if !strings.Contains(got, want) {
			t.Errorf("status lacks %q:\n%s", want, got)
		}
	}
}
