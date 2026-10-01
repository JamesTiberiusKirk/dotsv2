package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

// Locked brightness: the lit monitors form one group, each at a fixed offset
// from a shared level L (value_i = L + off_i). Keys and the main slider move L;
// only an accordion row edits an offset. Going to either edge stops the whole
// group at once, so the gaps are never squashed. Offsets persist in
// ~/.local/state/duo/brightness-offsets as "<key> <offset>" lines, L in
// brightness-level.
//
// L is stored, not read back off a panel: with the lid shut (clamshell) or the
// keyboard on the bottom panel, a built-in panel is dark, must not limit the
// group, and so can be pushed past 1..100 and clamped — after which its value
// no longer says where L is. Dark panels still get written (clamped), so they
// come back near the right value when they light up.

// member is one participating monitor. target is what apply/extSetPct take
// (top, bottom or a connector); key is the persistent identity.
type member struct {
	key, target string
	pct         int
	off         int
	lit         bool // dark panels keep their offset but set no limits
}

// ---- pure math (group_test.go) ----

// bounds is the legal range of L for these offsets.
func bounds(offs []int) (lo, hi int) {
	mn, mx := 0, 0
	for i, o := range offs {
		if i == 0 || o < mn {
			mn = o
		}
		if i == 0 || o > mx {
			mx = o
		}
	}
	return 1 - mn, 100 - mx
}

func clampL(offs []int, L int) int {
	lo, hi := bounds(offs)
	return min(max(L, lo), hi)
}

func maxOff(offs []int) int {
	mx := 0
	for i, o := range offs {
		if i == 0 || o > mx {
			mx = o
		}
	}
	return mx
}

// groupStep is a key press: the brightest monitor takes the usual bstep, the
// rest follow by the same delta, clamped so the first to hit an edge stops it.
func groupStep(offs []int, L int, up bool) int {
	main := L + maxOff(offs)
	return clampL(offs, L+bstep(main, up)-main)
}

// groupSet is the main slider: M is the brightest monitor's value.
func groupSet(offs []int, M int) int { return clampL(offs, M-maxOff(offs)) }

// memberOffset is an accordion row set to v at level L.
func memberOffset(v, L int) int { return clampPct(v) - L }

// capSpread pulls offsets up so brightest - dimmest <= 99; wider cannot fit
// in 1..100 (only reachable by hand-editing the file).
func capSpread(offs []int) []int {
	mx := maxOff(offs)
	out := make([]int, len(offs))
	for i, o := range offs {
		out[i] = max(o, mx-99)
	}
	return out
}

// ---- storage ----

func loadOffsets() map[string]int {
	offs := map[string]int{}
	for _, l := range strings.Split(stateRead("brightness-offsets"), "\n") {
		f := strings.Fields(l)
		if len(f) != 2 {
			continue
		}
		if n, err := strconv.Atoi(f[1]); err == nil {
			offs[f[0]] = n
		}
	}
	return offs
}

func saveOffsets(offs map[string]int) {
	keys := make([]string, 0, len(offs))
	for k := range offs {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, k := range keys {
		fmt.Fprintf(&b, "%s %d\n", k, offs[k])
	}
	if err := stateWrite("brightness-offsets", b.String()); err != nil {
		logf("brightness-offsets: %v", err)
	}
}

// extIDs maps connector -> EDID identity from monitors.lua's hypr-monitors
// file (lines "<connector> <id>"). A connector name is the fallback key: it
// survives nothing, but a missing map is no reason to lose the offset outright.
func extIDs() map[string]string {
	ids := map[string]string{}
	b, _ := os.ReadFile(os.Getenv("XDG_RUNTIME_DIR") + "/hypr-monitors")
	for _, l := range strings.Split(string(b), "\n") {
		if f := strings.Fields(l); len(f) == 2 && f[0] != "profile" {
			ids[f[0]] = f[1]
		}
	}
	return ids
}

// extValues is the externals' last applied percent. The daemon has it in
// memory; the CLI has no extSrv and must not ddcutil (the daemon owns the
// bus), so it reads the "ext" lines the daemon published.
func extValues() map[string]int {
	if extSrv != nil {
		v, _ := extSrv.values()
		return v
	}
	vals := map[string]int{}
	for _, l := range strings.Split(read(statePublishPath()), "\n") {
		if f := strings.Fields(l); len(f) == 3 && f[0] == "ext" {
			if n, err := strconv.Atoi(f[2]); err == nil {
				vals[f[1]] = n
			}
		}
	}
	return vals
}

// ---- group ----

// participants are every monitor with a backlight or DDC: both built-in panels
// (lit only while the kernel says their output is enabled — the lid shut, or the
// keyboard covering the bottom one, darkens them) and every external.
func participants() []member {
	offs := loadOffsets()
	var ms []member
	if pct, err := pctOf(topBL); err == nil {
		ms = append(ms, member{key: "top", target: "top", pct: pct,
			lit: read("/sys/class/drm/card1-eDP-1/enabled") == "enabled"})
	}
	if pct, err := pctOf(botBL); err == nil {
		ms = append(ms, member{key: "bottom", target: "bottom", pct: pct,
			lit: read("/sys/class/drm/card1-eDP-2/enabled") == "enabled"})
	}
	ids, vals := extIDs(), extValues()
	for _, c := range extConnectors() {
		key := c
		if id := ids[c]; id != "" {
			key = id
		}
		pct, ok := vals[c]
		if !ok {
			pct = -1
		}
		ms = append(ms, member{key: key, target: c, pct: pct, lit: true})
	}
	list := make([]int, len(ms))
	for i := range ms {
		list[i] = offs[ms[i].key]
	}
	if capped := capSpread(list); fmt.Sprint(capped) != fmt.Sprint(list) {
		logf("brightness-offsets: spread over 99, capped")
		list = capped
	}
	for i := range ms {
		ms[i].off = list[i]
	}
	return ms
}

// offsOf is the lit members' offsets: the ones that set the group's limits and
// its main value. All of them if nothing is lit, so the math never sees none.
func offsOf(ms []member) []int {
	var offs, all []int
	for _, m := range ms {
		all = append(all, m.off)
		if m.lit {
			offs = append(offs, m.off)
		}
	}
	if len(offs) == 0 {
		return all
	}
	return offs
}

// groupLevel is the stored L, or — first use, or re-locking after unlocked
// tweaks (deriveLevel) — one read back off the first lit member.
func groupLevel(ms []member) (int, bool) {
	if n, err := strconv.Atoi(stateRead("brightness-level")); err == nil {
		return n, true
	}
	return deriveLevel(ms)
}

func deriveLevel(ms []member) (int, bool) {
	for _, m := range ms {
		if m.lit && m.pct >= 0 {
			return m.pct - m.off, true
		}
	}
	return 0, false
}

func saveLevel(L int) {
	if err := stateWrite("brightness-level", strconv.Itoa(L)); err != nil {
		logf("brightness-level: %v", err)
	}
}

// applyGroup records L and writes L+off to every member, dark ones included.
func applyGroup(ms []member, L int) error {
	saveLevel(L)
	var err error
	for _, m := range ms {
		pct := clampPct(L + m.off)
		if m.target == "top" || m.target == "bottom" {
			if e := apply(pct, m.target); e != nil && err == nil {
				err = e
			}
		} else {
			extSetPct(m.target, pct)
		}
	}
	return err
}

// groupMain is the brightest and dimmest monitor's value for the state file
// (the main slider's value and floor). Computed from L, not the externals'
// readings, so a slow DDC write does not make the slider wobble.
func groupMain() (main, minV int, ok bool) {
	ms := participants()
	L, ok := groupLevel(ms)
	if !ok {
		return 0, 0, false
	}
	offs := offsOf(ms)
	if len(offs) == 0 {
		return 0, 0, false
	}
	mn := offs[0]
	for _, o := range offs {
		mn = min(mn, o)
	}
	return L + maxOff(offs), L + mn, true
}

// groupCmd is the locked path of `duo brightness up|down|set`. target "" and
// "all" move the group; anything else edits that monitor's offset.
func groupCmd(action, val, target string) error {
	ms := participants()
	L, ok := groupLevel(ms)
	if !ok {
		return fmt.Errorf("brightness: no lit monitor to read a level from")
	}
	offs := offsOf(ms)
	var n int
	if action == "set" {
		var err error
		if n, err = strconv.Atoi(val); err != nil {
			return fmt.Errorf("set: want a percent, got %q", val)
		}
	}
	switch {
	case action == "up" || action == "down":
		L = groupStep(offs, L, action == "up")
	case target == "" || target == "all" || target == "both":
		L = groupSet(offs, n)
	default:
		for _, m := range ms {
			if m.target != target {
				continue
			}
			all := loadOffsets()
			all[m.key] = memberOffset(n, L)
			saveOffsets(all)
			if m.target == "top" || m.target == "bottom" {
				return apply(clampPct(n), m.target)
			}
			extSetPct(m.target, n)
			return nil
		}
		return fmt.Errorf("brightness: %q is not in the group", target)
	}
	return applyGroup(ms, L)
}
