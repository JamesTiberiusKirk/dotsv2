package main

import (
	"fmt"
)

// Rotating the machine turns the stack of panels, not just each panel: stacked
// in landscape, side by side in portrait. The position table lives in
// ~/.config/hypr/monitors.lua; duo only records which way is up.

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
	switch o {
	case orientNormal, orientLeftUp, orientRightUp, orientBottomUp:
	default:
		return fmt.Errorf("rotate: no layout for %q", o)
	}
	// a mirror preset has no rotated form; turning the machine means stacked
	if err := runtimeWrite("mode", "stacked"); err != nil {
		return err
	}
	if err := runtimeWrite("rotation", string(o)); err != nil {
		return err
	}
	return applyMonitors()
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
