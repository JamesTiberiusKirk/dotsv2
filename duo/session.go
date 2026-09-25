package main

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"
)

// One `duo watch` per Hyprland session, and none that outlive their session.
//
// Both halves come from the same incident: a `duo watch` started on Sep 22 was
// still running on Sep 25, three days after its Hyprland had exited. It could
// not reach its dead socket, so every 5s reassert failed and spammed the log —
// but it shared `screen-override` and the log file with the live instance, so
// two daemons were reading one latch and writing one log.
//
// The lock lives *inside* the session's runtime directory, which Hyprland
// removes when it exits. That is the whole trick: a stale lock cannot outlive
// the session it belongs to, so a fresh session never finds one held by a
// corpse, and no pid-file staleness check is needed.

func sessionDir() (string, error) {
	sig := os.Getenv("HYPRLAND_INSTANCE_SIGNATURE")
	if sig == "" {
		return "", fmt.Errorf("HYPRLAND_INSTANCE_SIGNATURE is unset — not in a Hyprland session")
	}
	rt := os.Getenv("XDG_RUNTIME_DIR")
	if rt == "" {
		rt = fmt.Sprintf("/run/user/%d", os.Getuid())
	}
	return filepath.Join(rt, "hypr", sig), nil
}

// sessionAlive reports whether the compositor we were started by is still there.
// Checked on a tick, not just at startup: the zombie existed because nothing
// ever re-checked.
func sessionAlive() bool {
	dir, err := sessionDir()
	if err != nil {
		return false
	}
	_, err = os.Stat(filepath.Join(dir, ".socket.sock"))
	return err == nil
}

// lockSession takes an exclusive, non-blocking flock. The returned file must be
// held open for the process's lifetime — closing it releases the lock, so the
// caller keeps the reference even though it never reads from it.
func lockSession() (*os.File, error) {
	dir, err := sessionDir()
	if err != nil {
		return nil, err
	}
	if !sessionAlive() {
		return nil, fmt.Errorf("session socket is gone, refusing to start")
	}
	f, err := os.OpenFile(filepath.Join(dir, ".duo-watch.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		return nil, fmt.Errorf("another duo watch already holds this session")
	}
	return f, nil
}
