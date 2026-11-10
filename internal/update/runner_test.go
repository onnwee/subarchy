package update

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// A command that changes the system must be allowed to stop itself: pacman
// finishes the package it is on and removes its lock on SIGINT, and leaves
// both behind when killed.
func TestRunInterruptsInsteadOfKilling(t *testing.T) {
	marker := filepath.Join(t.TempDir(), "cleaned-up")
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- ExecRunner{}.Run(ctx, "sh", "-c", `trap 'touch "$1"; exit 0' INT; sleep 30 & wait`, "sh", marker)
	}()
	time.Sleep(300 * time.Millisecond) // let sh set its trap
	cancel()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("Run did not return after the command handled the interrupt")
	}
	if _, err := os.Stat(marker); err != nil {
		t.Errorf("the command was killed before its handler ran: %v", err)
	}
}
