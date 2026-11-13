package main

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"io"
	"net"
	"strings"
	"testing"
	"time"

	"git.subcult.tv/subculture-collective/subarchy/internal/dispatch"
	"git.subcult.tv/subculture-collective/subarchy/internal/ht3"
	"golang.org/x/sys/unix"
)

const address = "AA:BB:CC:DD:EE:FF"

// pipeConn is a net.Pipe end that, like a socket, still takes a deadline
// after the far end has closed.
type pipeConn struct{ net.Conn }

func (c pipeConn) SetReadDeadline(t time.Time) error {
	_ = c.Conn.SetReadDeadline(t)
	return nil
}

// fakeHeadset answers each GET with the captured PROTOCOL.md replies
// (89 %, transparency), then sends extra, then closes.
func fakeHeadset(t *testing.T, extra string) {
	t.Helper()
	prev := dial
	t.Cleanup(func() { dial = prev })
	dial = func(a string) (ht3.Conn, io.Closer, error) {
		if a != address {
			t.Errorf("dialled %q", a)
		}
		ours, theirs := net.Pipe()
		go func() {
			defer theirs.Close()
			buf := make([]byte, 16)
			if _, err := io.ReadFull(theirs, buf[:8]); err != nil {
				return
			}
			out, _ := hex.DecodeString("0002015959" + "0030010202" + extra)
			_, _ = theirs.Write(out)
		}()
		return pipeConn{ours}, ours, nil
	}
}

func TestStatus(t *testing.T) {
	fakeHeadset(t, "")
	var out, errOut bytes.Buffer
	if code := run([]string{"status", address}, &out, &errOut); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	if got := out.String(); got != "Battery  89 %\nMode     transparency\n" {
		t.Errorf("status %q", got)
	}
	out.Reset()
	fakeHeadset(t, "")
	if code := run([]string{"status", "--json", address}, &out, &errOut); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	if got := strings.TrimSpace(out.String()); got != `{"event":"state","battery":89,"mode":"transparency"}` {
		t.Errorf("status --json %s", got)
	}
}

func TestWatch(t *testing.T) {
	// The mode changes to ANC later; then the headset closes the channel.
	fakeHeadset(t, "0030010101")
	var out, errOut bytes.Buffer
	if code := run([]string{"watch", address}, &out, &errOut); code != 1 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	want := []string{
		`{"event":"connected"}`,
		`{"event":"state","battery":89}`,
		`{"event":"state","battery":89,"mode":"transparency"}`,
		`{"event":"state","battery":89,"mode":"anc"}`,
		`{"event":"error","message":"The headphones closed the control channel."}`,
	}
	if got := strings.Split(strings.TrimSpace(out.String()), "\n"); strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Errorf("watch:\n%s", out.String())
	}
}

func TestWatchDialError(t *testing.T) {
	prev := dial
	defer func() { dial = prev }()
	dial = func(string) (ht3.Conn, io.Closer, error) { return nil, nil, unix.EBUSY }
	var out, errOut bytes.Buffer
	if code := run([]string{"watch", address}, &out, &errOut); code != 1 {
		t.Fatalf("exit %d", code)
	}
	var l line
	if err := json.Unmarshal(out.Bytes(), &l); err != nil || l.Event != "error" || !strings.Contains(l.Message, "TOZO app") {
		t.Errorf("%s %v", out.String(), err)
	}
}

func TestUsage(t *testing.T) {
	for _, args := range [][]string{nil, {"set"}, {"status"}, {"watch", "not-an-address"}, {"status", address, "extra"}} {
		var out, errOut bytes.Buffer
		if code := run(args, &out, &errOut); code != 2 {
			t.Errorf("%q: exit %d", args, code)
		}
	}
	var out bytes.Buffer
	if code := run([]string{dispatch.MetadataFlag}, &out, io.Discard); code != 0 {
		t.Fatal(code)
	}
	var got []dispatch.Described
	if err := json.Unmarshal(out.Bytes(), &got); err != nil || len(got) != 2 || !got[1].Hidden {
		t.Errorf("metadata %s %v", out.String(), err)
	}
}
