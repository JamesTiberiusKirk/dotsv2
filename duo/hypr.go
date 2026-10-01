package main

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

// Screen geometry lives in ~/.config/hypr/monitors.lua, not here. duo records
// what it decided — bottom panel power (screen-override), mirror mode and
// rotation (runtime files) — then re-runs that file, the same one every config
// reload runs. A reload therefore lands on duo's state instead of undoing it,
// which is what the old 5s re-assert loop existed to paper over.
const monitorsLua = `dofile(os.getenv("HOME").."/.config/hypr/monitors.lua")`

func applyMonitors() error { return hyprEval(monitorsLua) }

func hyprEval(code string) error {
	out, err := exec.Command("hyprctl", "eval", code+` return ""`).CombinedOutput()
	if err != nil || strings.HasPrefix(string(out), "error") {
		return fmt.Errorf("hyprctl eval %q: %v %s", code, err, out)
	}
	return nil
}

// screenLatched records the intent, then applies it: monitors.lua reads the
// latch, so the state file is the action.
func screenLatched(action string) error {
	switch action {
	case "status":
		// Mirroring counts as on: the panel is lit and drawing power, which is
		// the whole reason anything asks.
		fmt.Println(onOff(edp2Active()))
		return nil
	case "auto":
		// Without this the only way out of a latch is physically moving the
		// keyboard, which is a poor answer to "put it back on automatic".
		setScreenOverride("")
		logf("manual: screen auto -> override cleared")
		return applyMonitors()
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
	if err := applyMonitors(); err != nil {
		setScreenOverride(prev) // never leave a latch behind for a move that failed
		return err
	}
	logf("manual: screen %s -> override=%s", action, want)
	return nil
}

// layoutCmd picks how the two panels relate. The two-panel presets latch the
// bottom panel on and top-only latches it off — the same latch `duo screen`
// uses, so the dock watcher and a reload both respect the choice. A preset
// also resets rotation: the mirror presets have no rotated form.
func layoutCmd(preset string) error {
	mode, power := "stacked", "on"
	switch preset {
	case "stacked", "mirror", "mirror-flip":
		mode = preset
	case "top-only":
		power = "off"
	default:
		return fmt.Errorf("layout: want stacked|mirror|mirror-flip|top-only, got %q", preset)
	}
	if err := runtimeWrite("mode", mode); err != nil {
		return err
	}
	if err := runtimeWrite("rotation", string(orientNormal)); err != nil {
		return err
	}
	return screenLatched(power)
}

// focusedMonitor is the name of the monitor holding Hyprland focus (the one the
// pointer/keyboard is on), or "" if that can't be read. Drives which screen the
// brightness keys move when the panels are unlocked.
func focusedMonitor() string {
	out, err := exec.Command("hyprctl", "monitors", "-j").Output()
	if err != nil {
		return ""
	}
	var mons []struct {
		Name    string `json:"name"`
		Focused bool   `json:"focused"`
	}
	if json.Unmarshal(out, &mons) != nil {
		return ""
	}
	for _, m := range mons {
		if m.Focused {
			return m.Name
		}
	}
	return ""
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
