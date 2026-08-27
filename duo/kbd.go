package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

// The detachable keyboard boots with its Fn/media layer off: every Fn chord
// arrives as a bare KEY_F<n> until it receives the ASUS init string. hid-asus
// does this in-kernel (asus_kbd_init) but its device table has no UX8406CA
// entry as of 7.1, so the keyboard runs on generic usbhid and we send it here.
//
// Report 0x5a on the vendor interface, payload "ASUS Tech.Inc.\0".
var handshake = []byte{
	0x5a, 0x41, 0x53, 0x55, 0x53, 0x20, 0x54, 0x65,
	0x63, 0x68, 0x2e, 0x49, 0x6e, 0x63, 0x2e, 0x00,
}

// Firmware answers the first attempts with -EPIPE or echoes stale state; the
// same bytes land a moment later, so back off and retry rather than give up.
var handshakeDelays = []time.Duration{0, 100, 250, 500, 1000, 2000}

func kbdCmd(action, val string) error {
	switch action {
	case "handshake":
		return kbdHandshake()
	case "backlight":
		n, err := strconv.Atoi(val)
		if err != nil || n < 0 || n > 3 {
			return fmt.Errorf("backlight: want 0-3, got %q", val)
		}
		if err := setKbdBacklight(n); err != nil {
			return err
		}
		setKbdLevel(n)
		// nothing in sysfs reports this level back, so the shell is told directly
		exec.Command("qs", "ipc", "call", "osd", "kbd", strconv.Itoa(n)).Run()
		return nil
	}
	return fmt.Errorf("kbd: want handshake|backlight, got %q", action)
}

// setKbdBacklight sends the level to the keyboard and nothing else: no
// persisted level, no OSD. The user-facing command layers those on top; the
// daemon calls this directly when it is restoring a level (startup, resume)
// or blanking for sleep — neither is a change the user made, so neither
// should flash the OSD or overwrite what they picked.
func setKbdBacklight(n int) error {
	// 0x5a 0xba 0xc5 0xc4 <level>, same report as hid-asus uses
	return withKbdDevice(func(f *os.File) error {
		return setFeature(f, []byte{0x5a, 0xba, 0xc5, 0xc4, byte(n)})
	})
}

func kbdHandshake() error {
	var err error
	for _, d := range handshakeDelays {
		time.Sleep(d * time.Millisecond)
		err = withKbdDevice(func(f *os.File) error { return setFeature(f, handshake) })
		if err == nil {
			return nil
		}
	}
	return fmt.Errorf("handshake: %w", err)
}

// withKbdDevice opens the keyboard's vendor hidraw node — the one whose report
// descriptor declares report id 0x5a (0x85 0x5a) — and hands it to fn.
// Interface numbering isn't stable across re-docks, hence the descriptor scan.
func withKbdDevice(fn func(*os.File) error) error {
	node, err := findKbdHidraw()
	if err != nil {
		return err
	}
	f, err := os.OpenFile(node, os.O_RDWR, 0)
	if err != nil {
		return err
	}
	defer f.Close()
	return fn(f)
}

func findKbdHidraw() (string, error) {
	nodes, _ := filepath.Glob("/sys/class/hidraw/hidraw*")
	for _, n := range nodes {
		uevent, err := os.ReadFile(filepath.Join(n, "device/uevent"))
		if err != nil || !isKbdUevent(string(uevent)) {
			continue
		}
		desc, err := os.ReadFile(filepath.Join(n, "device/report_descriptor"))
		if err != nil {
			continue
		}
		for i := 0; i+1 < len(desc); i++ {
			if desc[i] == 0x85 && desc[i+1] == 0x5a { // Report ID 0x5a
				return "/dev/" + filepath.Base(n), nil
			}
		}
	}
	return "", fmt.Errorf("keyboard hidraw node not found (docked?)")
}

// The same keyboard has one id docked and another over bluetooth, and the
// vendor channel works on both — so anything Fn-related must accept either.
func isKbdUevent(uevent string) bool {
	u := strings.ToUpper(uevent)
	for _, p := range []string{kbProduct, kbProductBT} {
		if strings.Contains(u, strings.ToUpper(p)) {
			return true
		}
	}
	return false
}

// kbdPresent reports whether the keyboard is reachable on either transport.
func kbdPresent() bool {
	_, err := findKbdHidraw()
	return err == nil
}

// setFeature issues HIDIOCSFEATURE(len): _IOC(READ|WRITE, 'H', 0x06, len).
func setFeature(f *os.File, data []byte) error {
	req := uintptr(3)<<30 | uintptr(len(data))<<16 | uintptr('H')<<8 | 0x06
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), req,
		uintptr(unsafe.Pointer(&data[0])))
	if errno != 0 {
		return errno
	}
	return nil
}

// Vendor key codes the keyboard reports on its 0x5a channel once the handshake
// has run. These never reach the input layer — no evdev device carries them —
// so nothing but this reader can see them. Captured on UX8406CA:
//
//	0x10 brightness down   0x20 brightness up   0xc7 keyboard backlight
//	0x00 is the release event for all of them
const (
	keyBrightnessDown = 0x10
	keyBrightnessUp   = 0x20
	keyKbdBacklight   = 0xc7
)

// Level the backlight key cycles through. The firmware can't be asked what it
// is, and the daemon, the CLI and the bar's click are three different
// processes, so the current value lives in a runtime file they all share.
func kbdLevelPath() string {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "duo-kbd-backlight")
}

func kbdLevel() int {
	b, err := os.ReadFile(kbdLevelPath())
	if err != nil {
		return 0
	}
	n, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil || n < 0 || n > 3 {
		return 0
	}
	return n
}

func setKbdLevel(n int) { os.WriteFile(kbdLevelPath(), []byte(strconv.Itoa(n)), 0644) }

// readKbdKeys pumps the vendor report channel until the keyboard goes away
// (undock closes the node, ending the loop).
func readKbdKeys() {
	node, err := findKbdHidraw()
	if err != nil {
		return
	}
	f, err := os.Open(node)
	if err != nil {
		fmt.Fprintln(os.Stderr, "duo: keyboard keys:", err)
		return
	}
	defer f.Close()

	buf := make([]byte, 64)
	for {
		n, err := f.Read(buf)
		if err != nil {
			return
		}
		if n < 2 || buf[0] != 0x5a {
			continue
		}
		switch buf[1] {
		case keyBrightnessDown:
			brightnessCmd("down", "", "")
		case keyBrightnessUp:
			brightnessCmd("up", "", "")
		case keyKbdBacklight:
			kbdCmd("backlight", strconv.Itoa((kbdLevel()+1)%4))
		}
	}
}
