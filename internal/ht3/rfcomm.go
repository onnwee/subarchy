package ht3

import (
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"golang.org/x/sys/unix"
)

// Channel is the HT3's RFCOMM control channel.
const Channel = 1

// Dial opens the control channel to the headset at address. The socket is
// non-blocking, so the returned file honours read deadlines. Closing it
// leaves the headset's audio connected.
func Dial(address string, timeout time.Duration) (*os.File, error) {
	mac, err := ParseAddress(address)
	if err != nil {
		return nil, err
	}
	fd, err := unix.Socket(unix.AF_BLUETOOTH, unix.SOCK_STREAM|unix.SOCK_NONBLOCK|unix.SOCK_CLOEXEC, unix.BTPROTO_RFCOMM)
	if err != nil {
		return nil, fmt.Errorf("open an RFCOMM socket: %w", err)
	}
	sa := &unix.SockaddrRFCOMM{Channel: Channel, Addr: bdaddr(mac)}
	err = unix.Connect(fd, sa)
	if errors.Is(err, unix.EINPROGRESS) {
		err = waitConnected(fd, timeout)
	}
	if err != nil {
		unix.Close(fd)
		return nil, err
	}
	return os.NewFile(uintptr(fd), "rfcomm:"+address), nil
}

func waitConnected(fd int, timeout time.Duration) error {
	fds := []unix.PollFd{{Fd: int32(fd), Events: unix.POLLOUT}}
	deadline := time.Now().Add(timeout)
	for {
		left := time.Until(deadline)
		if left <= 0 {
			return unix.ETIMEDOUT
		}
		n, err := unix.Poll(fds, int(left.Milliseconds())+1)
		if errors.Is(err, unix.EINTR) {
			continue
		}
		if err != nil {
			return err
		}
		if n == 0 {
			return unix.ETIMEDOUT
		}
		soErr, err := unix.GetsockoptInt(fd, unix.SOL_SOCKET, unix.SO_ERROR)
		if err != nil {
			return err
		}
		if soErr != 0 {
			return unix.Errno(soErr)
		}
		// Closed or failed with no error recorded: not connected.
		if fds[0].Revents&(unix.POLLHUP|unix.POLLERR|unix.POLLNVAL) != 0 {
			return unix.ECONNRESET
		}
		return nil
	}
}

// Explain turns a connection error into a sentence for the panel.
func Explain(err error) string {
	switch {
	case errors.Is(err, ErrNoAnswer):
		return "The headphones did not answer. Close the panel and open it again."
	case errors.Is(err, io.EOF):
		return "The headphones closed the control channel."
	case errors.Is(err, unix.EBUSY), errors.Is(err, unix.ECONNREFUSED), errors.Is(err, unix.EADDRINUSE):
		// Which of these the TOZO app's hold produces is not yet seen on
		// hardware; a refusal can also mean the channel is not offered.
		return "The headphones refused the control channel. If the TOZO app is open on a phone, close it, then open the panel again."
	case errors.Is(err, unix.ECONNRESET):
		return "The headphones dropped the control channel."
	case errors.Is(err, unix.ETIMEDOUT), errors.Is(err, unix.EHOSTDOWN), errors.Is(err, unix.EHOSTUNREACH):
		return "The headphones are out of reach."
	case errors.Is(err, unix.EAFNOSUPPORT), errors.Is(err, unix.EPROTONOSUPPORT):
		return "This system has no Bluetooth RFCOMM support."
	}
	return "Lost the headphones' control channel: " + err.Error()
}
