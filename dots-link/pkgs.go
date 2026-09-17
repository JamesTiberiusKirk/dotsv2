package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// Package lists this host converges against: the shared pair plus its own.
func pkgLists(host string) []string {
	return []string{
		".config/installed_packages/common.txt",
		".config/installed_packages/fonts.txt",
		".config/installed_packages/" + host + ".txt",
	}
}

// The same idea for things no repo carries: one directory under pkgbuilds/ per
// entry, built with makepkg. Kept in their own lists because they are installed
// by a different command, not because they are a different kind of package —
// pacman -Qq sees both once they are in.
func buildLists(host string) []string {
	return []string{
		".config/installed_packages/pkgbuilds-common.txt",
		".config/installed_packages/pkgbuilds-" + host + ".txt",
	}
}

func parsePkgs(content string) map[string]bool {
	set := map[string]bool{}
	for _, l := range strings.Split(content, "\n") {
		l = strings.TrimSpace(l)
		if l != "" && !strings.HasPrefix(l, "#") {
			set[l] = true
		}
	}
	return set
}

// listedPackages returns every package named in this host's lists, read from
// the working tree so uncommitted list edits count. Full set, not a merge
// delta: a list entry missing locally is offered on every run until installed,
// whichever commit added it and whoever declined it last time. Saying no just
// skips it.
func listedPackages(dir, host string) []string {
	return readLists(dir, pkgLists(host))
}

// Local PKGBUILD names. Each must match a directory under pkgbuilds/ *and* the
// pkgname inside it — the name is what pacman is asked about afterwards.
func listedBuilds(dir, host string) []string {
	return readLists(dir, buildLists(host))
}

func readLists(dir string, files []string) []string {
	set := map[string]bool{}
	for _, f := range files {
		c, err := os.ReadFile(filepath.Join(dir, f))
		if err != nil {
			continue
		}
		for p := range parsePkgs(string(c)) {
			set[p] = true
		}
	}
	out := make([]string, 0, len(set))
	for p := range set {
		out = append(out, p)
	}
	sort.Strings(out)
	return out
}

// filterInstalled drops packages the local pacman db already has.
// No pacman (mac) -> nothing to converge.
func filterInstalled(pkgs []string) []string {
	out, err := exec.Command("pacman", "-Qq").Output()
	if err != nil {
		return nil
	}
	installed := parsePkgs(string(out))
	kept := pkgs[:0:0]
	for _, p := range pkgs {
		if !installed[p] {
			kept = append(kept, p)
		}
	}
	return kept
}

// pkgWork is everything a converge still has to install, split by the command
// that installs it. Carried as one value so the three call sites in sync.go
// cannot pick up one half and drop the other.
type pkgWork struct {
	dir    string
	pkgs   []string
	builds []string
}

func (w pkgWork) empty() bool { return len(w.pkgs) == 0 && len(w.builds) == 0 }

func missingPkgs(dir, host string) pkgWork {
	return pkgWork{
		dir:    dir,
		pkgs:   filterInstalled(listedPackages(dir, host)),
		builds: filterInstalled(listedBuilds(dir, host)),
	}
}

func renderPkgPlan(w pkgWork) {
	if w.empty() {
		return
	}
	section("packages listed but not installed:")
	for _, p := range w.builds {
		fmt.Println("  " + label(styAdd, "build", p, "pkgbuilds/"+p))
	}
	for _, p := range w.pkgs {
		fmt.Println("  " + label(styAdd, "install", p, ""))
	}
}

// installPackages offers the missing packages to yay. Interactive only: under
// --yes (install.sh) it is skipped — the converge's own package pass covers
// the same lists moments later.
func installPackages(w pkgWork, yes bool) error {
	if w.empty() {
		return nil
	}
	if yes {
		info("packages skipped under --yes — install.sh's package pass handles them")
		return nil
	}
	n := len(w.pkgs) + len(w.builds)
	ok, err := confirm(fmt.Sprintf("install %d missing package(s)?", n))
	if err != nil {
		return err
	}
	if !ok {
		info("packages skipped")
		return nil
	}
	// Local builds first: a repo package may well depend on one.
	if err := runBuilds(w); err != nil {
		return err
	}
	if len(w.pkgs) == 0 {
		return nil
	}
	if _, err := exec.LookPath("yay"); err != nil {
		info("yay not found — install by hand: %s", strings.Join(w.pkgs, " "))
		return nil
	}
	cmd := exec.Command("yay", append([]string{"-S", "--needed"}, w.pkgs...)...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("yay: %w", err)
	}
	return nil
}

// makepkg per listed PKGBUILD, in its own directory. One failing build does not
// stop the rest: they are independent, and the next run offers it again anyway.
func runBuilds(w pkgWork) error {
	if _, err := exec.LookPath("makepkg"); err != nil && len(w.builds) > 0 {
		info("makepkg not found — skipping local builds: %s", strings.Join(w.builds, " "))
		return nil
	}
	for _, b := range w.builds {
		d := filepath.Join(w.dir, "pkgbuilds", b)
		if _, err := os.Stat(filepath.Join(d, "PKGBUILD")); err != nil {
			warnLine("!! no pkgbuilds/%s/PKGBUILD — listed but nothing to build", b)
			continue
		}
		fmt.Println("  " + label(styAdd, "building", b, ""))
		cmd := exec.Command("makepkg", "-si", "--needed", "--noconfirm")
		cmd.Dir = d
		cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
		if err := cmd.Run(); err != nil {
			warnLine("!! makepkg %s failed: %v", b, err)
		}
	}
	return nil
}
