import QtQuick

// The open body of a fold, lifted onto its own card.
//
// Separation by tone rather than by a rule: several folds stack inside one
// popout, and a divider between two of them reads as two more sections instead
// of as one thing having opened. The tint is track at low alpha so it stays
// clear of the focus ring, which is track at full strength.
//
// Children position themselves against the inner Column, so they want
// `width: parent.width` — that is the card minus its padding.
Item {
    id: root

    property int pad: 8
    property alias spacing: inner.spacing
    default property alias content: inner.data

    width: parent ? parent.width : 0
    implicitHeight: inner.implicitHeight + root.pad * 2
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Qt.alpha(Theme.track, 0.45)
        border.width: 1
        border.color: Theme.islandBorder
    }
    Column {
        id: inner
        anchors {
            left: parent.left; right: parent.right; top: parent.top
            margins: root.pad
        }
        spacing: 6
    }
}
