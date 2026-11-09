package display

import (
	"fmt"
	"math"
)

// CleanScale rounds a scale up to a value the mode can represent in
// Hyprland's 1/120 steps, following Omarchy's display scale controls. At the
// upper limit it uses the highest representable scale at or below 4.
func CleanScale(width, height int, scale float64) (float64, error) {
	if width <= 0 || height <= 0 || math.IsNaN(scale) || math.IsInf(scale, 0) || scale < 1 || scale > 4 {
		return 0, fmt.Errorf("scale needs an active mode and a value from 1 to 4")
	}
	a, b := width*120, height*120
	for b != 0 {
		a, b = b, a%b
	}
	k := int(math.Round(scale * 120))
	upper := min(a, 4*120)
	if k > upper {
		k = upper
	}
	for k <= upper && a%k != 0 {
		k++
	}
	if k > upper {
		k = upper
		for a%k != 0 {
			k--
		}
	}
	return float64(k) / 120, nil
}

// StepScale moves through Omarchy's scale presets, including 1.6, clamping
// at each end. Presets that round to the same effective scale count once.
func StepScale(m Monitor, direction int) (float64, error) {
	var choices []float64
	for _, preset := range []float64{1, 1.25, 1.6, 2, 3, 4} {
		scale, err := CleanScale(m.Width, m.Height, preset)
		if err != nil {
			return 0, err
		}
		if len(choices) == 0 || math.Abs(choices[len(choices)-1]-scale) > 0.0001 {
			choices = append(choices, scale)
		}
	}
	best := 0
	for i := range choices {
		if math.Abs(choices[i]-m.Scale) < math.Abs(choices[best]-m.Scale) {
			best = i
		}
	}
	next := best + direction
	if next < 0 {
		next = 0
	} else if next >= len(choices) {
		next = len(choices) - 1
	}
	return choices[next], nil
}
