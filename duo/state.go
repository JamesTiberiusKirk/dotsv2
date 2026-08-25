package main

import (
	"os"
	"path/filepath"
	"strings"
)

// Persisted session preferences (autorotate, brightness sync). Deliberately
// NOT $XDG_RUNTIME_DIR: that is wiped on every boot, which silently reset
// autorotate to off each time — a user preference has to outlive the session.
func statePath(name string) string {
	dir := os.Getenv("XDG_STATE_HOME")
	if dir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return filepath.Join(os.TempDir(), "duo-"+name)
		}
		dir = filepath.Join(home, ".local", "state")
	}
	dir = filepath.Join(dir, "duo")
	os.MkdirAll(dir, 0755) // best-effort; the write below reports the real error
	return filepath.Join(dir, name)
}

func stateRead(name string) string {
	b, err := os.ReadFile(statePath(name))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func stateWrite(name, val string) error {
	return os.WriteFile(statePath(name), []byte(val), 0644)
}

// Manual override of the bottom screen: "on", "off", or "" for none.
//
// Without it the re-assert in watch() would undo a deliberate `duo screen on`
// within a second of you typing it. It is cleared whenever the keyboard docks
// or undocks — physically moving the thing is a fresh statement of intent, and
// a latch you cannot remember setting is worse than no latch.
func screenOverride() string {
	switch v := stateRead("screen-override"); v {
	case "on", "off":
		return v
	}
	return ""
}

func setScreenOverride(v string) {
	if v == "" {
		os.Remove(statePath("screen-override"))
		return
	}
	stateWrite("screen-override", v)
}
