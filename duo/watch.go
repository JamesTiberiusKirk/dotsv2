package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

// The pogo-pin keyboard enumerates as USB 0b05:1bf2 when docked (covering
// eDP-2) and falls back to Bluetooth when lifted off.
const (
	kbVendor    = "0b05"
	kbProduct   = "1bf2" // docked, over the pogo pins
	kbProductBT = "1bf3" // same keyboard, lifted off and on bluetooth
)

func docked() bool {
	vendors, _ := filepath.Glob("/sys/bus/usb/devices/*/idVendor")
	for _, v := range vendors {
		if read(v) == kbVendor && read(filepath.Dir(v)+"/idProduct") == kbProduct {
			return true
		}
	}
	return false
}

func read(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

// watch applies the dock state, then polls for changes. udev would be the
// event-driven option, but `udevadm monitor` delivers nothing to an
// unprivileged process, and this costs one directory glob per second.
// Two independent signals, deliberately not merged: the screen follows physical
// placement (USB only), while the Fn layer follows the keyboard being reachable
// at all — it is just as usable over bluetooth, and was dead there before.
func watch() error {
	// At boot, duo watch starts on hyprland.start before USB has necessarily
	// finished enumerating the pogo-pin keyboard — a snapshot taken too early
	// reads undocked even when it's sitting docked, and since the state never
	// changes afterward the poll loop has nothing to correct. Wait for two
	// consecutive agreeing reads before trusting the initial state.
	dock := docked()
	for i := 0; i < 5; i++ {
		time.Sleep(500 * time.Millisecond)
		now := docked()
		if now == dock {
			break
		}
		dock = now
	}
	kbd := kbdPresent()
	logf("watch: start docked=%v keyboard=%v override=%q", dock, kbd, screenOverride())
	applyDock(dock)
	applyKbd(kbd)

	// hyprland.start also fires load-plugins.sh, which does `hyprctl reload` —
	// re-running the host config's "eDP-2 enabled" rule. That launch and this
	// one are both fire-and-forget, so there's no ordering guarantee between
	// "reload re-enables eDP-2" and "duo disables it": whichever finishes last
	// wins. Re-assert once more after the boot storm settles.
	time.AfterFunc(4*time.Second, func() { applyDock(dock) })
	orient, stable := orientNormal, 0
	ticks := 0

	for range time.Tick(time.Second) {
		if now := docked(); now != dock {
			dock = now
			// Moving the keyboard is a fresh statement of intent, so it retires
			// any manual override — otherwise a `duo screen on` from last week
			// silently outranks the dock state forever.
			if prev := screenOverride(); prev != "" {
				setScreenOverride("")
				logf("dock: docked=%v, clearing override=%q", dock, prev)
			}
			logf("dock: docked=%v", dock)
			applyDock(dock)
			// Being placed on or lifted off the panel resets the keyboard's Fn
			// layer even when the bluetooth link never drops, so there is no
			// appear/disappear transition to catch it — re-init here too.
			applyKbd(kbdPresent())
		}
		if now := kbdPresent(); now != kbd {
			kbd = now
			logf("keyboard: present=%v", kbd)
			applyKbd(kbd)
		}
		// Reacting to transitions alone is not enough: `hyprctl reload` re-applies
		// the host config's monitor rules and re-enables eDP-2 without the dock
		// state ever changing, so nothing above fires and the panel stays on.
		// theme-apply and SUPER+CTRL+C both reload, which is why this looked
		// random. Enforce the desired state rather than only reacting to changes.
		if ticks++; ticks%reassertEvery == 0 {
			reassert(dock)
		}
		if autoRotate() {
			orient, stable = followOrientation(orient, stable)
		}
	}
	return nil
}

// One `hyprctl monitors` fork per interval, against a display that stays wrong
// until the next pass — 5s keeps the cost off the idle loop while still being
// faster than noticing by eye.
const reassertEvery = 5

func reassert(dock bool) {
	// Read the latch once: deciding on one read and logging another produced a
	// line that contradicted the action it was describing.
	ov := screenOverride()
	want := !dock
	if ov != "" {
		want = ov == "on"
	}
	if edp2Active() == want {
		return
	}
	logf("reassert: eDP-2 %s -> %s (docked=%v override=%q)",
		onOff(!want), onOff(want), dock, ov)
	applyScreen(want)
}

func onOff(on bool) string {
	if on {
		return "on"
	}
	return "off"
}

func applyDock(docked bool) {
	if ov := screenOverride(); ov != "" {
		logf("dock: docked=%v but override=%q holds, leaving eDP-2 alone", docked, ov)
		return
	}
	applyScreen(!docked)
}

func applyScreen(on bool) {
	if err := screenCmd(onOff(on)); err != nil {
		logf("error: screen %s: %v", onOff(on), err)
		fmt.Fprintln(os.Stderr, "duo:", err)
	}
}

// applyKbd re-runs the init the keyboard forgets every time it re-appears, on
// either transport. Without it the Fn row emits nothing at all.
func applyKbd(present bool) {
	if !present {
		return
	}
	if err := kbdHandshake(); err != nil {
		fmt.Fprintln(os.Stderr, "duo: keyboard handshake:", err)
		return
	}
	kbdCmd("backlight", strconv.Itoa(kbdLevel()))
	// One reader at a time: applyKbd also runs on dock changes, and a second
	// reader on the same node would double every keypress.
	if readerRunning.CompareAndSwap(false, true) {
		go func() {
			defer readerRunning.Store(false)
			readKbdKeys()
		}()
	}
}

var readerRunning atomic.Bool

// followOrientation rotates only after the machine has agreed with itself for
// a couple of polls — a single sample flips while the lid is still moving.
func followOrientation(current orientation, stable int) (orientation, int) {
	now, err := detectOrientation()
	if err != nil || now == orientUnknown || now == current {
		return current, 0
	}
	if stable++; stable < 2 {
		return current, stable
	}
	if err := applyOrientation(now); err != nil {
		fmt.Fprintln(os.Stderr, "duo:", err)
		return current, 0
	}
	return now, 0
}
