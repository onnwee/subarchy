package thermal

import (
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"

	"golang.org/x/sys/unix"
)

func u32b(v uint32) []byte {
	b := make([]byte, 4)
	binary.LittleEndian.PutUint32(b, v)
	return b
}

func concat(parts ...[]byte) []byte {
	var out []byte
	for _, p := range parts {
		out = append(out, p...)
	}
	return out
}

func sysfs(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	files := map[string]string{
		"class/thermal/thermal_zone0/type":              "SKIN\n",
		"class/thermal/thermal_zone0/temp":              "48050\n",
		"class/thermal/thermal_zone0/trip_point_0_type": "passive\n",
		"class/thermal/thermal_zone0/trip_point_0_temp": "-274000\n",
		"class/thermal/thermal_zone0/trip_point_1_type": "critical\n",
		"class/thermal/thermal_zone0/trip_point_1_temp": "87050\n",
		"class/thermal/thermal_zone0/trip_point_2_type": "hot\n",
		"class/thermal/thermal_zone0/trip_point_2_temp": "82050\n",
		"class/thermal/thermal_zone0/trip_point_2_hyst": "2000\n",
		"class/thermal/thermal_zone3/type":              "x86_pkg_temp\n",
		"class/thermal/thermal_zone3/temp":              "61000\n",
		"class/thermal/cooling_device0/type":            "Processor\n",
	}
	for p, c := range files {
		full := filepath.Join(root, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(c), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestZones(t *testing.T) {
	zones, err := Zones(sysfs(t))
	if err != nil {
		t.Fatal(err)
	}
	if len(zones) != 2 || zones[0].ID != 0 || zones[1].ID != 3 {
		t.Fatalf("zones: %+v", zones)
	}
	if zones[0].Type != "SKIN" || zones[0].Temp != 48050 || len(zones[0].Trips) != 3 {
		t.Errorf("zone 0: %+v", zones[0])
	}
	hot := zones[0].Trips[2]
	if hot.Kind != "hot" || hot.Temp != 82050 || hot.Hyst != 2000 {
		t.Errorf("hot trip: %+v", hot)
	}
	if zones[1].Type != "x86_pkg_temp" || len(zones[1].Trips) != 0 {
		t.Errorf("zone 3: %+v", zones[1])
	}
	if z, err := Zones(filepath.Join(t.TempDir(), "none")); err != nil || z != nil {
		t.Errorf("missing sysfs: %v %v", z, err)
	}
}

func TestParseEventAndResolve(t *testing.T) {
	root := sysfs(t)
	payload := concat(Attr(attrTZID, u32b(0)), Attr(attrTripID, u32b(2)), Attr(attrTZTemp, u32b(83000)))
	msg := GenlMessage(0x1f, 0, 7, eventTripUp, 2, payload)
	msgs, err := ParseMessages(msg)
	if err != nil || len(msgs) != 1 || msgs[0].Header.Type != 0x1f {
		t.Fatalf("messages: %+v %v", msgs, err)
	}
	e, ok, err := ParseEvent(msgs[0].Data)
	if err != nil || !ok {
		t.Fatalf("event: %v %v", ok, err)
	}
	e = Resolve(root, e)
	want := Event{Zone: 0, ZoneType: "SKIN", Trip: 2, Kind: "hot", TripTemp: 82050, Temp: 83000, Direction: "up"}
	if e != want {
		t.Errorf("got %+v, want %+v", e, want)
	}

	down := GenlMessage(0x1f, 0, 8, eventTripDown, 2, concat(Attr(attrTZID, u32b(3)), Attr(attrTripID, u32b(0))))
	e, ok, err = ParseEvent(down[unix.NLMSG_HDRLEN:])
	if err != nil || !ok || e.Direction != "down" || e.Zone != 3 || e.Temp != 0 {
		t.Errorf("down event: %+v %v %v", e, ok, err)
	}
	if e = Resolve(root, e); e.ZoneType != "x86_pkg_temp" || e.Kind != "" {
		t.Errorf("resolve without trips: %+v", e)
	}

	// Other thermal events (a cooling device state, a temperature sample) are not trips.
	other := GenlMessage(0x1f, 0, 9, 12, 2, Attr(attrTZID, u32b(0)))
	if _, ok, err := ParseEvent(other[unix.NLMSG_HDRLEN:]); ok || err != nil {
		t.Errorf("a non-trip event parsed as a trip: %v %v", ok, err)
	}
	// A trip event missing its ids is an error, not a zero event.
	bad := GenlMessage(0x1f, 0, 9, eventTripUp, 2, Attr(attrTZTemp, u32b(1)))
	if _, ok, err := ParseEvent(bad[unix.NLMSG_HDRLEN:]); ok || err == nil {
		t.Errorf("a trip without ids: %v %v", ok, err)
	}
}

func TestParseMessagesTruncated(t *testing.T) {
	msg := GenlMessage(0x1f, 0, 1, eventTripUp, 2, Attr(attrTZID, u32b(0)))
	if _, err := ParseMessages(msg[:len(msg)-2]); err == nil {
		t.Error("a truncated message parsed")
	}
	two := concat(msg, msg)
	if msgs, err := ParseMessages(two); err != nil || len(msgs) != 2 {
		t.Errorf("two messages: %d %v", len(msgs), err)
	}
	if _, err := ParseAttrs([]byte{1, 0, 0, 0}); err == nil {
		t.Error("an attribute shorter than its header parsed")
	}
}

func TestParseFamily(t *testing.T) {
	groups := concat(
		Attr(1|unix.NLA_F_NESTED, concat(Attr(unix.CTRL_ATTR_MCAST_GRP_NAME, []byte("sampling\x00")), Attr(unix.CTRL_ATTR_MCAST_GRP_ID, u32b(5)))),
		Attr(2|unix.NLA_F_NESTED, concat(Attr(unix.CTRL_ATTR_MCAST_GRP_NAME, []byte("event\x00")), Attr(unix.CTRL_ATTR_MCAST_GRP_ID, u32b(6)))),
	)
	id := make([]byte, 2)
	binary.LittleEndian.PutUint16(id, 0x1f)
	reply := GenlMessage(unix.GENL_ID_CTRL, 0, 1, 1, 2, concat(
		Attr(unix.CTRL_ATTR_FAMILY_NAME, []byte("thermal\x00")),
		Attr(unix.CTRL_ATTR_FAMILY_ID, id),
		Attr(unix.CTRL_ATTR_MCAST_GROUPS|unix.NLA_F_NESTED, groups)))
	f, err := ParseFamily(reply[unix.NLMSG_HDRLEN:])
	if err != nil {
		t.Fatal(err)
	}
	if f.ID != 0x1f || f.Groups["event"] != 6 || f.Groups["sampling"] != 5 {
		t.Errorf("family: %+v", f)
	}
	if _, err := ParseFamily(GenlMessage(unix.GENL_ID_CTRL, 0, 1, 1, 2, nil)[unix.NLMSG_HDRLEN:]); err == nil {
		t.Error("a reply without an id parsed")
	}
}

// The live kernel: the family resolves (or is absent, which is a clean
// error), nothing more. No event can be provoked safely.
func TestDialLive(t *testing.T) {
	c, err := Dial()
	if err != nil {
		t.Skipf("no netlink here: %v", err)
	}
	defer c.Close()
	if err := c.SetTimeout(2e9); err != nil {
		t.Fatal(err)
	}
	f, err := c.Subscribe()
	if err == ErrNoFamily {
		t.Skip("kernel without the thermal netlink family")
	}
	if err != nil {
		t.Skipf("thermal family lookup: %v", err)
	}
	if f.ID == 0 || f.Groups[EventGroup] == 0 {
		t.Errorf("family: %+v", f)
	}
}
