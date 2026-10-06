// A text field with a placeholder.
import QtQuick
import QtQuick.Templates as T

T.TextField {
    id: input

    implicitHeight: 44 * Theme.unit
    leftPadding: 14 * Theme.unit
    rightPadding: 14 * Theme.unit
    verticalAlignment: TextInput.AlignVCenter
    color: Theme.text
    placeholderTextColor: Theme.muted
    selectionColor: Theme.accent
    selectedTextColor: Theme.text
    font.family: Theme.font
    font.pixelSize: 15 * Theme.unit

    background: Rectangle {
        color: Theme.field
        border.color: input.activeFocus ? Qt.rgba(1, 1, 1, 0.4) : Theme.border
    }
    // T.TextField draws no placeholder by itself.
    Text {
        x: input.leftPadding
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text === "" && input.preeditText === ""
        text: input.placeholderText
        color: input.placeholderTextColor
        font: input.font
    }
}
