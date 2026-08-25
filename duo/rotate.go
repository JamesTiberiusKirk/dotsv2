package main

import (
	"fmt"
)

// Rotating the machine doesn't just transform each panel — it changes how they
// sit relative to each other. Stacked in landscape (eDP-1 above eDP-2), they
// end up side by side in portrait, and which one is on the left depends on
// which way you turned it.
//
// Logical sizes at scale 1.5: landscape 1920x1200 per panel, portrait 1200x1920.
//
// If a rotation comes out mirrored or with the panels the wrong way round, the
// fix is here: swap the transform numbers or the two positions for that entry.
type layout struct {
	transform int
	edp1Pos   string
	edp2Pos   string
}

var layouts = map[orientation]layout{
	orientNormal:   {0, "0x0", "0x1200"}, // eDP-1 on top
	orientBottomUp: {2, "0x1200", "0x0"}, // upside down: eDP-1 below
	// Sides as observed on the machine, not as reasoned about: with the left
	// edge up, eDP-1 (the panel that was on top) lands on the RIGHT.
	orientLeftUp:  {1, "1200x0", "0x0"}, // portrait, eDP-1 on the right
	orientRightUp: {3, "0x0", "1200x0"}, // portrait, eDP-1 on the left
}

func rotateCmd(arg string) error {
	var o orientation
	switch arg {
	case "auto":
		d, err := detectOrientation()
		if err != nil {
			return err
		}
		if d == orientUnknown {
			return fmt.Errorf("rotate: machine is flat, orientation undetermined")
		}
		o = d
	case "normal", "left-up", "right-up", "bottom-up":
		o = orientation(arg)
	default:
		return fmt.Errorf("rotate: want auto|normal|left-up|right-up|bottom-up, got %q", arg)
	}
	return applyOrientation(o)
}

func applyOrientation(o orientation) error {
	l, ok := layouts[o]
	if !ok {
		return fmt.Errorf("rotate: no layout for %q", o)
	}
	// Both panels in one eval: applied one at a time, there is an instant where
	// one is rotated and the other is not, and their boxes overlap — which
	// Hyprland notices and complains about on screen.
	//
	// Portrait swaps each panel's logical size (1920x1200 -> 1200x1920), so the
	// mode string stays the same and only transform and positions move.
	return hyprEval(fmt.Sprintf(
		`hl.monitor({ output = "eDP-1", mode = "2880x1800@120", position = %q, scale = 1.5, transform = %d, mirror = "none", disabled = false }) `+
			`hl.monitor({ output = "eDP-2", mode = "2880x1800@120", position = %q, scale = 1.5, transform = %d, mirror = "none", disabled = false })`,
		l.edp1Pos, l.transform, l.edp2Pos, l.transform))
}

// Auto-rotate is opt-in and remembered across runs: a machine that reorients
// itself unasked while you are typing is worse than one that never does.
func autoRotate() bool {
	return stateRead("autorotate") == "on"
}

func autoRotateCmd(arg string) error {
	switch arg {
	case "on", "off":
		return stateWrite("autorotate", arg)
	case "", "status":
		fmt.Println(map[bool]string{true: "on", false: "off"}[autoRotate()])
		return nil
	}
	return fmt.Errorf("autorotate: want on|off|status, got %q", arg)
}
