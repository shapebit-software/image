// A menu that opens under its button. Each entry of `entries` has a `text`,
// a `run` function, and optionally `initials` (shown as an avatar) or
// `checked`. Main.qml closes it on Escape or a click elsewhere.
import QtQuick

Rectangle {
    id: menu

    property var entries: []
    property bool open: false
    // Gets the keyboard focus back when the menu closes.
    property Item returnFocus

    function toggle() {
        open = !open
        if (open)
            rows.itemAt(0).forceActiveFocus()
    }

    visible: open
    z: 2
    width: column.width + 2
    height: column.height + 2
    color: Theme.panel
    border.color: Theme.border
    onOpenChanged: if (!open && returnFocus) returnFocus.forceActiveFocus()

    Column {
        id: column
        x: 1
        y: 1

        Repeater {
            id: rows
            model: menu.entries

            Rectangle {
                id: row

                required property var modelData

                function run() {
                    menu.open = false
                    modelData.run()
                }

                width: Math.max(180 * Theme.unit, label.implicitWidth + 64 * Theme.unit)
                height: 38 * Theme.unit
                color: area.containsMouse || activeFocus ? Theme.hover : "transparent"
                activeFocusOnTab: true
                Keys.onReturnPressed: run()
                Keys.onEnterPressed: run()
                Keys.onSpacePressed: run()
                Keys.onUpPressed: nextItemInFocusChain(false).forceActiveFocus()
                Keys.onDownPressed: nextItemInFocusChain(true).forceActiveFocus()

                Avatar {
                    id: avatar
                    visible: row.modelData.initials !== undefined
                    x: 10 * Theme.unit
                    anchors.verticalCenter: parent.verticalCenter
                    size: 24 * Theme.unit
                    initials: row.modelData.initials ?? ""
                }
                Text {
                    id: label
                    x: (avatar.visible ? 44 : 14) * Theme.unit
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.text
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14 * Theme.unit
                }
                Icon {
                    visible: row.modelData.checked === true
                    anchors.right: parent.right
                    anchors.rightMargin: 12 * Theme.unit
                    anchors.verticalCenter: parent.verticalCenter
                    size: 16 * Theme.unit
                    path: "M5 12l5 5 9-10"
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.run()
                }
            }
        }
    }
}
