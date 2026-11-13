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
	dir := t.TempDir()
	marker, ready := filepath.Join(dir, "cleaned-up"), filepath.Join(dir, "ready")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() {
		done <- ExecRunner{}.Run(ctx, "sh", "-c", `trap 'touch "$1"; exit 0' INT; touch "$2"; sleep 30 & wait`, "sh", marker, ready)
	}()
	// Interrupt only once sh has set its trap.
	for deadline := time.Now().Add(5 * time.Second); ; time.Sleep(10 * time.Millisecond) {
		if _, err := os.Stat(ready); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("sh did not set its trap")
		}
	}
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
