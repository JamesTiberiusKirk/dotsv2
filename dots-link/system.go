package main

import (
	"bytes"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// System files (udev rules, elogind hooks, runit services) can't be symlinked
// into the repo the way home dotfiles are: udev reads its rules before /home —
// a separate btrfs subvolume — is mounted, so the link would dangle and the
// rule would be silently skipped. So these are copied, root-owned.
//
// The diff is computed without sudo (every target here is world-readable);
// sudo is invoked only to apply, once per approved file.
type sysMap struct {
	src    string     // repo-relative dir
	dst    string     // absolute install dir
	enable bool       // runit: also link each sv dir into runsvdir/default
	reload [][]string // run once (as root) if anything in this mapping changed
}

var sysMaps = []sysMap{
	{src: "system/etc/udev/rules.d", dst: "/etc/udev/rules.d", reload: [][]string{
		{"udevadm", "control", "--reload"},
		{"udevadm", "trigger", "--subsystem-match=hidraw", "--subsystem-match=cpu", "--subsystem-match=pci", "--subsystem-match=usb"},
	}},
	{src: "system/etc/elogind/sleep.conf.d", dst: "/etc/elogind/sleep.conf.d"},
	// elogind runs sleep hooks out of /lib, not /etc
	{src: "system/etc/elogind/system-sleep", dst: "/lib/elogind/system-sleep"},
	{src: "system/etc/runit/sv", dst: "/etc/runit/sv", enable: true},
}

const runsvdirDefault = "/etc/runit/runsvdir/default"

type sysAction struct {
	enable bool // ln -sfn instead of a copy
	src    string
	dst    string
	mode   os.FileMode
	note   string
	mapIdx int
}

// computeSystemActions diffs the repo's system/ tree against the installed
// files. Read-only, no sudo.
func computeSystemActions(env *Env) ([]sysAction, error) {
	var acts []sysAction
	for i, m := range sysMaps {
		root := filepath.Join(env.DotsDir, m.src)
		err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return nil
			}
			rel, err := filepath.Rel(root, p)
			if err != nil {
				return nil
			}
			fi, err := d.Info()
			if err != nil {
				return nil
			}
			a := sysAction{src: p, dst: filepath.Join(m.dst, rel), mode: fi.Mode().Perm(), mapIdx: i}
			switch note := diffInstalled(p, a.dst, a.mode); note {
			case "":
			default:
				a.note = note
				acts = append(acts, a)
			}
			return nil
		})
		if err != nil && !os.IsNotExist(err) {
			return nil, fmt.Errorf("scan %s: %w", m.src, err)
		}
		if !m.enable {
			continue
		}
		ents, _ := os.ReadDir(root)
		for _, e := range ents {
			if !e.IsDir() {
				continue
			}
			link := filepath.Join(runsvdirDefault, e.Name())
			if _, err := os.Lstat(link); err == nil {
				continue
			}
			acts = append(acts, sysAction{enable: true, src: filepath.Join(m.dst, e.Name()), dst: link,
				note: "service not enabled", mapIdx: i})
		}
	}
	return acts, nil
}

// diffInstalled returns "" when the installed file already matches, otherwise a
// short reason. An unreadable target is reported as such — never guessed at.
func diffInstalled(src, dst string, mode os.FileMode) string {
	want, err := os.ReadFile(src)
	if err != nil {
		return "unreadable in repo"
	}
	fi, err := os.Stat(dst)
	if os.IsNotExist(err) {
		return "new"
	}
	if err != nil {
		return "unreadable — verify with sudo"
	}
	got, err := os.ReadFile(dst)
	if err != nil {
		return "unreadable — verify with sudo"
	}
	if !bytes.Equal(want, got) {
		return "changed"
	}
	if fi.Mode().Perm() != mode {
		return fmt.Sprintf("mode %04o → %04o", fi.Mode().Perm(), mode)
	}
	return ""
}

func renderSystemPlan(acts []sysAction) {
	if len(acts) == 0 {
		return
	}
	section("system files (root, copied):")
	for _, a := range acts {
		tag := "install"
		if a.enable {
			tag = "enable"
		}
		fmt.Println("  " + label(styAdd, tag, a.dst, a.note))
	}
}

// applySystem copies each approved file with sudo, then runs each affected
// mapping's reload hook once.
func applySystem(acts []sysAction, yes bool) error {
	if len(acts) == 0 {
		return nil
	}
	touched := map[int]bool{}
	for _, a := range acts {
		if !yes {
			what := fmt.Sprintf("install %s (%s)?", a.dst, a.note)
			if a.enable {
				what = fmt.Sprintf("enable service %s?", filepath.Base(a.dst))
			}
			ok, err := confirm(what)
			if err != nil {
				return err
			}
			if !ok {
				fmt.Println("  " + label(styMuted, "skipped", a.dst, ""))
				continue
			}
		}
		var cmd []string
		if a.enable {
			cmd = []string{"ln", "-sfn", a.src, a.dst}
		} else {
			cmd = []string{"install", "-D", "-m", fmt.Sprintf("%04o", a.mode), a.src, a.dst}
		}
		if err := sudoRun(cmd); err != nil {
			return err
		}
		fmt.Println("  " + label(styAdd, "installed", a.dst, ""))
		touched[a.mapIdx] = true
	}
	for i, m := range sysMaps {
		if !touched[i] {
			continue
		}
		for _, c := range m.reload {
			if err := sudoRun(c); err != nil {
				return err
			}
			fmt.Println("  " + label(styAdd, "ran", strings.Join(c, " "), ""))
		}
	}
	return nil
}

func sudoRun(args []string) error {
	cmd := exec.Command("sudo", args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("sudo %s: %w", strings.Join(args, " "), err)
	}
	return nil
}
