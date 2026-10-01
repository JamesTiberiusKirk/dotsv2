package main

import (
	"fmt"
	"testing"
)

func TestGroup(t *testing.T) {
	offs := []int{0, -20, -5} // laptop, MSI 20 dimmer, a third 5 dimmer

	// down: dimmest (off -20) at 3 -> L=23; a -5 step clamps to L=21 (dimmest 1)
	if L := groupStep(offs, 23, false); L != 21 {
		t.Errorf("down clamp: L=%d want 21", L)
	}
	if L := groupStep(offs, 21, false); L != 21 { // already at the stop
		t.Errorf("down stop: L=%d want 21", L)
	}
	// up: brightest (off 0) lands exactly on 100
	if L := groupStep(offs, 97, true); L != 100 {
		t.Errorf("up clamp: L=%d want 100", L)
	}
	if L := groupStep(offs, 100, true); L != 100 {
		t.Errorf("up stop: L=%d want 100", L)
	}
	// main slider below/above range clamps
	if L := groupSet(offs, 5); L != 21 {
		t.Errorf("set low: L=%d want 21", L)
	}
	if L := groupSet(offs, 500); L != 100 {
		t.Errorf("set high: L=%d want 100", L)
	}
	if L := groupSet(offs, 60); L != 60 {
		t.Errorf("set mid: L=%d want 60", L)
	}
	// member set: only that offset moves, relative to L
	if o := memberOffset(50, 70); o != -20 {
		t.Errorf("member: off=%d want -20", o)
	}
	if o := memberOffset(500, 70); o != 30 { // v clamps to 100
		t.Errorf("member clamp: off=%d want 30", o)
	}
	// no participants / one participant
	if lo, hi := bounds(nil); lo != 1 || hi != 100 {
		t.Errorf("empty bounds: %d %d", lo, hi)
	}
	if L := groupStep(nil, 50, true); L != 55 {
		t.Errorf("empty step: L=%d want 55", L)
	}
	if L := groupSet([]int{0}, 0); L != 1 {
		t.Errorf("single set: L=%d want 1", L)
	}
	// offsets wider than 99 apart are pulled in
	if c := capSpread([]int{0, -150}); c[1] != -99 {
		t.Errorf("capSpread: %v", c)
	}
}

// A dark panel (lid shut, keyboard on the bottom one) keeps its offset but must
// not set the group's limits or its main value.
func TestOffsOfSkipsDark(t *testing.T) {
	ms := []member{
		{key: "top", off: -40, lit: false},
		{key: "DP-1", off: 0, lit: true},
		{key: "HDMI-A-1", off: -10, lit: true},
	}
	if got := fmt.Sprint(offsOf(ms)); got != "[0 -10]" {
		t.Fatalf("offsOf = %s, want [0 -10]", got)
	}
	for i := range ms {
		ms[i].lit = false
	}
	if got := len(offsOf(ms)); got != 3 {
		t.Fatalf("nothing lit: offsOf len = %d, want all 3", got)
	}
}
