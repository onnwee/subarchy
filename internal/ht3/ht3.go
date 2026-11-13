// Package ht3 reads a TOZO HT3 headset's battery and noise mode over its
// Bluetooth Classic control channel and sets the noise mode (issues #65 and
// #153; the HT3 widget in the shell and look design).
//
// The protocol is the one `PROTOCOL.md` in the owner's omarchy-plugin-ht3
// repository documents, used here as a specification:
//
//   - RFCOMM channel 1. Closing it leaves the audio profile connected.
//   - A packet is opcode, parameter, payload length, payload, then
//     sum(payload) modulo 256.
//   - GET is opcode 0 with an empty payload; the reply is a GET-shaped
//     packet carrying the value. SET is opcode 16; its acknowledgement is
//     not a reading.
//   - Battery is parameter 0x02, one byte 0–100. Noise mode is 0x30, one
//     byte: 0 normal, 1 ANC, 2 transparency, 3 wind, 4 leisure, 6
//     adaptive.
//   - Normal is SET 0x04 payload 00, ANC SET 0x04 payload 01, transparency
//     SET 0x05 payload 01. The saved boot mode is left alone.
//   - The socket is a byte stream: a read may hold part of a packet or
//     several, and the headset also sends vendor data in another envelope.
//
// The only SET this package sends is a noise mode, and a mode counts as
// changed only when a GET 0x30 that follows it reports the new mode.
package ht3

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"time"
)

// Opcodes.
const (
	OpGet byte = 0x00
	OpSet byte = 0x10
)

// Parameters.
const (
	ParamBattery byte = 0x02
	ParamSpatial byte = 0x13
	ParamEQ      byte = 0x0b
	ParamMode    byte = 0x30
	// SET parameters that select a noise mode.
	ParamANC          byte = 0x04
	ParamTransparency byte = 0x05
)

// The noise modes the panel can set.
const (
	ModeNormal       byte = 0
	ModeANC          byte = 1
	ModeTransparency byte = 2
)

// replyLen is the payload length of each GET reply PROTOCOL.md describes.
// Spatial audio and EQ are never asked for, but knowing their lengths lets
// the parser step over a whole reply instead of reading into it.
var replyLen = map[byte]byte{
	ParamBattery: 1,
	ParamSpatial: 1,
	ParamEQ:      20,
	ParamMode:    1,
}

// Modes names the noise modes by their byte.
var Modes = map[byte]string{
	0: "normal",
	1: "anc",
	2: "transparency",
	3: "wind",
	4: "leisure",
	6: "adaptive",
}

// Frame encodes one packet.
func Frame(op, param byte, payload []byte) []byte {
	out := make([]byte, 0, 4+len(payload))
	out = append(out, op, param, byte(len(payload)))
	out = append(out, payload...)
	return append(out, checksum(payload))
}

// Get encodes a GET for param.
func Get(param byte) []byte {
	return Frame(OpGet, param, nil)
}

// SetMode encodes the SET that selects mode: normal is SET 04 00, ANC
// SET 04 01, transparency SET 05 01 (PROTOCOL.md). ok is false for the
// modes the headset reports but PROTOCOL.md gives no SET for.
func SetMode(mode byte) (packet []byte, ok bool) {
	switch mode {
	case ModeNormal:
		return Frame(OpSet, ParamANC, []byte{0x00}), true
	case ModeANC:
		return Frame(OpSet, ParamANC, []byte{0x01}), true
	case ModeTransparency:
		return Frame(OpSet, ParamTransparency, []byte{0x01}), true
	}
	return nil, false
}

// ModeByName is the byte of a mode SetMode can set, by its name in Modes.
func ModeByName(name string) (byte, bool) {
	for b, n := range Modes {
		if n == name {
			if _, ok := SetMode(b); ok {
				return b, true
			}
		}
	}
	return 0, false
}

func checksum(payload []byte) byte {
	var sum byte
	for _, b := range payload {
		sum += b
	}
	return sum
}

// Reply is one GET reply taken from the stream.
type Reply struct {
	Param   byte
	Payload []byte
}

// Parser takes GET replies out of the RFCOMM byte stream. It accepts a
// packet only with opcode 0, a known parameter, that parameter's reply
// length and a matching checksum; anything else is skipped a byte at a
// time. The zero value is ready to use.
type Parser struct {
	buf []byte
}

// Feed adds bytes read from the socket and returns the complete replies
// they finish. A packet cut across reads is kept until its end arrives:
// once its header names a known reply and that reply's length, bytes
// inside its body are not read as replies of their own (an EQ reply's
// gains can look like a battery reply). Flush gives up on it.
func (p *Parser) Feed(b []byte) []Reply {
	p.buf = append(p.buf, b...)
	var out []Reply
	i := 0
	for i < len(p.buf) {
		end, status := frameAt(p.buf[i:])
		switch status {
		case frameNo:
			i++
			continue
		case framePartial:
			p.buf = append(p.buf[:0], p.buf[i:]...)
			return out
		}
		rest := p.buf[i:]
		out = append(out, Reply{Param: rest[1], Payload: append([]byte(nil), rest[3:end-1]...)})
		i += end
	}
	p.buf = p.buf[:0]
	return out
}

// Pending reports whether Feed is holding the start of a packet.
func (p *Parser) Pending() bool { return len(p.buf) > 0 }

// Flush treats a kept partial packet as noise when complete replies follow
// it, and returns those. Session calls it when a wait for replies runs out,
// so a false packet start (vendor bytes that look like a GET header) holds
// a real reply back by one wait at most. An EQ reply whose second half
// comes later than that can still be misread; the helper never asks for EQ.
func (p *Parser) Flush() []Reply {
	var out []Reply
	for len(p.buf) > 0 && completeAfter(p.buf[1:]) {
		rest := append([]byte(nil), p.buf[1:]...)
		p.buf = p.buf[:0]
		out = append(out, p.Feed(rest)...)
	}
	return out
}

const (
	frameNo = iota
	framePartial
	frameOK
)

// frameAt reports whether b starts with a GET reply: frameOK with its
// length, framePartial when b ends before the reply could, frameNo when it
// cannot be one.
func frameAt(b []byte) (int, int) {
	if b[0] != OpGet {
		return 0, frameNo
	}
	if len(b) < 2 {
		return 0, framePartial
	}
	n, ok := replyLen[b[1]]
	if !ok {
		return 0, frameNo
	}
	if len(b) < 3 {
		return 0, framePartial
	}
	if b[2] != n {
		return 0, frameNo
	}
	end := 3 + int(n) + 1
	if len(b) < end {
		return 0, framePartial
	}
	if checksum(b[3:end-1]) != b[end-1] {
		return 0, frameNo
	}
	return end, frameOK
}

func completeAfter(b []byte) bool {
	for j := range b {
		if _, status := frameAt(b[j:]); status == frameOK {
			return true
		}
	}
	return false
}

// State is what the headset has reported; -1 means not yet.
type State struct {
	Battery int
	Mode    int
}

// Unknown is the state before any reply.
func Unknown() State { return State{Battery: -1, Mode: -1} }

// Apply folds a reply into s and reports whether it changed s. A battery
// above 100 is not a reading and is ignored.
func (s *State) Apply(r Reply) bool {
	if len(r.Payload) != 1 {
		return false
	}
	v := int(r.Payload[0])
	switch r.Param {
	case ParamBattery:
		if v > 100 || v == s.Battery {
			return false
		}
		s.Battery = v
	case ParamMode:
		if v == s.Mode {
			return false
		}
		s.Mode = v
	default:
		return false
	}
	return true
}

// Complete reports whether both values have been read.
func (s State) Complete() bool { return s.Battery >= 0 && s.Mode >= 0 }

// ModeName is the noise mode's name, or "unknown" for a byte PROTOCOL.md
// does not list.
func ModeName(mode int) string {
	if mode < 0 || mode > 255 {
		return "unknown"
	}
	if name, ok := Modes[byte(mode)]; ok {
		return name
	}
	return "unknown"
}

// Conn is the control channel: the RFCOMM socket, or a pipe in tests.
type Conn interface {
	io.ReadWriter
	SetReadDeadline(time.Time) error
}

// ErrNoAnswer means the headset did not answer the GETs.
var ErrNoAnswer = errors.New("the headphones did not answer")

// Session reads replies from one connection.
type Session struct {
	conn  Conn
	parse Parser
	State State
}

// NewSession wraps an open control channel.
func NewSession(c Conn) *Session {
	return &Session{conn: c, State: Unknown()}
}

// Query asks for the battery and the noise mode, and asks again for any
// value still missing after each wait, up to tries times. changed is
// called with the state whenever a reply changes it.
func (s *Session) Query(wait time.Duration, tries int, changed func(State) error) error {
	for try := 0; try < tries && !s.State.Complete(); try++ {
		var ask []byte
		if s.State.Battery < 0 {
			ask = append(ask, Get(ParamBattery)...)
		}
		if s.State.Mode < 0 {
			ask = append(ask, Get(ParamMode)...)
		}
		if _, err := s.conn.Write(ask); err != nil {
			return err
		}
		if err := s.read(time.Now().Add(wait), changed); err != nil {
			return err
		}
	}
	if !s.State.Complete() {
		return ErrNoAnswer
	}
	return nil
}

// ErrNotChanged means the readback after a mode SET reported another mode.
var ErrNotChanged = errors.New("the headphones did not change the noise mode")

// ErrNotSettable means a mode has no SET in PROTOCOL.md.
var ErrNotSettable = errors.New("this noise mode cannot be set from here")

// Watch is what Follow does besides reading.
type Watch struct {
	// Every is how often Follow asks for both values again.
	Every time.Duration
	// Wait is how long a readback may take before Follow asks again, and
	// how long a partial packet is kept before Flush.
	Wait time.Duration
	// Tries is how many readbacks a mode change gets.
	Tries int
	// Modes carries the mode changes to make; nil for none.
	Modes <-chan byte
	// Changed is called with the state whenever a reply changes it.
	Changed func(State) error
	// Done is called once per mode change: err is nil when a readback
	// reported the mode, ErrNotChanged when every readback reported
	// another, ErrNotSettable for a mode without a SET.
	Done func(mode byte, err error) error
}

// Follow keeps reading after Query until the connection fails or closes.
// It asks for both values again every w.Every, so a change made on the
// headset reaches w.Changed, and it carries out the mode changes sent on
// w.Modes: SET, then GET 0x30, asked again after each w.Wait until the
// readback reports the mode or w.Tries readbacks have not. A SET's
// acknowledgement is never taken as the new mode. A change sent while
// another is waiting replaces it.
func (s *Session) Follow(w Watch) error {
	if err := s.conn.SetReadDeadline(time.Time{}); err != nil {
		return err
	}
	chunks := make(chan []byte)
	failed := make(chan error, 1)
	stop := make(chan struct{})
	defer close(stop)
	go func() {
		for {
			buf := make([]byte, 256)
			n, err := s.conn.Read(buf)
			if n > 0 {
				select {
				case chunks <- buf[:n]:
				case <-stop:
					return
				}
			}
			if err != nil {
				failed <- err
				return
			}
		}
	}()
	refresh := time.NewTicker(w.Every)
	defer refresh.Stop()
	var flush, retry <-chan time.Time
	var want byte
	left := 0 // readbacks still to ask for; retry is nil when no change waits
	apply := func(replies []Reply) error {
		for _, r := range replies {
			if s.State.Apply(r) {
				if err := w.Changed(s.State); err != nil {
					return err
				}
			}
			if retry != nil && r.Param == ParamMode && s.State.Mode == int(want) {
				retry = nil
				if err := w.Done(want, nil); err != nil {
					return err
				}
			}
		}
		return nil
	}
	for {
		var err error
		select {
		case b := <-chunks:
			err = apply(s.parse.Feed(b))
			flush = nil
			if s.parse.Pending() {
				flush = time.After(w.Wait)
			}
		case err = <-failed:
			return err
		case <-flush:
			flush = nil
			err = apply(s.parse.Flush())
		case <-refresh.C:
			_, err = s.conn.Write(append(Get(ParamBattery), Get(ParamMode)...))
		case mode := <-w.Modes:
			packet, ok := SetMode(mode)
			if !ok {
				err = w.Done(mode, ErrNotSettable)
				break
			}
			want, left, retry = mode, w.Tries-1, time.After(w.Wait)
			_, err = s.conn.Write(append(packet, Get(ParamMode)...))
		case <-retry:
			if left <= 0 {
				retry = nil
				err = w.Done(want, ErrNotChanged)
				break
			}
			left--
			retry = time.After(w.Wait)
			_, err = s.conn.Write(Get(ParamMode))
		}
		if err != nil {
			return err
		}
	}
}

// read reads until the state is complete or the deadline passes. At the
// deadline it flushes a partial packet the parser kept.
func (s *Session) read(deadline time.Time, changed func(State) error) error {
	if err := s.conn.SetReadDeadline(deadline); err != nil {
		return err
	}
	apply := func(replies []Reply) error {
		for _, r := range replies {
			if s.State.Apply(r) {
				if err := changed(s.State); err != nil {
					return err
				}
			}
		}
		return nil
	}
	buf := make([]byte, 256)
	for {
		n, err := s.conn.Read(buf)
		if aerr := apply(s.parse.Feed(buf[:n])); aerr != nil {
			return aerr
		}
		if err != nil {
			if errors.Is(err, os.ErrDeadlineExceeded) {
				return apply(s.parse.Flush())
			}
			return err
		}
		if s.State.Complete() {
			return nil
		}
	}
}

// bdaddr is the address as the kernel's bdaddr_t holds it: little-endian,
// the last octet first.
func bdaddr(mac [6]byte) [6]byte {
	var out [6]byte
	for i := range mac {
		out[i] = mac[len(mac)-1-i]
	}
	return out
}

// ParseAddress reads a Bluetooth address written AA:BB:CC:DD:EE:FF.
func ParseAddress(s string) ([6]byte, error) {
	var out [6]byte
	parts := strings.Split(s, ":")
	if len(parts) != 6 {
		return out, fmt.Errorf("%q is not a Bluetooth address (AA:BB:CC:DD:EE:FF)", s)
	}
	for i, p := range parts {
		var b byte
		if len(p) != 2 {
			return out, fmt.Errorf("%q is not a Bluetooth address (AA:BB:CC:DD:EE:FF)", s)
		}
		for _, c := range []byte(p) {
			var d byte
			switch {
			case c >= '0' && c <= '9':
				d = c - '0'
			case c >= 'a' && c <= 'f':
				d = c - 'a' + 10
			case c >= 'A' && c <= 'F':
				d = c - 'A' + 10
			default:
				return out, fmt.Errorf("%q is not a Bluetooth address (AA:BB:CC:DD:EE:FF)", s)
			}
			b = b<<4 | d
		}
		out[i] = b
	}
	return out, nil
}
