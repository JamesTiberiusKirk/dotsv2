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

    // Paired audio kit that is not currently connected. The audio panel lists
    // these under the live sinks so a headset can be brought back without
    // opening this panel — pipewire only knows a device once bluez has it.
    readonly property var audioDevices: devices.filter(d => !d.connected && isAudio(d))
    function isAudio(device) {
        const i = device?.icon ?? "";
        return i.includes("headset") || i.includes("headphone")
            || i.includes("speaker") || i.includes("audio");
    }

    // bluez calls AirPods audio-headset like everything else, so the model has
    // to come off the name. Cheap, and the only thing that distinguishes them.
    function isPods(device) {
        return (device?.name ?? "").toLowerCase().indexOf("airpods") >= 0;
    }

    function setEnabled(on) {
        if (adapter) adapter.enabled = on;
    }
    // bluez has no connect()/disconnect(); the property is the verb.
    //
    // Connecting retries, because AirPods only listen for an incoming
    // connection while nothing else holds them — lid just opened, or in-ear
    // with no host. Held by a phone, they stop page-scanning and a single
    // Connect simply times out. Apple's own devices skip the queue with the
    // iCloud account keys, which is not a door open to us. So the row keeps
    // asking for a few seconds: tap it, pop the case lid, and the retry lands
    // in the window instead of you having to hit it by hand.
    //
    // Disconnect stays a single call — nothing has to agree to that.
    function toggle(device) {
        if (!device) return;
        if (device.connected) {
            if (connecting === device) stopConnect();
            device.connected = false;
            return;
        }
        connecting = device;
        retry.ticks = 8;
        retry.restart();
        device.connected = true;
    }
    // The device currently being retried, or null. Rows bind against it to
    // show themselves as busy for the whole window rather than only during
    // bluez's own Connecting state.
    property var connecting: null
    function stopConnect() {
        connecting = null;
        retry.stop();
    }

    Timer {
        id: retry
        // Long enough that a real Connect attempt has finished failing; eight
        // of them covers the lid-open fumble without nagging bluez for a
        // minute. ponytail: one pending connect at a time, the panel only
        // offers one row to press anyway.
        interval: 2000
        repeat: true
        property int ticks: 0
        onTriggered: {
            const d = root.connecting;
            if (!d || d.connected || ticks <= 0) {
                root.stopConnect();
                return;
            }
            ticks--;
            // Re-issuing while bluez is still dialling gets the attempt in
            // flight thrown away, so a tick that lands mid-attempt just waits.
            if (d.state !== BluetoothDeviceState.Connecting) d.connected = true;
        }
    }

    // bluez hands out freedesktop icon names, which map onto the nerd font's
    // device set closely enough to skip a lookup table per model
    function devIcon(device) {
        if (isPods(device)) return "airpods";
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
