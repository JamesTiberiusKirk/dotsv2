import QtQuick

// A text box for a bar popout. Drop it in with `popout:` set and typing just
// works: while it shows, the popout takes the keyboard and Sys lifts the
// any-key-closes submap (see Sys.submap). Nothing else to wire per use.
Rectangle {
    id: root

    // The Popout this sits in. Passed in rather than found by walking up the
    // parents: explicit, and it cannot latch onto the wrong window.
    required property var popout
    property alias text: input.text
    property bool password: false
    property bool reveal: false
    signal accepted()

    implicitWidth: 140
    implicitHeight: 24
    radius: 4
    color: Theme.track

    // Counted into popout.inputs while shown. `visible` is effective
    // visibility, so a closed popout or a folded row counts out too. The
    // flag keeps in/out paired; the destruction line covers a field torn
    // down while showing (a wifi row dropping out of a rescan), which would
    // otherwise leave the popout holding the keyboard for good.
    property bool counted: false
    function sync() {
        if (visible === counted) return;
        counted = visible;
        popout.inputs += visible ? 1 : -1;
        // the surface takes focus on click, but nothing hands it to the field
        if (visible) input.forceActiveFocus();
    }
    onVisibleChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (counted && popout) popout.inputs -= 1

    TextInput {
        id: input
        anchors { fill: parent; margins: 6 }
        font.family: Theme.font
        font.pixelSize: 11
        color: Theme.bright
        echoMode: root.password && !root.reveal ? TextInput.Password : TextInput.Normal
        clip: true
        Keys.onReturnPressed: root.accepted()
        // the submap's Esc is off while this is up, so Esc has to land here
        Keys.onEscapePressed: root.popout.bar.closeIslandPopouts()
    }
}
