package ht3

import (
	"bytes"
	"encoding/hex"
	"errors"
	"io"
	"net"
	"reflect"
	"testing"
	"time"
)

// Replies captured from a paired HT3 on 2026-09-19 (PROTOCOL.md).
const (
	capturedBattery = "0002015959" // 89 %
	capturedMode    = "0030010202" // transparency
	capturedSpatial = "0013010000" // off
)

func unhex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestGetFrames(t *testing.T) {
	for param, want := range map[byte]string{ParamBattery: "00020000", ParamMode: "00300000"} {
		if got := hex.EncodeToString(Get(param)); got != want {
			t.Errorf("GET %02x = %s, want %s", param, got, want)
		}
	}
	// The captured replies are frames with the checksum PROTOCOL.md gives.
	if got := hex.EncodeToString(Frame(OpGet, ParamBattery, []byte{89})); got != capturedBattery {
		t.Errorf("battery frame %s", got)
	}
	if got := hex.EncodeToString(Frame(OpSet, 0x0b, []byte{0xff, 0x02})); got != "100b02ff0201" {
		t.Errorf("checksum is not modulo 256: %s", got)
	}
}

// The SETs PROTOCOL.md names for the three modes the panel offers, built
// by its frame rule: opcode 16, parameter, length 1, payload, checksum.
func TestSetModeFrames(t *testing.T) {
	for mode, want := range map[byte]string{
		ModeNormal:       "1004010000",
		ModeANC:          "1004010101",
		ModeTransparency: "1005010101",
	} {
		got, ok := SetMode(mode)
		if !ok || hex.EncodeToString(got) != want {
			t.Errorf("SET for %s = %x %v, want %s", ModeName(int(mode)), got, ok, want)
		}
		if b, ok := ModeByName(ModeName(int(mode))); !ok || b != mode {
			t.Errorf("ModeByName(%s) = %d %v", ModeName(int(mode)), b, ok)
		}
	}
	// Wind, leisure and adaptive are read, never set: PROTOCOL.md gives
	// no SET for them.
	for _, mode := range []byte{3, 4, 6, 0xff} {
		if got, ok := SetMode(mode); ok || got != nil {
			t.Errorf("SET for mode %d = %x", mode, got)
		}
	}
	for _, name := range []string{"wind", "leisure", "adaptive", "unknown", "", "ANC"} {
		if _, ok := ModeByName(name); ok {
			t.Errorf("ModeByName(%q) accepted", name)
		}
	}
}

// The GET 0x30 readback for each mode the panel sets: transparency is the
// captured reply, the other two follow the same frame rule.
func TestModeReadbacks(t *testing.T) {
	for stream, want := range map[string]string{
		"0030010000": "normal",
		"0030010101": "anc",
		capturedMode: "transparency",
	} {
		var p Parser
		// The SET's acknowledgement before the readback is not a reading.
		got := p.Feed(unhex(t, "1004010101"+stream))
		if len(got) != 1 {
			t.Fatalf("%s: replies %+v", stream, got)
		}
		s := Unknown()
		s.Apply(got[0])
		if ModeName(s.Mode) != want {
			t.Errorf("%s read as %s, want %s", stream, ModeName(s.Mode), want)
		}
	}
}

func TestCapturedReplies(t *testing.T) {
	var p Parser
	got := p.Feed(unhex(t, capturedBattery+capturedMode+capturedSpatial))
	want := []Reply{
		{Param: ParamBattery, Payload: []byte{89}},
		{Param: ParamMode, Payload: []byte{2}},
		{Param: ParamSpatial, Payload: []byte{0}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("replies %+v", got)
	}
	s := Unknown()
	for _, r := range got {
		s.Apply(r)
	}
	if s.Battery != 89 || ModeName(s.Mode) != "transparency" || !s.Complete() {
		t.Errorf("state %+v (%s)", s, ModeName(s.Mode))
	}
}

func TestFragmentedStream(t *testing.T) {
	stream := unhex(t, capturedBattery+capturedMode)
	// Every split point, and one byte at a time.
	for cut := 1; cut < len(stream); cut++ {
		var p Parser
		got := append(p.Feed(stream[:cut]), p.Feed(stream[cut:])...)
		if len(got) != 2 || got[0].Param != ParamBattery || got[1].Param != ParamMode {
			t.Errorf("cut at %d: %+v", cut, got)
		}
	}
	var p Parser
	var got []Reply
	for _, b := range stream {
		got = append(got, p.Feed([]byte{b})...)
	}
	if len(got) != 2 {
		t.Errorf("byte at a time: %+v", got)
	}
}

func TestNoiseAndChecksums(t *testing.T) {
	cases := map[string]struct {
		stream string
		want   []byte // params found
	}{
		"vendor envelope before and after": {"aa5503010203ff" + capturedBattery + "ff00", []byte{ParamBattery}},
		"bad checksum":                     {"0002015958" + capturedMode, []byte{ParamMode}},
		// PROTOCOL.md does not give the SET acknowledgement's bytes; these
		// are synthetic opcode-16 frames for the SETs it names.
		"SET acknowledgement (synthetic)": {"1004010101" + "1005010101", nil},
		"unknown parameter":               {"0077010101", nil},
		"wrong length for battery":        {"000202595900", nil},
		"zero bytes around a reply":       {"000000" + capturedMode + "0000", []byte{ParamMode}},
	}
	for name, c := range cases {
		var p Parser
		var params []byte
		for _, r := range p.Feed(unhex(t, c.stream)) {
			params = append(params, r.Param)
		}
		if !bytes.Equal(params, c.want) {
			t.Errorf("%s: params %x, want %x", name, params, c.want)
		}
	}
}

func TestPartialKeptUntilComplete(t *testing.T) {
	var p Parser
	if got := p.Feed(unhex(t, "ffff000201")); len(got) != 0 {
		t.Fatalf("a partial reply was returned: %+v", got)
	}
	if got := p.Feed(unhex(t, "5959")); len(got) != 1 || got[0].Payload[0] != 89 {
		t.Fatalf("the rest did not complete it: %+v", got)
	}
	if len(p.buf) != 0 {
		t.Errorf("buffer kept %x", p.buf)
	}
}

func TestFalseStartFlushed(t *testing.T) {
	// Vendor bytes that look like an EQ header hold the battery reply back
	// until the wait runs out; Flush then finds it.
	var p Parser
	if got := p.Feed(unhex(t, "000b14"+capturedBattery)); len(got) != 0 {
		t.Fatalf("read inside a possible EQ reply: %+v", got)
	}
	if got := p.Flush(); len(got) != 1 || got[0].Param != ParamBattery || got[0].Payload[0] != 89 {
		t.Fatalf("flush: %+v", got)
	}
	if len(p.buf) != 0 || len(p.Flush()) != 0 {
		t.Errorf("buffer kept %x", p.buf)
	}
	// A partial reply with nothing complete after it stays for its end.
	p.Feed(unhex(t, "000201"))
	if got := p.Flush(); len(got) != 0 || len(p.buf) != 3 {
		t.Errorf("flush dropped a lone partial: %+v %x", got, p.buf)
	}
}

func TestEQReplyStepsOverItsBody(t *testing.T) {
	// Ten gains then ten frequency codes (PROTOCOL.md); the gains here
	// hold a battery-shaped run that must not be read as a reply.
	payload := unhex(t, "00020159590000000000"+"05060708"+"0a0c0e10"+"1214")
	var p Parser
	got := p.Feed(Frame(OpGet, ParamEQ, payload))
	if len(got) != 1 || got[0].Param != ParamEQ || len(got[0].Payload) != 20 {
		t.Fatalf("EQ reply: %+v", got)
	}
	// The same reply split at every point: still one EQ reply, and the
	// battery-shaped run in its gains is never taken.
	frame := Frame(OpGet, ParamEQ, payload)
	for cut := 1; cut < len(frame); cut++ {
		var p Parser
		got := append(p.Feed(frame[:cut]), p.Feed(frame[cut:])...)
		if len(got) != 1 || got[0].Param != ParamEQ {
			t.Errorf("cut at %d: %+v", cut, got)
		}
	}
}

func TestStateApply(t *testing.T) {
	s := Unknown()
	if s.Complete() {
		t.Fatal("unknown state is complete")
	}
	if s.Apply(Reply{Param: ParamBattery, Payload: []byte{101}}) || s.Battery != -1 {
		t.Error("a battery above 100 was taken")
	}
	if !s.Apply(Reply{Param: ParamBattery, Payload: []byte{100}}) || s.Apply(Reply{Param: ParamBattery, Payload: []byte{100}}) {
		t.Error("battery change detection")
	}
	if s.Apply(Reply{Param: ParamSpatial, Payload: []byte{1}}) {
		t.Error("spatial changed the state")
	}
	if !s.Apply(Reply{Param: ParamMode, Payload: []byte{5}}) || ModeName(s.Mode) != "unknown" {
		t.Error("an unlisted mode should be kept and named unknown")
	}
	for b, name := range map[int]string{0: "normal", 1: "anc", 2: "transparency", 3: "wind", 4: "leisure", 6: "adaptive", -1: "unknown"} {
		if ModeName(b) != name {
			t.Errorf("mode %d = %s", b, ModeName(b))
		}
	}
}

func TestBdaddr(t *testing.T) {
	mac, err := ParseAddress("AA:BB:CC:DD:EE:FF")
	if err != nil {
		t.Fatal(err)
	}
	if got := bdaddr(mac); got != [6]byte{0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa} {
		t.Errorf("bdaddr %x", got)
	}
}

func TestParseAddress(t *testing.T) {
	got, err := ParseAddress("aa:BB:0c:1D:e2:F3")
	if err != nil || got != [6]byte{0xaa, 0xbb, 0x0c, 0x1d, 0xe2, 0xf3} {
		t.Errorf("%x %v", got, err)
	}
	for _, bad := range []string{"", "AA:BB:CC:DD:EE", "AA:BB:CC:DD:EE:FG", "AAA:BB:CC:DD:EE:F", "AA-BB-CC-DD-EE-FF", "AA:BB:CC:DD:EE:FF:00"} {
		if _, err := ParseAddress(bad); err == nil {
			t.Errorf("%q accepted", bad)
		}
	}
}

// headset answers GETs on the far end of a pipe as the HT3 does: the
// battery reply split across two writes and vendor noise in between.
func headset(t *testing.T, c net.Conn, answer map[byte]string, asked chan<- []byte) {
	t.Helper()
	buf := make([]byte, 64)
	for {
		n, err := c.Read(buf)
		if err != nil {
			return
		}
		asked <- append([]byte(nil), buf[:n]...)
		for i := 0; i+4 <= n; i += 4 {
			reply, ok := answer[buf[i+1]]
			if !ok {
				continue
			}
			b := unhex(t, reply)
			if _, err := c.Write(append(unhex(t, "aa55"), b[:2]...)); err != nil {
				return
			}
			if _, err := c.Write(b[2:]); err != nil {
				return
			}
		}
	}
}

func TestSessionQuery(t *testing.T) {
	ours, theirs := net.Pipe()
	defer ours.Close()
	asked := make(chan []byte, 8)
	go headset(t, theirs, map[byte]string{ParamBattery: capturedBattery, ParamMode: capturedMode}, asked)
	s := NewSession(ours)
	var seen []State
	if err := s.Query(time.Second, 3, func(st State) error { seen = append(seen, st); return nil }); err != nil {
		t.Fatal(err)
	}
	if s.State.Battery != 89 || s.State.Mode != 2 || len(seen) != 2 {
		t.Errorf("state %+v, changes %+v", s.State, seen)
	}
	if got := hex.EncodeToString(<-asked); got != "0002000000300000" {
		t.Errorf("asked %s", got)
	}
	// A later reply (as if the mode changed on the headset) reaches Follow.
	done := make(chan error, 1)
	go func() {
		done <- s.Follow(Watch{Every: time.Hour, Wait: time.Second, Tries: 3, Changed: func(st State) error {
			if st.Mode == 1 {
				return io.ErrUnexpectedEOF // stop here
			}
			return nil
		}})
	}()
	if _, err := theirs.Write(unhex(t, "0030010101")); err != nil {
		t.Fatal(err)
	}
	if err := <-done; !errors.Is(err, io.ErrUnexpectedEOF) {
		t.Errorf("follow: %v", err)
	}
	theirs.Close()
}

func TestFollowAsksAgain(t *testing.T) {
	ours, theirs := net.Pipe()
	defer ours.Close()
	asked := make(chan []byte, 8)
	go headset(t, theirs, map[byte]string{ParamBattery: capturedBattery, ParamMode: capturedMode}, asked)
	s := NewSession(ours)
	if err := s.Query(time.Second, 3, func(State) error { return nil }); err != nil {
		t.Fatal(err)
	}
	<-asked
	done := make(chan error, 1)
	go func() {
		done <- s.Follow(Watch{Every: 20 * time.Millisecond, Wait: time.Second, Tries: 3, Changed: func(State) error { return nil }})
	}()
	select {
	case got := <-asked:
		if hex.EncodeToString(got) != "0002000000300000" {
			t.Errorf("asked again %x", got)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Follow did not ask again")
	}
	theirs.Close()
	if err := <-done; err == nil {
		t.Error("Follow returned no error after the channel closed")
	}
}

func TestSessionRetriesOnlyMissing(t *testing.T) {
	ours, theirs := net.Pipe()
	defer ours.Close()
	defer theirs.Close()
	asked := make(chan []byte, 8)
	// The mode is never answered.
	go headset(t, theirs, map[byte]string{ParamBattery: capturedBattery}, asked)
	s := NewSession(ours)
	err := s.Query(50*time.Millisecond, 3, func(State) error { return nil })
	if !errors.Is(err, ErrNoAnswer) {
		t.Fatalf("err %v", err)
	}
	if s.State.Battery != 89 || s.State.Mode != -1 {
		t.Errorf("state %+v", s.State)
	}
	var all []string
	for len(asked) > 0 {
		all = append(all, hex.EncodeToString(<-asked))
	}
	if !reflect.DeepEqual(all, []string{"0002000000300000", "00300000", "00300000"}) {
		t.Errorf("asked %v", all)
	}
	if Explain(err) == "" || Explain(io.EOF) == Explain(err) {
		t.Error("explanations")
	}
}

// modeHeadset is a headset that keeps a noise mode: it acknowledges each
// SET with an opcode-16 frame (synthetic), switches mode when obey is
// set, and answers GET battery and GET mode. Every frame asked is sent on
// asked. Replies go out from their own goroutine, as a socket buffers
// them, so the fake never blocks Follow's writes.
func modeHeadset(t *testing.T, c net.Conn, mode byte, obey bool, asked chan<- []byte) {
	t.Helper()
	replies := make(chan []byte, 16)
	go func() {
		for r := range replies {
			if _, err := c.Write(r); err != nil {
				return
			}
		}
	}()
	defer close(replies)
	var buf []byte
	chunk := make([]byte, 64)
	for {
		n, err := c.Read(chunk)
		if err != nil {
			return
		}
		buf = append(buf, chunk[:n]...)
		for len(buf) >= 4 && len(buf) >= 4+int(buf[2]) {
			end := 4 + int(buf[2])
			frame := append([]byte(nil), buf[:end]...)
			buf = buf[end:]
			asked <- frame
			op, param, payload := frame[0], frame[1], frame[3:end-1]
			switch {
			case op == OpSet:
				replies <- frame // the acknowledgement echoes the SET
				if obey && param == ParamANC {
					mode = payload[0]
				} else if obey && param == ParamTransparency && payload[0] == 1 {
					mode = ModeTransparency
				}
			case param == ParamMode:
				replies <- Frame(OpGet, ParamMode, []byte{mode})
			case param == ParamBattery:
				replies <- unhex(t, capturedBattery)
			}
		}
	}
}

type modeDone struct {
	mode byte
	err  error
}

// follow runs Follow on a fresh session already holding the captured
// state (89 %, transparency) and returns where its events go.
func follow(t *testing.T, ours net.Conn, w Watch) (chan State, chan modeDone, chan error) {
	t.Helper()
	changed := make(chan State, 8)
	done := make(chan modeDone, 8)
	stopped := make(chan error, 1)
	s := NewSession(ours)
	s.State = State{Battery: 89, Mode: int(ModeTransparency)}
	w.Changed = func(st State) error { changed <- st; return nil }
	w.Done = func(m byte, err error) error { done <- modeDone{m, err}; return nil }
	go func() { stopped <- s.Follow(w) }()
	return changed, done, stopped
}

func waitFor[T any](t *testing.T, c <-chan T, what string) T {
	t.Helper()
	select {
	case v := <-c:
		return v
	case <-time.After(5 * time.Second):
		t.Fatalf("no %s", what)
	}
	var zero T
	return zero
}

func TestFollowSetsMode(t *testing.T) {
	for _, mode := range []byte{ModeANC, ModeNormal, ModeTransparency} {
		ours, theirs := net.Pipe()
		asked := make(chan []byte, 16)
		go modeHeadset(t, theirs, ModeTransparency, true, asked)
		modes := make(chan byte, 1)
		changed, done, stopped := follow(t, ours, Watch{Every: time.Hour, Wait: time.Second, Tries: 3, Modes: modes})
		modes <- mode
		set, _ := SetMode(mode)
		if got := waitFor(t, asked, "SET"); !bytes.Equal(got, set) {
			t.Errorf("%s: first frame %x, want the SET %x", ModeName(int(mode)), got, set)
		}
		if got := waitFor(t, asked, "readback"); !bytes.Equal(got, Get(ParamMode)) {
			t.Errorf("%s: SET not followed by GET 30: %x", ModeName(int(mode)), got)
		}
		if mode != ModeTransparency {
			// The new mode reaches Changed before Done reports it.
			if st := waitFor(t, changed, "change"); st.Mode != int(mode) {
				t.Errorf("changed to %s", ModeName(st.Mode))
			}
		}
		if d := waitFor(t, done, "done"); d.mode != mode || d.err != nil {
			t.Errorf("%s: done %+v", ModeName(int(mode)), d)
		}
		theirs.Close()
		if err := waitFor(t, stopped, "stop"); err == nil {
			t.Error("Follow returned no error after the channel closed")
		}
		ours.Close()
	}
}

func TestFollowModeNotConfirmed(t *testing.T) {
	ours, theirs := net.Pipe()
	defer ours.Close()
	asked := make(chan []byte, 16)
	// The headset acknowledges the SET but stays in transparency.
	gone := make(chan struct{})
	go func() { modeHeadset(t, theirs, ModeTransparency, false, asked); close(gone) }()
	modes := make(chan byte, 1)
	changed, done, stopped := follow(t, ours, Watch{Every: time.Hour, Wait: 30 * time.Millisecond, Tries: 3, Modes: modes})
	modes <- ModeANC
	if d := waitFor(t, done, "done"); d.mode != ModeANC || !errors.Is(d.err, ErrNotChanged) {
		t.Errorf("done %+v", d)
	}
	theirs.Close()
	waitFor(t, stopped, "stop")
	<-gone
	readbacks := 0
	for len(asked) > 0 {
		if bytes.Equal(<-asked, Get(ParamMode)) {
			readbacks++
		}
	}
	if readbacks != 3 {
		t.Errorf("%d readbacks, want 3", readbacks)
	}
	if len(changed) != 0 {
		t.Errorf("the acknowledgement or an unchanged readback was taken as a change: %+v", <-changed)
	}
}

func TestFollowRefusesModeWithoutSet(t *testing.T) {
	ours, theirs := net.Pipe()
	defer ours.Close()
	asked := make(chan []byte, 16)
	go modeHeadset(t, theirs, ModeTransparency, true, asked)
	modes := make(chan byte, 1)
	_, done, stopped := follow(t, ours, Watch{Every: time.Hour, Wait: time.Second, Tries: 3, Modes: modes})
	modes <- 6 // adaptive
	if d := waitFor(t, done, "done"); d.mode != 6 || !errors.Is(d.err, ErrNotSettable) {
		t.Errorf("done %+v", d)
	}
	theirs.Close()
	waitFor(t, stopped, "stop")
	if len(asked) != 0 {
		t.Errorf("sent %x for a mode without a SET", <-asked)
	}
}
