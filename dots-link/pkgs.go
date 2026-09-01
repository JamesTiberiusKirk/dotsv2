package main

import (
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
)

// Package lists whose additions matter to this host: the shared pair plus its
// own. Additions are computed across the sync merge (old HEAD → upstream), so
// a package you deliberately uninstalled while it stays listed never nags —
// only lines another machine added since the last pull show up.
func pkgLists(host string) []string {
	return []string{
		".config/installed_packages/common.txt",
		".config/installed_packages/fonts.txt",
		".config/installed_packages/" + host + ".txt",
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

// newPackages returns the list entries present at newRef but not at oldRef.
// Set difference, not a line diff, so re-sorting a list adds nothing.
func newPackages(dir, oldRef, newRef, host string) []string {
	var out []string
	for _, f := range pkgLists(host) {
		newC, ok := fileAtRef(dir, newRef, f)
		if !ok {
			continue
		}
		oldC, _ := fileAtRef(dir, oldRef, f) // missing before -> whole list is new
		old := parsePkgs(oldC)
		for p := range parsePkgs(newC) {
			if !old[p] {
				out = append(out, p)
			}
		}
	}
	sort.Strings(out)
	return out
}

// filterInstalled drops packages the local pacman db already has (added
// upstream by the very machine that installed them first, or put on this box
// by hand). No pacman (mac) -> nothing filtered, yay --needed still no-ops.
func filterInstalled(pkgs []string) []string {
	out, err := exec.Command("pacman", "-Qq").Output()
	if err != nil {
		return pkgs
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

func renderPkgPlan(pkgs []string) {
	if len(pkgs) == 0 {
		return
	}
	section("new packages (added upstream):")
	for _, p := range pkgs {
		fmt.Println("  " + label(styAdd, "install", p, ""))
	}
}

// installPackages offers the new packages to yay. Interactive only: under
// --yes (install.sh) it is skipped — the converge's own package pass covers
// the same lists moments later.
func installPackages(pkgs []string, yes bool) error {
	if len(pkgs) == 0 {
		return nil
	}
	if yes {
		info("new packages skipped under --yes — install.sh's package pass handles them")
		return nil
	}
	if _, err := exec.LookPath("yay"); err != nil {
		info("yay not found — install by hand: %s", strings.Join(pkgs, " "))
		return nil
	}
	ok, err := confirm(fmt.Sprintf("install %d new package(s) with yay?", len(pkgs)))
	if err != nil {
		return err
	}
	if !ok {
		info("packages skipped")
		return nil
	}
	cmd := exec.Command("yay", append([]string{"-S", "--needed"}, pkgs...)...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("yay: %w", err)
	}
	return nil
}
