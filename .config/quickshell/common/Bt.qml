pragma Singleton
import Quickshell
import Quickshell.Bluetooth
import QtQuick

// Bluetooth state for the bar cell and its panel.
//
// Pairing is deliberately absent: BluetoothDevice exposes `connected` and
// `trusted` as writable but has no pair() method, so a new device still has to
// go through blueman (which is installed). This covers the daily case —
// connect the headset, see what the keyboard's battery is doing.
Singleton {
    id: root

    property bool panelOpen: false

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool present: adapter !== null
    readonly property bool enabled: adapter?.enabled ?? false

    // connected first, then whatever is paired, each alphabetical — the list is
    // short and a stable order beats bluez's arrival order
    readonly property var devices: {
        const ds = (Bluetooth.devices?.values ?? []).filter(d => d.paired);
        ds.sort((a, b) => (b.connected - a.connected)
                       || a.name.localeCompare(b.name));
        return ds;
    }
    readonly property var connectedDevices: devices.filter(d => d.connected)
    readonly property bool anyConnected: connectedDevices.length > 0

    function setEnabled(on) {
        if (adapter) adapter.enabled = on;
    }
    // bluez has no connect()/disconnect(); the property is the verb
    function toggle(device) {
        if (device) device.connected = !device.connected;
    }

    // bluez hands out freedesktop icon names, which map onto the nerd font's
    // device set closely enough to skip a lookup table per model
    function devIcon(device) {
        const i = device?.icon ?? "";
        if (i.includes("headset")) return "headset";
        if (i.includes("headphone")) return "headphones";
        if (i.includes("speaker") || i.includes("audio")) return "speaker";
        if (i.includes("keyboard")) return "keyboard";
        if (i.includes("mouse") || i.includes("pointing")) return "mouse";
        if (i.includes("phone")) return "cellphone";
        return "bluetooth";
    }

    // State is carried by colour rather than by swapping in bluetooth-connect,
    // whose two hanging dots collapse into a speck at bar size. Kept that way
    // after the move to SVG: the size is controllable now, but the colour still
    // reads faster than a shape difference that small.
    readonly property string icon: !present || !enabled ? "bluetooth-off" : "bluetooth"
}
