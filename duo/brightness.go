package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

// eDP-1 is the source of truth for the single-number view (status, the OSD).
// Both are max 400 but every write scales via percent anyway, so unequal
// maxes would still work.
const (
	topBL = "/sys/class/backlight/intel_backlight"
	botBL = "/sys/class/backlight/card1-eDP-2-backlight"
)

// Locked together, the panels track one value and the brightness keys move
// both. Unlocked, each is driven on its own and the keys move only eDP-1 —
// the panel the "source of truth" comment above already names. The flag lives
// here rather than in the shell because the keys have to honour it too; split
// across Go and QML the two would drift apart.
func brightnessSync() bool {
	return stateRead("brightness-sync") != "off" // locked unless told otherwise
}

func brightnessCmd(action, val, target string) error {
	switch action {
	case "get":
		top, err := brightnessPct()
		if err != nil {
			return err
		}
		bot, err := pctOf(botBL)
		if err != nil {
			bot = -1 // bottom panel absent or disabled
		}
		fmt.Printf("%d %d\n", top, bot)
		return nil

	case "sync":
		switch val {
		case "on", "off":
			if err := stateWrite("brightness-sync", val); err != nil {
				return err
			}
			// re-locking: snap every monitor to the top panel's value, since
			// unlocked tweaks left them apart
			if val == "on" {
				pct, err := brightnessPct()
				if err != nil {
					return err
				}
				return applyAll(pct)
			}
			return nil
		case "", "status":
			fmt.Println(map[bool]string{true: "on", false: "off"}[brightnessSync()])
			return nil
		}
		return fmt.Errorf("brightness sync: want on|off|status, got %q", val)

	case "refresh":
		// the daemon owns the i2c bus: queue it there, never run ddcutil here
		return extSend("refresh")

	case "ext":
		// externals only, one "<connector> <pct>" line each — the shell reads
		// this on popout open to build the per-monitor sliders
		for _, m := range extListLive() {
			fmt.Printf("%s %d\n", m.conn, m.pct)
		}
		return nil
	}

	// Locked, every monitor holds the same value: keys step off eDP-1 and any
	// `set` (whatever the target) writes all of them — there are no per-monitor
	// values to edit while locked.
	if brightnessSync() {
		pct, err := brightnessPct()
		switch action {
		case "up":
			pct = bstep(pct, true)
		case "down":
			pct = bstep(pct, false)
		case "set":
			pct, err = strconv.Atoi(val)
			if err != nil {
				return fmt.Errorf("set: want a percent, got %q", val)
			}
		default:
			return fmt.Errorf("brightness: want up|down|get|set|sync|ext, got %q", action)
		}
		if err != nil {
			return err
		}
		if err := applyAll(min(max(pct, 1), 100)); err != nil {
			return err
		}
		if action != "set" {
			osdBrightness(min(max(pct, 1), 100))
		}
		return nil
	}

	// Unlocked with no explicit target, the keys follow the focused monitor.
	if target == "" {
		target = focusedTarget()
	}

	// A bare connector target (DP-1, HDMI-A-1) is an external monitor: its
	// current value and its coalescing both live in the daemon, so hand the
	// intent over rather than read-modify-write here.
	if isExternalTarget(target) {
		switch action {
		case "up":
			extStep(target, true)
		case "down":
			extStep(target, false)
		case "set":
			n, err := strconv.Atoi(val)
			if err != nil {
				return fmt.Errorf("set: want a percent, got %q", val)
			}
			extSetPct(target, n)
		default:
			return fmt.Errorf("brightness: want up|down|get|set|sync|ext, got %q", action)
		}
		return nil // external OSD: the daemon pings it after applying a step
	}

	pct, err := pctOfTarget(target)
	if err != nil {
		return err
	}

	switch action {
	case "up":
		pct = bstep(pct, true)
	case "down":
		pct = bstep(pct, false)
	case "set":
		pct, err = strconv.Atoi(val)
		if err != nil {
			return fmt.Errorf("set: want a percent, got %q", val)
		}
	default:
		return fmt.Errorf("brightness: want up|down|get|set|sync|ext, got %q", action)
	}

	pct = min(max(pct, 1), 100)
	if target == "all" {
		if err := applyAll(pct); err != nil {
			return err
		}
	} else if err := apply(pct, target); err != nil {
		return err
	}
	// Only the keys get the OSD. `set` is the slider path: pinging per drag
	// frame would strobe the OSD over the panel being dragged.
	if action != "set" {
		osdBrightness(pct)
	}
	return nil
}

// osdBrightness pops the OSD at pct. The OSD shows exactly what it is told:
// it cannot read an external's value itself. Start+reap, so the daemon's
// worker never waits on qs.
func osdBrightness(pct int) {
	cmd := exec.Command("qs", "ipc", "call", "osd", "brightness", strconv.Itoa(pct))
	if cmd.Start() == nil {
		go cmd.Wait()
	}
}

// bstep is the shared key-step feel: 5% steps, 1% steps near the bottom, never
// fully off. Internal panels and externals both step through it so the two feel
// identical under the brightness keys.
func bstep(pct int, up bool) int {
	if up {
		if pct < 5 {
			return pct + 1
		}
		return pct + 5
	}
	if pct <= 5 {
		return pct - 1
	}
	return pct - 5
}

// applyAll is the locked write: both internal panels via sysfs (instant) and
// every external via the daemon. Internal failure is fatal (it is the primary
// screen); externals are fire-and-forget.
func applyAll(pct int) error {
	if err := apply(pct, "both"); err != nil {
		return err
	}
	for _, conn := range extConnectors() {
		extSetPct(conn, pct)
	}
	return nil
}

// isExternalTarget reports whether target names a DDC external rather than an
// internal panel or the top/bottom/both/all keywords.
func isExternalTarget(target string) bool {
	switch target {
	case "top", "bottom", "both", "all", "":
		return false
	}
	for _, c := range extConnectors() {
		if c == target {
			return true
		}
	}
	return false
}

// focusedTarget maps the Hyprland-focused monitor to a brightness target, so
// the keys move the screen the user is actually on when the panels are
// unlocked. eDP-1/eDP-2 are the internal panels; anything else is an external
// connector handed to the daemon.
func focusedTarget() string {
	switch m := focusedMonitor(); m {
	case "eDP-1", "":
		return "top"
	case "eDP-2":
		return "bottom"
	default:
		return m
	}
}

// apply writes pct to the requested panels. The bottom is best-effort even
// when explicitly targeted: it is absent on other hosts and its sysfs node
// can vanish with the output disabled.
func apply(pct int, target string) error {
	switch target {
	case "top":
		return writePct(topBL, pct)
	case "bottom":
		return writePct(botBL, pct)
	case "both":
		if err := writePct(topBL, pct); err != nil {
			return err
		}
		writePct(botBL, pct)
		return nil
	}
	return fmt.Errorf("brightness: want top|bottom|both, got %q", target)
}

func pctOfTarget(target string) (int, error) {
	if target == "bottom" {
		return pctOf(botBL)
	}
	return brightnessPct() // top, and "both" steps off eDP-1
}

func brightnessPct() (int, error) { return pctOf(topBL) }

func pctOf(dev string) (int, error) {
	cur, err := readInt(dev + "/brightness")
	if err != nil {
		return 0, err
	}
	maxB, err := readInt(dev + "/max_brightness")
	if err != nil {
		return 0, err
	}
	return (cur*100 + maxB/2) / maxB, nil
}

func writePct(dev string, pct int) error {
	maxB, err := readInt(dev + "/max_brightness")
	if err != nil {
		return err
	}
	v := strconv.Itoa(maxB * pct / 100)
	return os.WriteFile(filepath.Join(dev, "brightness"), []byte(v), 0644)
}

func readInt(path string) (int, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	return strconv.Atoi(strings.TrimSpace(string(b)))
}
