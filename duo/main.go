// duo — Zenbook Duo (UX8406CA / binstar) session utility for Hyprland.
// Session-scoped: started by hypr hosts/binstar.lua, talks to the compositor
// via `hyprctl eval` (the lua parser rejects `hyprctl keyword`). No root: the
// backlight writes need the video group (install.sh adds it).
//
//	duo watch                        dock/undock daemon (eDP-2 off when keyboard docks)
//	duo screen on|off|toggle|status  manual bottom-screen control
//	duo brightness up|down|get|set N [top|bottom] | sync on|off
//	duo layout stacked|mirror|mirror-flip|top-only
//	duo status
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	var err error
	switch os.Args[1] {
	case "watch":
		err = watch()
	case "screen":
		err = screenLatched(arg(2))
	case "brightness":
		err = brightnessCmd(arg(2), arg(3), arg(4))
	case "layout":
		err = layoutCmd(arg(2))
	case "kbd":
		err = kbdCmd(arg(2), arg(3))
	case "orientation":
		err = orientationCmd()
	case "rotate":
		err = rotateCmd(arg(2))
	case "autorotate":
		err = autoRotateCmd(arg(2))
	case "status":
		err = status()
	default:
		usage()
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "duo:", err)
		os.Exit(1)
	}
}

func arg(i int) string {
	if len(os.Args) > i {
		return os.Args[i]
	}
	return ""
}

func usage() {
	fmt.Fprintln(os.Stderr, `usage: duo <command>
  watch                          run the dock/undock daemon
  screen on|off|toggle|status    bottom screen (eDP-2); on/off/toggle latch an
                                 override, cleared next time the keyboard moves
  screen auto                    drop the override, follow the keyboard again
  brightness up|down|set N [top|bottom]
  brightness get                 "<top> <bottom>" percent, bottom -1 if absent
  brightness sync on|off|status  lock the panels together (keys included)
  layout stacked|mirror|mirror-flip|top-only
  kbd handshake|backlight N      enable the Fn layer / set keyboard backlight (0-3)
  orientation                    accelerometer + hinge angles + detected orientation
  rotate auto|normal|left-up|right-up|bottom-up
  autorotate on|off|status       follow the accelerometer (off by default)
  status`)
	os.Exit(2)
}

func status() error {
	dock := "detached"
	if docked() {
		dock = "docked"
	}
	screen := "off"
	if edp2Active() {
		screen = "on"
	}
	top, err := brightnessPct()
	if err != nil {
		return err
	}
	bot, err := pctOf(botBL)
	if err != nil {
		bot = -1
	}
	override := screenOverride()
	if override == "" {
		override = "none (follows the keyboard)"
	}
	fmt.Printf("keyboard:   %s\nbottom:     %s\noverride:   %s\nbrightness: %d%% / %d%%\nsync:       %s\nautorotate: %s\nlog:        %s\n",
		dock, screen, override, top, bot,
		map[bool]string{true: "on", false: "off"}[brightnessSync()],
		map[bool]string{true: "on", false: "off"}[autoRotate()],
		logPath())
	return nil
}
