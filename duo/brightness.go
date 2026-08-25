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
			// re-locking with the panels apart: snap to eDP-1 rather than
			// leave a lock that claims they match when they don't
			if val == "on" {
				pct, err := brightnessPct()
				if err != nil {
					return err
				}
				return apply(pct, "both")
			}
			return nil
		case "", "status":
			fmt.Println(map[bool]string{true: "on", false: "off"}[brightnessSync()])
			return nil
		}
		return fmt.Errorf("brightness sync: want on|off|status, got %q", val)
	}

	// up/down/set all resolve to "write this percent to these panels"
	if target == "" {
		if brightnessSync() {
			target = "both"
		} else {
			target = "top"
		}
	} else if brightnessSync() {
		target = "both" // the lock outranks an explicit target
	}

	pct, err := pctOfTarget(target)
	if err != nil {
		return err
	}

	switch action {
	// 5% steps, 1% steps near the bottom, never fully off — same feel as the
	// old brightnessctl bind.
	case "up":
		if pct < 5 {
			pct++
		} else {
			pct += 5
		}
	case "down":
		if pct <= 5 {
			pct--
		} else {
			pct -= 5
		}
	case "set":
		pct, err = strconv.Atoi(val)
		if err != nil {
			return fmt.Errorf("set: want a percent, got %q", val)
		}
	default:
		return fmt.Errorf("brightness: want up|down|get|set|sync, got %q", action)
	}

	if err := apply(min(max(pct, 1), 100), target); err != nil {
		return err
	}
	// Only the keys get the OSD. `set` is the slider path: pinging per drag
	// frame would strobe the OSD over the panel being dragged.
	if action != "set" {
		exec.Command("qs", "ipc", "call", "osd", "brightness").Run()
	}
	return nil
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
