import QtQuick
import QtQuick.Effects

// A themed status icon. Material Design Icons, the same library the nf-md-*
// glyphs were patched from, so every icon here has the shape it had as a glyph.
//
// Fonts were doing this job before. They rendered too small, because Theme.font
// names a font that is not installed on every host — text fell back to one
// family and the glyphs to another, and Qt sizes a fallback by its own em box.
// Icons stopped being at the mercy of the fontconfig chain when they stopped
// being text.
//
// The MDI files carry no fill, so they arrive black and MultiEffect recolours
// them. That is what buys back what a glyph gave for free: `color` is a plain
// property, so a themed icon re-tints on light/dark with no second asset.
Item {
    id: root

    required property string name
    property color color: Theme.text
    // Matched to the text it sits beside rather than to fontSize directly: a
    // glyph used to draw inside the em box, and an icon drawn to the same
    // number would read noticeably smaller than the letters next to it.
    property int size: Theme.fontSize + 4

    implicitWidth: size
    implicitHeight: size

    Image {
        id: src

        anchors.fill: parent
        source: root.name ? Qt.resolvedUrl("../icons/" + root.name + ".svg") : ""
        // Rasterised at twice the layout size: these land on a 1.5x scaled
        // output, and an SVG rendered at logical size is upscaled by the
        // compositor rather than re-rendered.
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        asynchronous: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: src
        colorization: 1.0
        colorizationColor: root.color
        // Without this the tint keeps the source's luminance, and a black
        // source stays black whatever colour it is given.
        brightness: 1.0
        visible: src.status === Image.Ready
    }
}
