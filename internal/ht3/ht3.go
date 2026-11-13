// Package ht3 reads a TOZO HT3 headset's battery and noise mode over its
// Bluetooth Classic control channel (issue #65; the HT3 widget in the shell
// and look design).
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
//   - The socket is a byte stream: a read may hold part of a packet or
//     several, and the headset also sends vendor data in another envelope.
//
// This package only reads. It sends no SET packet.
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
		if err := s.read(time.Now().Add(wait), true, changed); err != nil {
			return err
		}
	}
	if !s.State.Complete() {
		return ErrNoAnswer
	}
	return nil
}

// Follow keeps reading, and asks for both values again every interval,
// so a change on the headset reaches changed while the panel stays open.
// It returns when the connection fails or closes.
func (s *Session) Follow(every time.Duration, changed func(State) error) error {
	for {
		if err := s.read(time.Now().Add(every), false, changed); err != nil {
			return err
		}
		if _, err := s.conn.Write(append(Get(ParamBattery), Get(ParamMode)...)); err != nil {
			return err
		}
	}
}

// read reads until the deadline or, with untilComplete, until the state is
// complete. At the deadline it flushes a partial packet the parser kept.
func (s *Session) read(deadline time.Time, untilComplete bool, changed func(State) error) error {
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
		if untilComplete && s.State.Complete() {
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
