// Package thermal reads the kernel's thermal zones and listens for their
// trip-point events (rice port: thermal alerts, issue #98; ADR 0054).
//
// The kernel reports a trip point crossed over the "thermal" generic
// netlink family (THERMAL_GENL_EVENT_TZ_TRIP_UP and _DOWN); sysfs has no
// inotify for temperatures, so this is the one event source that needs no
// polling. The events name the zone and trip by id; their type and
// threshold come from /sys/class/thermal.
package thermal

import (
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

// From include/uapi/linux/thermal.h.
const (
	FamilyName = "thermal"
	EventGroup = "event"

	attrTZID   = 2 // THERMAL_GENL_ATTR_TZ_ID
	attrTZTemp = 3 // THERMAL_GENL_ATTR_TZ_TEMP
	attrTripID = 5 // THERMAL_GENL_ATTR_TZ_TRIP_ID

	eventTripUp   = 5 // THERMAL_GENL_EVENT_TZ_TRIP_UP
	eventTripDown = 6 // THERMAL_GENL_EVENT_TZ_TRIP_DOWN
)

// ErrNoFamily: the running kernel has no thermal netlink family (CONFIG_THERMAL_NETLINK off).
var ErrNoFamily = errors.New("no thermal netlink family on this kernel")

// Event is one trip point crossed, as the shell reads it: one JSON object
// per line. Temperatures are millidegrees Celsius.
type Event struct {
	Zone      int    `json:"zone"`
	ZoneType  string `json:"type"`
	Trip      int    `json:"trip"`
	Kind      string `json:"kind"` // hot, critical, passive, active; "" when sysfs has no such trip
	TripTemp  int    `json:"tripTemp"`
	Temp      int    `json:"temp"`
	Direction string `json:"direction"` // up or down
}

// Trip is one trip point of a zone.
type Trip struct {
	ID   int    `json:"id"`
	Kind string `json:"kind"`
	Temp int    `json:"temp"`
	Hyst int    `json:"hyst"`
}

// Zone is one thermal zone with its trips.
type Zone struct {
	ID    int    `json:"id"`
	Type  string `json:"type"`
	Temp  int    `json:"temp"`
	Trips []Trip `json:"trips"`
}

// Zones reads every thermal zone under root/class/thermal.
func Zones(root string) ([]Zone, error) {
	dir := filepath.Join(root, "class", "thermal")
	entries, err := os.ReadDir(dir)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}
	var zones []Zone
	for _, e := range entries {
		id, ok := strings.CutPrefix(e.Name(), "thermal_zone")
		if !ok {
			continue
		}
		n, err := strconv.Atoi(id)
		if err != nil {
			continue
		}
		z := Zone{ID: n, Type: readString(filepath.Join(dir, e.Name(), "type")), Temp: readInt(filepath.Join(dir, e.Name(), "temp"))}
		for i := 0; ; i++ {
			kind := readString(filepath.Join(dir, e.Name(), fmt.Sprintf("trip_point_%d_type", i)))
			if kind == "" {
				break
			}
			z.Trips = append(z.Trips, Trip{ID: i, Kind: kind,
				Temp: readInt(filepath.Join(dir, e.Name(), fmt.Sprintf("trip_point_%d_temp", i))),
				Hyst: readInt(filepath.Join(dir, e.Name(), fmt.Sprintf("trip_point_%d_hyst", i)))})
		}
		zones = append(zones, z)
	}
	sort.Slice(zones, func(i, j int) bool { return zones[i].ID < zones[j].ID })
	return zones, nil
}

// Resolve fills the zone type and the trip's kind and threshold from sysfs.
func Resolve(root string, e Event) Event {
	dir := filepath.Join(root, "class", "thermal", fmt.Sprintf("thermal_zone%d", e.Zone))
	e.ZoneType = readString(filepath.Join(dir, "type"))
	e.Kind = readString(filepath.Join(dir, fmt.Sprintf("trip_point_%d_type", e.Trip)))
	e.TripTemp = readInt(filepath.Join(dir, fmt.Sprintf("trip_point_%d_temp", e.Trip)))
	return e
}

func readString(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func readInt(path string) int {
	n, err := strconv.Atoi(readString(path))
	if err != nil {
		return 0
	}
	return n
}

// Message is one netlink message: its header and payload.
type Message struct {
	Header unix.NlMsghdr
	Data   []byte
}

func align4(n int) int { return (n + 3) &^ 3 }

// ParseMessages splits a received buffer into netlink messages.
func ParseMessages(b []byte) ([]Message, error) {
	var out []Message
	for len(b) >= unix.NLMSG_HDRLEN {
		h := unix.NlMsghdr{
			Len:   binary.LittleEndian.Uint32(b[0:4]),
			Type:  binary.LittleEndian.Uint16(b[4:6]),
			Flags: binary.LittleEndian.Uint16(b[6:8]),
			Seq:   binary.LittleEndian.Uint32(b[8:12]),
			Pid:   binary.LittleEndian.Uint32(b[12:16]),
		}
		l := int(h.Len)
		if l < unix.NLMSG_HDRLEN || l > len(b) {
			return out, fmt.Errorf("netlink message length %d out of %d bytes", l, len(b))
		}
		out = append(out, Message{Header: h, Data: b[unix.NLMSG_HDRLEN:l]})
		b = b[min(align4(l), len(b)):]
	}
	return out, nil
}

// ParseAttrs reads a run of netlink attributes into a map by type (the
// nested flag stripped). A later attribute of the same type wins.
func ParseAttrs(b []byte) (map[uint16][]byte, error) {
	out := map[uint16][]byte{}
	for len(b) >= unix.NLA_HDRLEN {
		l := int(binary.LittleEndian.Uint16(b[0:2]))
		t := binary.LittleEndian.Uint16(b[2:4]) &^ unix.NLA_F_NESTED
		if l < unix.NLA_HDRLEN || l > len(b) {
			return out, fmt.Errorf("attribute length %d out of %d bytes", l, len(b))
		}
		out[t] = b[unix.NLA_HDRLEN:l]
		b = b[min(align4(l), len(b)):]
	}
	return out, nil
}

// ParseEvent reads a thermal family message. ok is false for anything but a
// trip crossing.
func ParseEvent(data []byte) (e Event, ok bool, err error) {
	if len(data) < unix.GENL_HDRLEN {
		return e, false, errors.New("short generic netlink header")
	}
	cmd := data[0]
	switch cmd {
	case eventTripUp:
		e.Direction = "up"
	case eventTripDown:
		e.Direction = "down"
	default:
		return e, false, nil
	}
	attrs, err := ParseAttrs(data[unix.GENL_HDRLEN:])
	if err != nil {
		return e, false, err
	}
	zone, ok1 := u32(attrs[attrTZID])
	trip, ok2 := u32(attrs[attrTripID])
	if !ok1 || !ok2 {
		return e, false, errors.New("trip event without zone or trip id")
	}
	e.Zone, e.Trip = int(zone), int(trip)
	if t, ok := u32(attrs[attrTZTemp]); ok {
		e.Temp = int(int32(t))
	}
	return e, true, nil
}

func u32(b []byte) (uint32, bool) {
	if len(b) < 4 {
		return 0, false
	}
	return binary.LittleEndian.Uint32(b[:4]), true
}

// Attr builds one netlink attribute (tests and the family request).
func Attr(typ uint16, payload []byte) []byte {
	l := unix.NLA_HDRLEN + len(payload)
	b := make([]byte, align4(l))
	binary.LittleEndian.PutUint16(b[0:2], uint16(l))
	binary.LittleEndian.PutUint16(b[2:4], typ)
	copy(b[unix.NLA_HDRLEN:], payload)
	return b
}

// GenlMessage builds a netlink message carrying a generic netlink header.
func GenlMessage(family uint16, flags uint16, seq uint32, cmd, version uint8, attrs []byte) []byte {
	l := unix.NLMSG_HDRLEN + unix.GENL_HDRLEN + len(attrs)
	b := make([]byte, align4(l))
	binary.LittleEndian.PutUint32(b[0:4], uint32(l))
	binary.LittleEndian.PutUint16(b[4:6], family)
	binary.LittleEndian.PutUint16(b[6:8], flags)
	binary.LittleEndian.PutUint32(b[8:12], seq)
	b[unix.NLMSG_HDRLEN] = cmd
	b[unix.NLMSG_HDRLEN+1] = version
	copy(b[unix.NLMSG_HDRLEN+unix.GENL_HDRLEN:], attrs)
	return b
}

// Family is a generic netlink family's id and multicast groups.
type Family struct {
	ID     uint16
	Groups map[string]uint32
}

// ParseFamily reads a CTRL_CMD_GETFAMILY reply.
func ParseFamily(data []byte) (Family, error) {
	f := Family{Groups: map[string]uint32{}}
	if len(data) < unix.GENL_HDRLEN {
		return f, errors.New("short family reply")
	}
	attrs, err := ParseAttrs(data[unix.GENL_HDRLEN:])
	if err != nil {
		return f, err
	}
	id := attrs[unix.CTRL_ATTR_FAMILY_ID]
	if len(id) < 2 {
		return f, errors.New("family reply without an id")
	}
	f.ID = binary.LittleEndian.Uint16(id[:2])
	groups, err := ParseAttrs(attrs[unix.CTRL_ATTR_MCAST_GROUPS])
	if err != nil {
		return f, err
	}
	for _, g := range groups {
		fields, err := ParseAttrs(g)
		if err != nil {
			return f, err
		}
		name := strings.TrimRight(string(fields[unix.CTRL_ATTR_MCAST_GRP_NAME]), "\x00")
		if gid, ok := u32(fields[unix.CTRL_ATTR_MCAST_GRP_ID]); ok && name != "" {
			f.Groups[name] = gid
		}
	}
	return f, nil
}

// Conn is a generic netlink socket.
type Conn struct {
	fd  int
	seq uint32
}

// Dial opens and binds a generic netlink socket.
func Dial() (*Conn, error) {
	fd, err := unix.Socket(unix.AF_NETLINK, unix.SOCK_RAW|unix.SOCK_CLOEXEC, unix.NETLINK_GENERIC)
	if err != nil {
		return nil, fmt.Errorf("netlink socket: %w", err)
	}
	if err := unix.Bind(fd, &unix.SockaddrNetlink{Family: unix.AF_NETLINK}); err != nil {
		unix.Close(fd)
		return nil, fmt.Errorf("netlink bind: %w", err)
	}
	return &Conn{fd: fd}, nil
}

// Close closes the socket.
func (c *Conn) Close() error { return unix.Close(c.fd) }

// SetTimeout bounds every receive; zero waits forever.
func (c *Conn) SetTimeout(d time.Duration) error {
	tv := unix.NsecToTimeval(d.Nanoseconds())
	return unix.SetsockoptTimeval(c.fd, unix.SOL_SOCKET, unix.SO_RCVTIMEO, &tv)
}

// Recv reads one datagram's messages. A timeout returns os.ErrDeadlineExceeded.
func (c *Conn) Recv() ([]Message, error) {
	buf := make([]byte, 64*1024)
	n, _, err := unix.Recvfrom(c.fd, buf, 0)
	if err != nil {
		if errors.Is(err, unix.EAGAIN) || errors.Is(err, unix.EWOULDBLOCK) {
			return nil, os.ErrDeadlineExceeded
		}
		if errors.Is(err, unix.EINTR) {
			return nil, nil
		}
		return nil, fmt.Errorf("netlink receive: %w", err)
	}
	return ParseMessages(buf[:n])
}

// LookupFamily asks the controller for a family by name.
func (c *Conn) LookupFamily(name string) (Family, error) {
	c.seq++
	req := GenlMessage(unix.GENL_ID_CTRL, unix.NLM_F_REQUEST|unix.NLM_F_ACK, c.seq, unix.CTRL_CMD_GETFAMILY, 1,
		Attr(unix.CTRL_ATTR_FAMILY_NAME, append([]byte(name), 0)))
	if err := unix.Sendto(c.fd, req, 0, &unix.SockaddrNetlink{Family: unix.AF_NETLINK}); err != nil {
		return Family{}, fmt.Errorf("netlink send: %w", err)
	}
	for {
		msgs, err := c.Recv()
		if err != nil {
			return Family{}, err
		}
		for _, m := range msgs {
			if m.Header.Seq != c.seq {
				continue
			}
			switch m.Header.Type {
			case unix.NLMSG_ERROR:
				if len(m.Data) >= 4 {
					if code := int32(binary.LittleEndian.Uint32(m.Data[:4])); code != 0 {
						if -code == int32(unix.ENOENT) {
							return Family{}, ErrNoFamily
						}
						return Family{}, fmt.Errorf("netlink: %w", unix.Errno(-code))
					}
				}
			case unix.GENL_ID_CTRL:
				return ParseFamily(m.Data)
			}
		}
	}
}

// Join subscribes to a multicast group.
func (c *Conn) Join(group uint32) error {
	if err := unix.SetsockoptInt(c.fd, unix.SOL_NETLINK, unix.NETLINK_ADD_MEMBERSHIP, int(group)); err != nil {
		return fmt.Errorf("netlink join group %d: %w", group, err)
	}
	return nil
}

// Subscribe looks the thermal family up and joins its event group.
func (c *Conn) Subscribe() (Family, error) {
	f, err := c.LookupFamily(FamilyName)
	if err != nil {
		return f, err
	}
	gid, ok := f.Groups[EventGroup]
	if !ok {
		return f, fmt.Errorf("thermal family without an %q group", EventGroup)
	}
	return f, c.Join(gid)
}

// Events receives until the timeout (zero: forever) or an error, calling fn
// for every trip crossing, resolved against root's sysfs.
func (c *Conn) Events(family uint16, root string, fn func(Event) error) error {
	for {
		msgs, err := c.Recv()
		if err != nil {
			return err
		}
		for _, m := range msgs {
			if m.Header.Type != family {
				continue
			}
			e, ok, err := ParseEvent(m.Data)
			if err != nil || !ok {
				continue
			}
			if err := fn(Resolve(root, e)); err != nil {
				return err
			}
		}
	}
}
