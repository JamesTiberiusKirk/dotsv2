package main

// External-monitor brightness over DDC/CI (ddcutil, VCP feature 0x10).
//
// The internal panels are sysfs writes — instant, no coordination. External
// monitors are not: a ddcutil write is 100-300ms and two writes racing on the
// same i2c bus fail with a busy/retry error. The brightness keys auto-repeat
// (binds.lua: repeating = true) and the slider commits every 50ms while
// dragging, so a naive "write per event" both lags and corrupts.
//
// The fix is a single owner. `duo watch` already runs one-per-session, so the
// daemon carries a goroutine that owns every external: requests arrive on a
// unix socket, land in a desired-value map, and one worker applies the latest
// value per monitor, draining anything that queued during a slow write. That
// makes it last-value-wins by construction — no cross-process flock protocol,
// no lost final value. The CLI (`duo brightness ...`) is a thin client that
// fires an intent at the socket and returns immediately; if no daemon is
// listening it writes ddcutil directly as a best-effort fallback.
//
// Externals are addressed by DRM connector name (DP-1, HDMI-A-1) — the same
// vocabulary Hyprland and monitor-layout.sh use. ddcutil itself selects by
// --bus, and buses only shuffle across replug/reboot, so the connector->bus
// map is cached from one `ddcutil detect` and refreshed on demand.

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
)

// extMon is one DDC-capable external monitor.
type extMon struct {
	conn string // DRM connector, "card1-" stripped: DP-1, HDMI-A-1
	bus  int    // /dev/i2c-N
	pct  int    // current brightness (VCP 0x10), -1 if not read
}

const vcpBrightness = "10"

func extSocketPath() (string, error) {
	dir, err := sessionDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "duo-bright.sock"), nil
}

// extCachePath is the connector list the CLI reads to know which externals
// exist without paying for a detect (seconds) on every keypress. The daemon
// writes it; it lives in the session dir so it dies with the session.
func extCachePath() (string, error) {
	dir, err := sessionDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "duo-externals"), nil
}

// ---- detection ----

// ddcDetect parses `ddcutil detect` into the DDC-capable externals. Invalid
// displays (the internal panels report "does not support DDC/CI") and the
// "Invalid display" blocks are skipped: only a "Display N" block with both an
// I2C bus and a DRM connector counts. The laptop panels enumerate here too and
// must not — they are driven through sysfs.
func ddcDetect() ([]extMon, error) {
	out, err := exec.Command("ddcutil", "detect").Output()
	if err != nil {
		return nil, fmt.Errorf("ddcutil detect: %w", err)
	}
	var mons []extMon
	var cur extMon
	valid := false
	flush := func() {
		if valid && cur.bus >= 0 && cur.conn != "" {
			mons = append(mons, cur)
		}
	}
	for _, line := range strings.Split(string(out), "\n") {
		t := strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(t, "Display "):
			flush()
			cur = extMon{bus: -1, pct: -1}
			valid = true
		case strings.HasPrefix(t, "Invalid display"):
			flush()
			cur = extMon{bus: -1, pct: -1}
			valid = false // an internal panel or a non-DDC monitor
		case strings.HasPrefix(t, "I2C bus:"):
			// "I2C bus:  /dev/i2c-15"
			if i := strings.LastIndex(t, "i2c-"); i >= 0 {
				cur.bus, _ = strconv.Atoi(t[i+4:])
			}
		case strings.HasPrefix(t, "DRM_connector:"):
			// "DRM_connector:  card1-DP-1"
			f := strings.Fields(t)
			cur.conn = stripCard(f[len(f)-1])
		}
	}
	flush()
	return mons, nil
}

// stripCard turns "card1-DP-1" into "DP-1"; leaves anything else untouched.
func stripCard(s string) string {
	if i := strings.Index(s, "-"); i >= 0 && strings.HasPrefix(s, "card") {
		return s[i+1:]
	}
	return s
}

// readVCP reads a monitor's current brightness percent off its bus. Only ever
// called at detect time (daemon start, popout open), never per keypress.
func readVCP(bus int) int {
	out, err := exec.Command("ddcutil", "--bus", strconv.Itoa(bus), "getvcp", vcpBrightness).Output()
	if err != nil {
		return -1
	}
	// "VCP code 0x10 (Brightness): current value = 97, max value = 100"
	s := string(out)
	i := strings.Index(s, "current value =")
	if i < 0 {
		return -1
	}
	f := strings.Fields(s[i+len("current value ="):])
	if len(f) == 0 {
		return -1
	}
	v, err := strconv.Atoi(strings.TrimRight(f[0], ","))
	if err != nil {
		return -1
	}
	return v
}

// ---- daemon (runs inside `duo watch`) ----

type extServer struct {
	mu   sync.Mutex
	bus  map[string]int // connector -> i2c bus
	set  map[string]int // connector -> last percent we applied
	reqs chan extReq
	// bumped per completed refresh, published as "refreshed N": the shell may
	// rebuild its open slider rows on a fresh read, never on its own writes
	refreshes int
}

// extReq is one intent. abs >= 0 is an absolute percent; abs < 0 means step by
// `step` (+1/-1) from the monitor's current value. refresh re-detects every
// external and re-reads its brightness — queued like a write, so a detect never
// shares the i2c bus with one.
type extReq struct {
	conn    string
	abs     int
	step    int
	refresh bool
	osd     bool // a key press: ping the OSD with the applied value
}

// extSrv is the daemon's server, nil outside `duo watch` (and until extServe
// has built it). The watch loop queues a refresh on it when a connector comes
// or goes; publish reads the applied values off it.
var extSrv *extServer

func newExtServer() *extServer {
	return &extServer{
		bus:  map[string]int{},
		set:  map[string]int{},
		reqs: make(chan extReq, 64),
	}
}

// refresh re-detects, re-reads every external's brightness and rewrites the
// connector cache. Only ever runs on the worker goroutine. Rebuilt from
// scratch: an unplugged monitor drops out, and a value changed with the
// monitor's own buttons replaces the stale one the next key press would
// otherwise step from.
func (s *extServer) refresh() {
	mons, err := ddcDetect()
	if err != nil {
		logf("extbright: detect: %v", err)
		return
	}
	bus, set := map[string]int{}, map[string]int{}
	for _, m := range mons {
		bus[m.conn] = m.bus
		set[m.conn] = readVCP(m.bus)
	}
	s.mu.Lock()
	s.bus, s.set = bus, set
	s.refreshes++
	s.mu.Unlock()
	s.writeCache(mons)
}

// values is connector -> applied percent for the monitors present right now,
// plus the refresh count those values belong to.
func (s *extServer) values() (map[string]int, int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make(map[string]int, len(s.set))
	for conn, pct := range s.set {
		if _, ok := s.bus[conn]; ok && pct >= 0 {
			out[conn] = pct
		}
	}
	return out, s.refreshes
}

func (s *extServer) writeCache(mons []extMon) {
	path, err := extCachePath()
	if err != nil {
		return
	}
	var b strings.Builder
	for _, m := range mons {
		fmt.Fprintln(&b, m.conn)
	}
	os.WriteFile(path, []byte(b.String()), 0644)
}

func (s *extServer) busFor(conn string) (int, bool) {
	s.mu.Lock()
	bus, ok := s.bus[conn]
	s.mu.Unlock()
	if !ok {
		s.refresh()
		s.mu.Lock()
		bus, ok = s.bus[conn]
		s.mu.Unlock()
	}
	return bus, ok
}

// worker owns every external write. Requests fold into `desired`; after each
// slow write it drains whatever queued so only the latest value per monitor is
// applied. ponytail: monitors are written one at a time (serial), so two
// externals both changing lag ~200ms apart — fine for a brightness nudge; a
// per-bus goroutine is the upgrade if it ever matters.
func (s *extServer) worker() {
	desired := map[string]int{}
	refresh := false
	osd := map[string]bool{}
	absorb := func(r extReq) {
		if r.refresh {
			refresh = true
			return
		}
		if r.osd {
			osd[r.conn] = true
		}
		if r.abs >= 0 {
			desired[r.conn] = clampPct(r.abs)
			return
		}
		cur, ok := desired[r.conn]
		if !ok {
			s.mu.Lock()
			cur = s.set[r.conn]
			s.mu.Unlock()
		}
		desired[r.conn] = clampPct(bstep(cur, r.step > 0))
	}
	for r := range s.reqs {
		absorb(r)
		// drain the burst that piled up behind a slow write
		for drained := false; !drained; {
			select {
			case r2 := <-s.reqs:
				absorb(r2)
			default:
				drained = true
			}
		}
		if refresh {
			s.refresh()
			refresh = false
		}
		for conn, pct := range desired {
			s.mu.Lock()
			same := s.set[conn] == pct
			s.mu.Unlock()
			if same {
				if osd[conn] {
					osdBrightness(pct) // key pressed at a limit: still show it
				}
				continue
			}
			bus, ok := s.busFor(conn)
			if !ok {
				logf("extbright: no bus for %s", conn)
				continue
			}
			if err := exec.Command("ddcutil", "--bus", strconv.Itoa(bus),
				"setvcp", "--noverify", vcpBrightness, strconv.Itoa(pct)).Run(); err != nil {
				logf("extbright: set %s=%d: %v", conn, pct, err)
				continue
			}
			s.mu.Lock()
			s.set[conn] = pct
			s.mu.Unlock()
			if osd[conn] {
				osdBrightness(pct)
			}
		}
		clear(desired)
		clear(osd)
		publish()
	}
}

// extServe accepts one-line requests on the session socket:
//
//	set <connector> <pct>
//	step <connector> up|down
//	refresh            re-detect and re-read every external (panel open)
//	publish            rewrite the state file now (a CLI just changed something)
//
// Fire-and-forget: the client writes a line and closes. Errors are logged, not
// returned — the client has already moved on.
func extServe() {
	s := newExtServer()
	extSrv = s
	go s.worker()
	s.reqs <- extReq{refresh: true}

	path, err := extSocketPath()
	if err != nil {
		logf("extbright: no socket: %v", err)
		return
	}
	os.Remove(path) // a stale socket from a crashed daemon blocks Listen
	ln, err := net.Listen("unix", path)
	if err != nil {
		logf("extbright: listen: %v", err)
		return
	}
	for {
		c, err := ln.Accept()
		if err != nil {
			logf("extbright: accept: %v", err)
			return
		}
		go s.handle(c)
	}
}

func (s *extServer) handle(c net.Conn) {
	defer c.Close()
	sc := bufio.NewScanner(c)
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) == 1 {
			switch f[0] {
			case "refresh":
				s.reqs <- extReq{refresh: true}
			case "publish":
				publish()
			}
			continue
		}
		if len(f) < 3 {
			continue
		}
		switch f[0] {
		case "set":
			if pct, err := strconv.Atoi(f[2]); err == nil {
				s.reqs <- extReq{conn: f[1], abs: pct}
			}
		case "step":
			dir := 0
			switch f[2] {
			case "up":
				dir = 1
			case "down":
				dir = -1
			}
			if dir != 0 {
				s.reqs <- extReq{conn: f[1], abs: -1, step: dir, osd: true}
			}
		}
	}
}

// ---- client (the `duo brightness` CLI) ----

// extSend delivers one line to the daemon. Returns an error if no daemon is
// listening, so the caller can fall back to a direct (uncoalesced) write.
func extSend(line string) error {
	path, err := extSocketPath()
	if err != nil {
		return err
	}
	c, err := net.Dial("unix", path)
	if err != nil {
		return err
	}
	defer c.Close()
	_, err = fmt.Fprintln(c, line)
	return err
}

// extSetPct pushes an absolute percent to one external, via the daemon when it
// is up and directly otherwise. The direct path is best-effort and unthrottled:
// it only runs with no `duo watch`, where nothing is repeating fast anyway.
func extSetPct(conn string, pct int) {
	if extSend(fmt.Sprintf("set %s %d", conn, clampPct(pct))) == nil {
		return
	}
	extWriteDirect(conn, clampPct(pct))
}

func extStep(conn string, up bool) {
	dir := "down"
	if up {
		dir = "up"
	}
	if extSend(fmt.Sprintf("step %s %s", conn, dir)) == nil {
		return
	}
	// no daemon: read-modify-write directly
	for _, m := range extListLive() {
		if m.conn == conn {
			pct := clampPct(bstep(readVCP(m.bus), up))
			extWriteDirect(conn, pct)
			osdBrightness(pct)
			return
		}
	}
}

func extWriteDirect(conn string, pct int) {
	for _, m := range extListLive() {
		if m.conn == conn {
			exec.Command("ddcutil", "--bus", strconv.Itoa(m.bus),
				"setvcp", "--noverify", vcpBrightness, strconv.Itoa(pct)).Run()
			return
		}
	}
}

// extConnectors returns the external connector names, from the daemon's cache
// file (instant) or a live detect if the daemon has not written one. An empty
// file is an answer (no externals), not a missing one: falling through on it
// ran a seconds-long detect on every keypress and every 1s publish.
func extConnectors() []string {
	if path, err := extCachePath(); err == nil {
		if b, err := os.ReadFile(path); err == nil {
			var out []string
			for _, l := range strings.Split(strings.TrimSpace(string(b)), "\n") {
				if l = strings.TrimSpace(l); l != "" {
					out = append(out, l)
				}
			}
			return out
		}
	}
	var out []string
	for _, m := range extListLive() {
		out = append(out, m.conn)
	}
	return out
}

// extListLive is a full detect + current-brightness read. Slow (~1-2s); only
// the `ext` subcommand (popout open) and the no-daemon fallbacks call it.
func extListLive() []extMon {
	mons, err := ddcDetect()
	if err != nil {
		return nil
	}
	for i := range mons {
		mons[i].pct = readVCP(mons[i].bus)
	}
	return mons
}

func clampPct(p int) int { return min(max(p, 1), 100) }
