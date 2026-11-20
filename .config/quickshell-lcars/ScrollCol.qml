import QtQuick
import QtQuick.Layouts
import "."

// A vertically scrolling column for page content: children stack in a
// ColumnLayout, the whole thing flicks only when it overflows.
Flickable {
    id: f
    default property alias body: col.data
    contentHeight: col.implicitHeight
    contentWidth: width
    clip: true
    interactive: contentHeight > height   // content that fits never takes a drifting tap
    boundsBehavior: Flickable.StopAtBounds
    ColumnLayout { id: col; width: f.width; spacing: 14 }
}
