import Quickshell
import QtQuick

// Drift check: lists fields/functions declared in FakeData.qml but not
// LiveData.qml and the other way round. Run: qs -p ~/.config/quickshell-lcars/check.qml
ShellRoot {
    function names(file) {
        const x = new XMLHttpRequest();
        x.open("GET", Qt.resolvedUrl(file), false);
        x.send();
        const out = new Set();
        const re = /^\s*(?:readonly\s+)?(?:property\s+(?:\w+)\s+(\w+)|function\s+(\w+))/gm;
        let m;
        while ((m = re.exec(x.responseText))) out.add(m[1] || m[2]);
        return out;
    }
    Component.onCompleted: {
        const f = names("FakeData.qml"), l = names("LiveData.qml");
        // internal helpers on one side only are fine
        const skip = new Set(["log", "root", "fd", "dev", "av", "briRow", "player"]);
        const miss = (a, b) => [...a].filter(n => !b.has(n) && !skip.has(n) && !n.startsWith("_"));
        const a = miss(f, l), b = miss(l, f);
        console.log("drift: in FakeData only:", a.join(",") || "none", "| in LiveData only:", b.join(",") || "none");
        Qt.quit();
    }
}
