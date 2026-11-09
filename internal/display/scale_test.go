package display

import (
	"math"
	"testing"
)

func TestStepScale(t *testing.T) {
	for _, tt := range []struct {
		name          string
		width, height int
		current, want float64
	}{
		{"1080p", 1920, 1080, 1, 1.25},
		{"fractional panel", 3456, 2160, 1, 4.0 / 3},
		{"panel 1.6", 3456, 2160, 4.0 / 3, 1.6},
		{"floating point", 3456, 2160, 1.6000000002, 2},
		{"upper limit", 3456, 2160, 4, 4},
		{"tiny mode", 1, 1, 1, 1},
	} {
		t.Run(tt.name, func(t *testing.T) {
			got, err := StepScale(Monitor{Width: tt.width, Height: tt.height, Scale: tt.current}, 1)
			if err != nil || math.Abs(got-tt.want) > 0.0001 {
				t.Fatalf("StepScale = %g, %v; want %g", got, err, tt.want)
			}
		})
	}
	for _, current := range []float64{1, 1.25} {
		got, err := StepScale(Monitor{Width: 1920, Height: 1080, Scale: current}, -1)
		if err != nil || got != 1 {
			t.Fatalf("step down from %g: %g, %v", current, got, err)
		}
	}
}

func TestCleanScaleRejectsInvalidInput(t *testing.T) {
	for _, scale := range []float64{0, -1, 4.1, math.NaN(), math.Inf(1)} {
		if _, err := CleanScale(1920, 1080, scale); err == nil {
			t.Errorf("accepted %g", scale)
		}
	}
	if _, err := CleanScale(0, 1080, 1.6); err == nil {
		t.Error("accepted a disabled mode")
	}
}
