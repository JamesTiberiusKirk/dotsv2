package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
)

// The state file quickshell watches instead of polling. Before it, the shell
// forked a shell every 2-5s per question (backlight, dock, keyboard level,
// bottom screen, autorotate) and ran ddcutil behind the daemon's back on panel
// open. Now `duo watch` is the one that looks, and it rewrites this file only
// when something differs; Sys.qml reacts to the change.
//
// One "key value..." line per fact:
//
//	docked on|off
//	kbdlevel 0-3
//	bottom on|off          eDP-2 lit (mirroring counts), from the kernel
//	autorotate on|off
//	sync on|off            brightness lock-together
//	group <main> <min>     locked only: brightest and dimmest lit monitor
//	bl <device> <pct>      internal backlight, primary panel first
//	ext <connector> <pct>  external DDC monitor, as last applied/read
//	refreshed N            bumped by each re-detect + re-read of the externals
//
// Everything here is a file read: no hyprctl, no ddcutil, so the 1s tick can
// call it for free. Changes made by a separate `duo` CLI process show up on
// that tick, or at once when the CLI pokes the daemon (notifyDaemon).

var (
	pubMu   sync.Mutex
	pubLast string
)

func statePublishPath() string { return runtimePath("state") }

func publish() {
	var b strings.Builder
	fmt.Fprintf(&b, "docked %s\n", onOff(docked()))
	fmt.Fprintf(&b, "kbdlevel %d\n", kbdLevel())
	// the kernel's view, not Hyprland's: no fork, and it is the truth
	fmt.Fprintf(&b, "bottom %s\n", onOff(read("/sys/class/drm/card1-eDP-2/enabled") == "enabled"))
	fmt.Fprintf(&b, "autorotate %s\n", onOff(autoRotate()))
	fmt.Fprintf(&b, "sync %s\n", onOff(brightnessSync()))
	if brightnessSync() {
		if main, mn, ok := groupMain(); ok {
			fmt.Fprintf(&b, "group %d %d\n", main, mn)
		}
	}
	for _, dev := range []string{topBL, botBL} {
		if pct, err := pctOf(dev); err == nil {
			fmt.Fprintf(&b, "bl %s %d\n", filepath.Base(dev), pct)
		}
	}
	if extSrv != nil {
		vals, n := extSrv.values()
		fmt.Fprintf(&b, "refreshed %d\n", n)
		conns := make([]string, 0, len(vals))
		for c := range vals {
			conns = append(conns, c)
		}
		sort.Strings(conns)
		for _, c := range conns {
			fmt.Fprintf(&b, "ext %s %d\n", c, vals[c])
		}
	}

	pubMu.Lock()
	defer pubMu.Unlock()
	if b.String() == pubLast {
		return
	}
	// written in place, not renamed: the shell's file watch follows the inode
	if err := os.WriteFile(statePublishPath(), []byte(b.String()), 0644); err != nil {
		logf("publish: %v", err)
		return
	}
	pubLast = b.String()
}

// notifyDaemon asks a running `duo watch` to publish now, so a CLI change
// (keys, slider, menu) reaches the bar at once instead of on the next tick.
// No daemon: nothing is watching the file either, so nothing to do.
func notifyDaemon() { extSend("publish") }

// externalsConnected is the sorted list of connected non-eDP connectors, read
// from the kernel. The watch loop compares it each tick: a change means a
// monitor came or went, and the DDC map has to be re-detected.
func externalsConnected() string {
	dirs, _ := filepath.Glob("/sys/class/drm/card*-*")
	var out []string
	for _, d := range dirs {
		name := stripCard(filepath.Base(d))
		if strings.HasPrefix(name, "eDP") || read(d+"/status") != "connected" {
			continue
		}
		out = append(out, name)
	}
	sort.Strings(out)
	return strings.Join(out, ",")
}
