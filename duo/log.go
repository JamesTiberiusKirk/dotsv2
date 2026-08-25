package main

import (
	"fmt"
	"os"
	"time"
)

// duo watch is a long-lived session daemon that turns a display on and off by
// itself. Without a trace of why, a spurious flip is unfalsifiable — the
// reason this file exists is that eDP-2 kept coming on with "no pattern", and
// the pattern turned out to be `hyprctl reload` (theme-apply, SUPER+CTRL+C),
// which nothing recorded.
//
// Not socklog: that is for runit services, and duo is session-scoped, started
// by Hyprland. Not the journal: Artix has no systemd. So, a file.
const logMaxBytes = 256 * 1024

func logPath() string { return statePath("log") }

// logf appends one timestamped line. Best-effort throughout: a daemon that
// manages your display must not die because its log is unwritable.
func logf(format string, args ...any) {
	line := time.Now().Format("2006-01-02 15:04:05") + "  " + fmt.Sprintf(format, args...) + "\n"

	path := logPath()
	// Truncate rather than rotate: there is exactly one reader (you, with
	// tail), and keeping a .1 around doubles the code for no benefit.
	if fi, err := os.Stat(path); err == nil && fi.Size() > logMaxBytes {
		os.Remove(path)
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	f.WriteString(line)
}
