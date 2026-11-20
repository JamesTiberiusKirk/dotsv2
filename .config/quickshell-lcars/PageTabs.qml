import QtQuick
import "."

// Pill tabs for a station's pages. `page` is the selected index.
Row {
    id: tabs
    property var pages: []
    property int page: 0
    spacing: Lc.gap
    Repeater {
        model: tabs.pages
        Pill {
            required property string modelData
            required property int index
            text: modelData
            toggle: true
            on: tabs.page === index
            tint: Lc.orange
            height: 56
            labelSize: 18
            onClicked: tabs.page = index
        }
    }
}
