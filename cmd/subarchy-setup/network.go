package main

// The network page: with no wired or Wi-Fi link up, the installer lists
// the Wi-Fi networks the live image's iwd sees and joins one, or the user
// skips it and installs offline. Whatever Wi-Fi network the live session
// is on when the questions end, joined here or by hand with iwctl, goes to
// the installed system as a NetworkManager connection (ADR 0016, 0049).
//
// iwd is read over D-Bus through busctl's JSON output rather than from
// iwctl's table, which wraps long names and colours its signal bars.
// iwctl only joins a network, because it answers iwd's passphrase request.

import (
	"bufio"
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/setup"
)

// wifiNetwork is one network iwd can see.
type wifiNetwork struct {
	path      string // iwd's D-Bus object for it
	name      string // the SSID
	security  string // iwd's type: open, psk, 8021x or wep
	signal    int    // in hundredths of a dBm
	connected bool
}

// supported reports whether the installer can join the network and carry
// it over: an open or passphrase network, not 802.1X or WEP.
func (n wifiNetwork) supported() bool { return n.security == "open" || n.security == "psk" }

// row is the network's line in the pick list.
func (n wifiNetwork) row() string {
	kind := map[string]string{"open": "open", "psk": "password", "8021x": "802.1X", "wep": "WEP"}[n.security]
	if kind == "" {
		kind = n.security
	}
	name := n.name
	// Space at either end would vanish in the padded column, so two networks
	// differing only there would get the same row; quote such a name.
	if strings.TrimSpace(name) != name {
		name = strconv.Quote(name)
	}
	return fmt.Sprintf("%-32s  %-8s  %s", name, kind, strength(n.signal))
}

// strength puts a signal in words, at iwctl's thresholds for its bars.
func strength(signal int) string {
	switch {
	case signal >= -6000:
		return "strong"
	case signal >= -6700:
		return "good"
	case signal >= -7500:
		return "fair"
	}
	return "weak"
}

// wifi is the live image's Wi-Fi, through iwd.
type wifi struct {
	// busctl runs busctl with these arguments and returns what it printed.
	busctl func(args ...string) ([]byte, error)
	// join connects the device to a network with iwctl; passphrase is
	// empty for an open network.
	join func(device, name, security, passphrase string) error
	// online reports whether a link other than lo has a default route.
	online func() bool
	// dir is iwd's state directory, where it keeps a joined network's key.
	dir string
	// sleep waits between checks; a no-op in tests.
	sleep func(time.Duration)
	// typed holds the passphrase typed here for each network joined.
	typed map[string]string
}

// variant is a D-Bus variant in busctl's JSON.
type variant struct {
	Type string          `json:"type"`
	Data json.RawMessage `json:"data"`
}

type iwdObjects map[string]map[string]map[string]variant

const iwdService = "net.connman.iwd"

func (w *wifi) objects() (iwdObjects, error) {
	out, err := w.busctl("--json=short", "call", iwdService, "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects")
	if err != nil {
		return nil, err
	}
	var reply struct {
		Data []iwdObjects `json:"data"`
	}
	if err := json.Unmarshal(out, &reply); err != nil || len(reply.Data) != 1 {
		return nil, fmt.Errorf("iwd's objects: unexpected reply")
	}
	return reply.Data[0], nil
}

func str(props map[string]variant, key string) string {
	var s string
	json.Unmarshal(props[key].Data, &s)
	return s
}

func boolean(props map[string]variant, key string) bool {
	var b bool
	json.Unmarshal(props[key].Data, &b)
	return b
}

// station returns the first Wi-Fi device in station mode: its D-Bus object
// and its interface name.
func (w *wifi) station(objs iwdObjects) (path, device string) {
	for p, ifaces := range objs {
		dev, isDev := ifaces[iwdService+".Device"]
		_, isStation := ifaces[iwdService+".Station"]
		if isDev && isStation && (path == "" || p < path) {
			path, device = p, str(dev, "Name")
		}
	}
	return path, device
}

func network(objs iwdObjects, path string) (wifiNetwork, bool) {
	props, ok := objs[path][iwdService+".Network"]
	if !ok {
		return wifiNetwork{}, false
	}
	return wifiNetwork{path: path, name: str(props, "Name"), security: str(props, "Type"), connected: boolean(props, "Connected")}, true
}

// needed reports whether to show the network page: no link is up and
// there is a Wi-Fi device to join a network with.
func (w *wifi) needed() bool {
	if w == nil || w.online() {
		return false
	}
	objs, err := w.objects()
	if err != nil {
		return false
	}
	path, _ := w.station(objs)
	return path != ""
}

// scan asks iwd for a fresh scan, waits up to ten seconds for it, and
// returns the networks strongest first.
func (w *wifi) scan() ([]wifiNetwork, error) {
	objs, err := w.objects()
	if err != nil {
		return nil, err
	}
	path, _ := w.station(objs)
	if path == "" {
		return nil, errors.New("no Wi-Fi device")
	}
	// Busy while a scan already runs, which is as good.
	w.busctl("call", iwdService, path, iwdService+".Station", "Scan")
	for i := 0; i < 20; i++ {
		w.sleep(500 * time.Millisecond)
		if objs, err = w.objects(); err != nil {
			return nil, err
		}
		if !boolean(objs[path][iwdService+".Station"], "Scanning") {
			break
		}
	}
	out, err := w.busctl("--json=short", "call", iwdService, path, iwdService+".Station", "GetOrderedNetworks")
	if err != nil {
		return nil, err
	}
	var reply struct {
		Data [][][]json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(out, &reply); err != nil || len(reply.Data) != 1 {
		return nil, errors.New("iwd's networks: unexpected reply")
	}
	var nets []wifiNetwork
	for _, pair := range reply.Data[0] {
		var p string
		var signal int
		if len(pair) != 2 || json.Unmarshal(pair[0], &p) != nil || json.Unmarshal(pair[1], &signal) != nil {
			continue
		}
		// Any access point nearby picks its name; one with control
		// characters could drive the console, so it is not listed.
		if n, ok := network(objs, p); ok && setup.ValidSSID(n.name) {
			n.signal = signal
			nets = append(nets, n)
		}
	}
	return nets, nil
}

// connect joins a network and waits up to twenty seconds for an address.
// up is false when it joined but got no address in that time.
func (w *wifi) connect(n wifiNetwork, passphrase string) (up bool, err error) {
	objs, err := w.objects()
	if err != nil {
		return false, err
	}
	_, device := w.station(objs)
	if err := w.join(device, n.name, n.security, passphrase); err != nil {
		return false, err
	}
	if passphrase != "" {
		w.typed[n.name] = passphrase
	}
	for i := 0; i < 40; i++ {
		if w.online() {
			return true, nil
		}
		w.sleep(500 * time.Millisecond)
	}
	return false, nil
}

// current is the network the Wi-Fi device is on now, if any.
func (w *wifi) current() (wifiNetwork, bool) {
	objs, err := w.objects()
	if err != nil {
		return wifiNetwork{}, false
	}
	path, _ := w.station(objs)
	var connected string
	json.Unmarshal(objs[path][iwdService+".Station"]["ConnectedNetwork"].Data, &connected)
	return network(objs, connected)
}

// iwdFile is the name iwd stores a network under: the SSID when it holds
// only letters, digits, spaces, - and _, else = and the SSID in hex.
func iwdFile(ssid, security string) string {
	for _, c := range []byte(ssid) {
		if !('a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' || '0' <= c && c <= '9' || c == ' ' || c == '-' || c == '_') {
			return "=" + hex.EncodeToString([]byte(ssid)) + "." + security
		}
	}
	return ssid + "." + security
}

// secret is a passphrase network's key: the passphrase typed here, or
// what iwd saved when it joined (its Passphrase, else its 64-digit
// PreSharedKey; NetworkManager takes either).
func (w *wifi) secret(n wifiNetwork) (string, error) {
	if p, ok := w.typed[n.name]; ok {
		return p, nil
	}
	f, err := os.Open(filepath.Join(w.dir, iwdFile(n.name, n.security)))
	if err != nil {
		return "", err
	}
	defer f.Close()
	keys := map[string]string{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		// As ell reads it: blanks after the = are dropped, and the rest of
		// the line is the value, escaped.
		if k, v, ok := strings.Cut(sc.Text(), "="); ok {
			keys[strings.TrimSpace(k)] = unescapeSetting(strings.TrimLeft(v, " \t"))
		}
	}
	for _, k := range []string{"Passphrase", "PreSharedKey"} {
		if setup.ValidWiFiPassphrase(keys[k]) == nil {
			return keys[k], nil
		}
	}
	return "", errors.New("no key in iwd's file")
}

// unescapeSetting undoes ell's escapes in a settings value: \s, \t, \n,
// \r and \\. A value with any other escape is not one iwd wrote; it
// comes back empty.
func unescapeSetting(v string) string {
	var b strings.Builder
	for i := 0; i < len(v); i++ {
		if v[i] != '\\' {
			b.WriteByte(v[i])
			continue
		}
		if i++; i == len(v) {
			return ""
		}
		c, ok := map[byte]byte{'s': ' ', 't': '\t', 'n': '\n', 'r': '\r', '\\': '\\'}[v[i]]
		if !ok {
			return ""
		}
		b.WriteByte(c)
	}
	return b.String()
}

// carryWiFi puts the Wi-Fi network the live session is on into the
// answers, so the installed system joins it too. It returns why a network
// is not carried over, or "" when it is or there is none.
func carryWiFi(a *setup.Answers, w *wifi) string {
	a.WiFiSSID, a.WiFiPSK = "", ""
	if w == nil {
		return ""
	}
	n, ok := w.current()
	if !ok {
		return ""
	}
	if !setup.ValidSSID(n.name) {
		// Not printed: the name may hold control characters.
		return "The installed system will not join this Wi-Fi network by itself; join it from the network menu."
	}
	if !n.supported() {
		return fmt.Sprintf("The installed system will not join %s by itself; join it from the network menu.", n.name)
	}
	if n.security == "psk" {
		psk, err := w.secret(n)
		if err != nil {
			return fmt.Sprintf("The key for %s was not found; join it again from the network menu after the install.", n.name)
		}
		a.WiFiPSK = psk
	}
	a.WiFiSSID = n.name
	return ""
}

// The network page's text, shared by the screens and the plain prompts.
const (
	networkTitle = "Let's get you online."
	networkSkip  = "Skip, install offline"
	networkScan  = "Look for networks again"
)

var networkBody = []string{
	"No wired or Wi-Fi connection is up. Pick a Wi-Fi network to join, or skip:",
	"everything the install needs is on this medium. The installed system joins",
	"the network you pick here.",
}

// validTyped checks a passphrase typed on the page. The 64-digit key,
// which NetworkManager also takes, is refused here: iwd joins only with
// the passphrase itself.
func validTyped(passphrase string) error {
	if len(passphrase) > 63 {
		return errors.New("a Wi-Fi passphrase has 8 to 63 characters")
	}
	return setup.ValidWiFiPassphrase(passphrase)
}

// unsupported is why the installer will not join a network.
func unsupported(n wifiNetwork) string {
	if n.security == "8021x" {
		return n.name + " needs an 802.1X sign-in, which the installer cannot do. Join it after the install."
	}
	return n.name + " uses WEP, which Subarchy does not support."
}

// networkRows gives each network its own line in the pick list. A row already
// taken (two networks with the same name, security and strength) gets a
// number, so choosing a row always means one network.
func networkRows(nets []wifiNetwork) ([]string, map[string]wifiNetwork) {
	rows := []string{}
	byRow := map[string]wifiNetwork{}
	for _, n := range nets {
		r := n.row()
		for i := 2; ; i++ {
			if _, taken := byRow[r]; !taken {
				break
			}
			r = fmt.Sprintf("%s  (%d)", n.row(), i)
		}
		rows = append(rows, r)
		byRow[r] = n
	}
	return rows, byRow
}

// network is the screens' network page. It returns errSkip when there is
// nothing to ask: a link is up, or there is no Wi-Fi device.
func (s *screens) network(w *wifi) error {
	if !w.needed() {
		return errSkip
	}
	body := func(extra ...string) []string { return append(append([]string{}, networkBody...), extra...) }
	selected := ""
	for {
		s.page(networkTitle, body("", "Looking for Wi-Fi networks...")...)
		nets, err := w.scan()
		if err != nil {
			s.notice("Could not look for networks: " + err.Error())
		}
		rows, byRow := networkRows(nets)
		if len(nets) == 0 {
			s.page(networkTitle, body("", "No Wi-Fi networks were found.")...)
		} else {
			s.page(networkTitle, body()...)
		}
		row, err := s.choose("Wi-Fi network", append(rows, networkScan, networkSkip), selected)
		if err != nil {
			return err
		}
		selected = row
		switch row {
		case networkSkip:
			return nil
		case networkScan:
			continue
		}
		n := byRow[row]
		if !n.supported() {
			s.notice(unsupported(n))
			continue
		}
		passphrase := ""
		if n.security == "psk" {
			for {
				s.page("Joining "+n.name+".", "Escape goes back to the list.")
				if passphrase, err = s.input("Passphrase", "The network's password", "", true); err != nil {
					break
				}
				if err = validTyped(passphrase); err != nil {
					s.notice(capital(err.Error()))
					continue
				}
				break
			}
			if err != nil {
				continue
			}
		}
		s.page("Joining " + n.name + "...")
		up, err := w.connect(n, passphrase)
		if err != nil {
			s.notice("Could not join " + n.name + ". Check the passphrase and try again.")
			continue
		}
		if !up {
			s.notice("Joined " + n.name + ", but it has not given this computer an address yet.")
		}
		return nil
	}
}

// network is the plain prompts' network question.
func (p *prompter) network(w *wifi) error {
	if !w.needed() {
		return nil
	}
	fmt.Fprintln(p.out, "\n"+networkTitle)
	for _, l := range networkBody {
		fmt.Fprintln(p.out, l)
	}
	for {
		fmt.Fprintln(p.out, "\nLooking for Wi-Fi networks...")
		nets, err := w.scan()
		if err != nil {
			fmt.Fprintf(p.out, "  could not look for networks: %v\n", err)
		}
		for i, n := range nets {
			fmt.Fprintf(p.out, "  %d) %s\n", i+1, n.row())
		}
		if len(nets) == 0 {
			fmt.Fprintln(p.out, "  No Wi-Fi networks were found.")
		}
		var n wifiNetwork
		answer, err := p.ask("Network number (r to look again, s to install offline)", "s", func(s string) error {
			if s == "r" || s == "s" {
				return nil
			}
			i, err := strconv.Atoi(s)
			if err != nil || i < 1 || i > len(nets) {
				return errors.New("enter a network number, r or s")
			}
			n = nets[i-1]
			return nil
		})
		if err != nil {
			return err
		}
		switch answer {
		case "s":
			return nil
		case "r":
			continue
		}
		if !n.supported() {
			fmt.Fprintln(p.out, "  "+unsupported(n))
			continue
		}
		passphrase := ""
		if n.security == "psk" {
			fmt.Fprintf(p.out, "Passphrase for %s: ", n.name)
			passphrase, err = p.secret()
			fmt.Fprintln(p.out)
			if err != nil {
				return err
			}
			if err := validTyped(passphrase); err != nil {
				fmt.Fprintf(p.out, "  %v\n", err)
				continue
			}
		}
		fmt.Fprintf(p.out, "Joining %s...\n", n.name)
		up, err := w.connect(n, passphrase)
		if err != nil {
			fmt.Fprintf(p.out, "  could not join %s; check the passphrase and try again\n", n.name)
			continue
		}
		if !up {
			fmt.Fprintf(p.out, "  joined %s, but it has not given this computer an address yet\n", n.name)
		}
		return nil
	}
}

// hasDefaultRoute reports whether the IPv4 or IPv6 routing table, in
// /proc/net/route and /proc/net/ipv6_route form, has a default route on a
// link other than lo.
func hasDefaultRoute(route, ipv6Route string) bool {
	if data, err := os.ReadFile(route); err == nil {
		for _, line := range strings.Split(string(data), "\n")[1:] {
			f := strings.Fields(line)
			// Iface Destination Gateway Flags ... Mask; flag 1 is up.
			if len(f) >= 8 && f[0] != "lo" && f[1] == "00000000" && f[7] == "00000000" {
				if flags, err := strconv.ParseUint(f[3], 16, 32); err == nil && flags&1 != 0 {
					return true
				}
			}
		}
	}
	if data, err := os.ReadFile(ipv6Route); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			f := strings.Fields(line)
			// dest destlen src srclen nexthop metric refcnt use flags iface;
			// flag 0x200 is a reject route, such as the kernel's own on lo.
			if len(f) == 10 && f[9] != "lo" && strings.Trim(f[0], "0") == "" && f[1] == "00" {
				if flags, err := strconv.ParseUint(f[8], 16, 32); err == nil && flags&0x200 == 0 {
					return true
				}
			}
		}
	}
	return false
}

// iwctlArgs is iwctl's command line to join a network. The passphrase is
// on it, so it shows in /proc/<pid>/cmdline while iwctl runs; iwctl takes
// it no other way without a prompt of its own. The live session runs
// nothing else that could read it.
func iwctlArgs(device, name, security, passphrase string) []string {
	var args []string
	if passphrase != "" {
		args = append(args, "--passphrase", passphrase)
	}
	// iwctl reads options with GNU getopt, which looks for them among all
	// the arguments; after "--" a name such as "-=Free WiFi=-" is not one.
	return append(args, "--", "station", device, "connect", name, security)
}

func realWiFi() *wifi {
	return &wifi{
		busctl: func(args ...string) ([]byte, error) {
			return exec.Command("busctl", args...).Output()
		},
		join: func(device, name, security, passphrase string) error {
			ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
			defer cancel()
			// iwctl's own messages are not shown or logged.
			return exec.CommandContext(ctx, "iwctl", iwctlArgs(device, name, security, passphrase)...).Run()
		},
		online: func() bool { return hasDefaultRoute("/proc/net/route", "/proc/net/ipv6_route") },
		dir:    "/var/lib/iwd",
		sleep:  time.Sleep,
		typed:  map[string]string{},
	}
}
