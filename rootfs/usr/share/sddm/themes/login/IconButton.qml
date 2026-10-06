// A button that shows only an icon; reachable with Tab, pressed with Enter or Space.
import QtQuick

Rectangle {
    id: button

    property alias path: icon.path
    property alias iconSize: icon.size
    property color fill: "transparent"
    default property alias content: icon.data

    signal clicked()

    implicitWidth: 30 * Theme.unit
    implicitHeight: 30 * Theme.unit
    color: fill.a > 0 ? (area.pressed ? Qt.darker(fill, 1.15) : area.containsMouse ? Qt.lighter(fill, 1.1) : fill)
        : area.containsMouse ? Theme.hover : "transparent"
    border.color: activeFocus ? Theme.text : "transparent"
    activeFocusOnTab: true
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    Keys.onSpacePressed: clicked()

    Icon {
        id: icon
        anchors.centerIn: parent
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
