package main

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

// Monitor rules for the two stacked 2880x1800@120 panels at scale 1.5
// (positions are in logical pixels: 1800/1.5 = 1200).
//
// disabled = false is not redundant: once an output has been disabled, a rule
// that only sets mode/position/scale is accepted but leaves it off. mirror =
// "none" is the same trap one level down — a rule that omits mirror leaves a
// previously set one in place, so "layout stacked" out of "layout mirror"
// silently did nothing at all.
//
// transform 2 is 180°: the tent presets flip the panel facing away from you.
const (
	edp1Rule    = `hl.monitor({ output = "eDP-1", mode = "2880x1800@120", position = "0x0", scale = 1.5, transform = 0, mirror = "none", disabled = false })`
	edp1Flipped = `hl.monitor({ output = "eDP-1", mode = "2880x1800@120", position = "0x0", scale = 1.5, transform = 2, mirror = "none", disabled = false })`
	edp2Rule    = `hl.monitor({ output = "eDP-2", mode = "2880x1800@120", position = "0x1200", scale = 1.5, transform = 0, mirror = "none", disabled = false })`
	edp2Off     = `hl.monitor({ output = "eDP-2", disabled = true })`
	edp2Mir     = `hl.monitor({ output = "eDP-2", transform = 0, mirror = "eDP-1", disabled = false })`
)

func hyprEval(code string) error {
	out, err := exec.Command("hyprctl", "eval", code+` return ""`).CombinedOutput()
	if err != nil || strings.HasPrefix(string(out), "error") {
		return fmt.Errorf("hyprctl eval %q: %v %s", code, err, out)
	}
	return nil
}

// screenLatched is the user-facing path: it records the intent *before* acting,
// so a re-assert tick landing in between cannot see an un-latched panel and
// undo the very change being made. screenCmd stays unlatched because the watch
// loop uses it as its actuator and must not claim the user asked.
func screenLatched(action string) error {
	if action == "status" {
		return screenCmd(action)
	}
	// Without this the only way out of a latch is physically moving the
	// keyboard, which is a poor answer to "put it back on automatic".
	if action == "auto" {
		setScreenOverride("")
		logf("manual: screen auto -> override cleared")
		return screenCmd(onOff(!docked()))
	}
	want := action
	if action == "toggle" {
		want = onOff(!edp2Active())
	}
	if want != "on" && want != "off" {
		return fmt.Errorf("screen: want on|off|toggle|auto|status, got %q", action)
	}
	prev := screenOverride()
	setScreenOverride(want)
	if err := screenCmd(want); err != nil {
		setScreenOverride(prev) // never leave a latch behind for a move that failed
		return err
	}
	logf("manual: screen %s -> override=%s", action, want)
	return nil
}

func screenCmd(action string) error {
	switch action {
	case "on":
		return hyprEval(edp2Rule)
	case "off":
		return hyprEval(edp2Off)
	case "toggle":
		if edp2Active() {
			return hyprEval(edp2Off)
		}
		return hyprEval(edp2Rule)
	case "status":
		// Mirroring counts as on: the panel is lit and drawing power, which is
		// the whole reason anything asks.
		fmt.Println(map[bool]string{true: "on", false: "off"}[edp2Active()])
		return nil
	}
	return fmt.Errorf("screen: want on|off|toggle|auto|status, got %q", action)
}

func layoutCmd(preset string) error {
	switch preset {
	case "stacked":
		if err := hyprEval(edp1Rule); err != nil {
			return err
		}
		return hyprEval(edp2Rule)
	case "mirror":
		if err := hyprEval(edp1Rule); err != nil {
			return err
		}
		return hyprEval(edp2Mir)
	case "mirror-flip":
		// Tent/share mode: both panels show the same thing and the top is
		// upside down, for whoever is sitting on the other side of the machine.
		if err := hyprEval(edp1Flipped); err != nil {
			return err
		}
		return hyprEval(edp2Mir)
	case "top-only":
		if err := hyprEval(edp1Rule); err != nil {
			return err
		}
		return hyprEval(edp2Off)
	}
	return fmt.Errorf("layout: want stacked|mirror|mirror-flip|top-only, got %q", preset)
}

// edp2Active reports whether eDP-2 is currently an enabled output.
//
// `monitors all`, not `monitors`: a mirrored output is absent from the plain
// list even though it is very much on, which made status report "bottom: off"
// while eDP-2 was mirroring.
func edp2Active() bool {
	out, err := exec.Command("hyprctl", "monitors", "all", "-j").Output()
	if err != nil {
		return false
	}
	var mons []struct {
		Name     string `json:"name"`
		Disabled bool   `json:"disabled"`
	}
	if json.Unmarshal(out, &mons) != nil {
		return false
	}
	for _, m := range mons {
		if m.Name == "eDP-2" {
			return !m.Disabled
		}
	}
	return false
}
