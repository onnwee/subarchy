package update

import (
	"context"
	"errors"
	"slices"
	"testing"
	"time"
)

type authorizationProbe struct {
	Runner
	queries chan []string
	err     error
}

func (p authorizationProbe) Output(_ context.Context, argv ...string) (string, error) {
	p.queries <- argv
	return "", p.err
}

func TestAuthorizationKeepalive(t *testing.T) {
	for _, revoked := range []bool{false, true} {
		t.Run(map[bool]string{false: "refresh", true: "revoked stops"}[revoked], func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			ticks := make(chan time.Time, 1)
			queries := make(chan []string, 1)
			probe := authorizationProbe{queries: queries}
			if revoked {
				probe.err = errors.New("sudo timestamp revoked")
			}
			done := make(chan struct{})
			go func() { defer close(done); keepAuthorization(ctx, probe, ticks) }()
			ticks <- time.Now()
			select {
			case argv := <-queries:
				if !slices.Equal(argv, []string{"sudo", "-n", "true"}) {
					t.Fatalf("background prompt possible: %v", argv)
				}
			case <-time.After(time.Second):
				t.Fatal("keepalive did not run")
			}
			if !revoked {
				cancel()
			}
			select {
			case <-done:
			case <-time.After(time.Second):
				t.Fatal("keepalive outlived update/revocation")
			}
		})
	}
}

func TestAuthorizationRelease(t *testing.T) {
	f := &fake{}
	stop, err := Authorize(context.Background(), f)
	if err != nil {
		t.Fatal(err)
	}
	stop()
	if !slices.Equal(f.ran, []string{"sudo true"}) {
		t.Fatalf("authorization = %v", f.ran)
	}
}
