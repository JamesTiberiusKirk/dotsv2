package main

import "testing"

// Entries/SystemEntries split: system/ lines must never reach the $HOME
// linker, and only they feed the root-installed system plan.
func TestManifestSystemSplit(t *testing.T) {
	m := parseManifestBytes("hosts/x", []byte(
		"# comment\n.zshrc\nsystem/etc/udev/rules.d/92-runtime-pm.rules\nsystem/etc/runit/sv/keyd\nservice cronie\n.config/hypr\n  service bluetoothd\n"))
	if got := m.Entries(); len(got) != 2 || got[0] != ".zshrc" || got[1] != ".config/hypr" {
		t.Fatalf("Entries() = %v", got)
	}
	if got := m.SystemEntries(); len(got) != 2 || got[0] != "system/etc/udev/rules.d/92-runtime-pm.rules" {
		t.Fatalf("SystemEntries() = %v", got)
	}
	if got := m.Services(); len(got) != 2 || got[0] != "cronie" || got[1] != "bluetoothd" {
		t.Fatalf("Services() = %v", got)
	}
}
