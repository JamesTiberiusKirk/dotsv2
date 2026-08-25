package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Orientation of the machine, named after which edge points up — the same
// vocabulary iio-sensor-proxy uses, so the thresholds below are comparable.
type orientation string

const (
	orientNormal   orientation = "normal"    // upright, panels stacked
	orientLeftUp   orientation = "left-up"   // rotated clockwise into portrait
	orientRightUp  orientation = "right-up"  // rotated anticlockwise into portrait
	orientBottomUp orientation = "bottom-up" // upside down
	orientUnknown  orientation = "unknown"   // lying flat: gravity says nothing useful
)

// Gravity is 9.81 m/s²; a tilt only counts once a good half of it lands on one
// axis, which keeps the layout from flapping when the machine is near 45°.
const tiltThreshold = 5.0

// iioDevice finds the IIO device with the given name. Indices are NOT stable:
// they follow probe order, so iio:device0 is the accelerometer on one boot and
// the ambient light sensor on the next. Hardcoding an index is what silently
// broke autorotate — accel reads landed on the ALS, which has no in_accel_*
// nodes at all, so every rotation attempt failed with "no accelerometer".
func iioDevice(name string) (string, error) {
	devs, _ := filepath.Glob("/sys/bus/iio/devices/iio:device*")
	for _, d := range devs {
		if b, err := os.ReadFile(filepath.Join(d, "name")); err == nil &&
			strings.TrimSpace(string(b)) == name {
			return d, nil
		}
	}
	return "", fmt.Errorf("no iio device named %q", name)
}

func accel() (x, y, z float64, err error) {
	dev, err := iioDevice("accel_3d")
	if err != nil {
		return 0, 0, 0, fmt.Errorf("no accelerometer: %w", err)
	}
	scale, err := readFloat(filepath.Join(dev, "in_accel_scale"))
	if err != nil {
		return 0, 0, 0, fmt.Errorf("no accelerometer: %w", err)
	}
	axis := func(a string) float64 {
		v, e := readFloat(filepath.Join(dev, "in_accel_"+a+"_raw"))
		if e != nil {
			err = e
		}
		return v * scale
	}
	return axis("x"), axis("y"), axis("z"), err
}

// hinge returns the Duo's three reported angles: the hinge itself, and each
// half's angle to the ground. Useful to tell laptop mode from book/tablet mode.
func hinge() (hingeDeg, screenDeg, keyboardDeg float64) {
	dev, err := iioDevice("hinge")
	if err != nil {
		return 0, 0, 0
	}
	h, _ := readFloat(filepath.Join(dev, "in_angl0_raw"))
	s, _ := readFloat(filepath.Join(dev, "in_angl1_raw"))
	k, _ := readFloat(filepath.Join(dev, "in_angl2_raw"))
	return h, s, k
}

// detectOrientation maps the gravity vector to an edge-up name. Portrait is
// checked first: with the machine on its side, x carries gravity and y is the
// one near zero.
//
// The x signs are the opposite of iio-sensor-proxy's convention — this panel is
// mounted the other way round. Measured on binstar: left edge up reads x ≈ +9.4,
// right edge up reads x ≈ -8.6, upright reads y ≈ -9.
func detectOrientation() (orientation, error) {
	x, y, _, err := accel()
	if err != nil {
		return orientUnknown, err
	}
	switch {
	case x > tiltThreshold:
		return orientLeftUp, nil
	case x < -tiltThreshold:
		return orientRightUp, nil
	case y > tiltThreshold:
		return orientBottomUp, nil
	case y < -tiltThreshold:
		return orientNormal, nil
	}
	return orientUnknown, nil
}

func readFloat(path string) (float64, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	return strconv.ParseFloat(strings.TrimSpace(string(b)), 64)
}

func orientationCmd() error {
	x, y, z, err := accel()
	if err != nil {
		return err
	}
	o, _ := detectOrientation()
	h, s, k := hinge()
	fmt.Printf("accel:       x=%+.2f y=%+.2f z=%+.2f m/s²\n", x, y, z)
	fmt.Printf("hinge:       hinge=%.0f° screen=%.0f° keyboard=%.0f°\n", h, s, k)
	fmt.Printf("orientation: %s\n", o)
	fmt.Printf("autorotate:  %s\n", map[bool]string{true: "on", false: "off"}[autoRotate()])
	return nil
}
