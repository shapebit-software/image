// A person's initials on a disc.
import QtQuick

Rectangle {
    property real size: 100 * Theme.unit
    property alias initials: label.text

    width: size
    height: size
    radius: size / 2
    color: Theme.accent
    border.color: Qt.rgba(1, 1, 1, 0.25)
    border.width: Math.max(1, size / 40)

    Text {
        id: label
        anchors.centerIn: parent
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: parent.size * 0.34
        font.weight: Font.DemiBold
    }
}
