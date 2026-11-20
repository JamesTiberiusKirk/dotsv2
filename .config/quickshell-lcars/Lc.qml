pragma Singleton
import Quickshell
import QtQuick

// LCARS colours, font and frame sizes. Own palette on purpose: never reads
// the normal shell's Theme.qml, so LCARS can't change how the normal shell looks.
Singleton {
    // red alert (Lcars.qml binds `alert`): every frame colour flips to a red shade, same roles
    property bool alert: false
    property int pulse: 1                   // 0/1, toggled by the one timer below while alerting
    readonly property real beat: alert && !pulse ? 0.55 : 1     // opacity of frame bars and spines
    Timer {
        interval: 500; repeat: true; running: Lc.alert
        onTriggered: Lc.pulse = Lc.pulse ? 0 : 1
        onRunningChanged: if (!running) Lc.pulse = 1
    }
    readonly property color black: "#000000"
    readonly property color orange: alert ? "#e03a2e" : "#ff9900"
    readonly property color peach: alert ? "#ff7a66" : "#ffcc99"
    readonly property color lilac: alert ? "#a8324a" : "#cc99cc"
    readonly property color blue: alert ? "#7a2233" : "#9999ff"
    readonly property color tan: alert ? "#f0553f" : "#ffcc66"
    readonly property color sky: alert ? "#c24455" : "#99ccff"
    readonly property color red: "#dd4444"
    readonly property color green: "#99cc66"
    readonly property color rose: alert ? "#d4506a" : "#cc6699"
    readonly property color dim: alert ? "#4a1a1a" : "#5a3c1e"
    readonly property color track: alert ? "#240c0c" : "#1c140a"

    readonly property string font: antonio.name
    FontLoader { id: antonio; source: Qt.resolvedUrl("fonts/Antonio.ttf") }

    readonly property int pad: 16
    readonly property int spine: 170        // station column width
    readonly property int topSpine: 60      // spine width on the top screen, where it enters from
    readonly property int topBar: 56        // top-screen bar thickness
    readonly property int bar: 26           // frame bar thickness
    readonly property int gap: 6
    readonly property int pill: 64          // station button height (touch target)

    // fake LCARS codes, stable per string
    function code(s) {
        let h = 7;
        for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 9000;
        const n = String(h + 1000);
        return n.slice(0, 2) + "-" + n.slice(2);
    }

    // invented stardate: years since 2000 as thousands, plus day-of-year fraction
    function stardate(d) {
        const y = d.getFullYear();
        const start = new Date(y, 0, 1);
        const doy = (d - start) / 86400000;
        return ((y - 2000) * 1000 + Math.floor(doy / 365 * 1000) + 100000) + "." + d.getHours();
    }
}
