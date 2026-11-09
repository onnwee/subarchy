package update

import (
	"context"
	"fmt"
	"time"
)

// Authorize asks sudo once and keeps its timestamp fresh for this update.
// sudo true respects the normal cache and any explicit passwordless policy.
// The caller must call the returned function to stop the keepalive.
func Authorize(ctx context.Context, r Runner) (func(), error) {
	if err := r.Run(ctx, "sudo", "true"); err != nil {
		return nil, fmt.Errorf("authorize update: %w", err)
	}
	keepCtx, cancel := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() {
		defer close(done)
		ticker := time.NewTicker(time.Minute)
		defer ticker.Stop()
		keepAuthorization(keepCtx, r, ticker.C)
	}()
	return func() {
		cancel()
		<-done
	}, nil
}

func keepAuthorization(ctx context.Context, r Runner, ticks <-chan time.Time) {
	for {
		select {
		case <-ctx.Done():
			return
		case _, ok := <-ticks:
			if !ok {
				return
			}
			// Never ask from the background or undo an intentional revocation.
			if _, err := r.Output(ctx, "sudo", "-n", "true"); err != nil {
				return
			}
		}
	}
}
