// The login screen: the date and the system menus along the top, and in the
// middle the person who signs in and their password.
import QtQml
import QtQuick
import SddmComponents as Sddm

Item {
    id: root

    property int userIndex: userModel.lastIndex
    // Without a list of users, the name is typed.
    readonly property var user: users.count > 0 ? users.objectAt(Math.max(0, userIndex)) : null
    readonly property string userName: user ? user.name : nameInput.text
    property bool reveal: false
    property bool busy: false
    property string message
    property date now: new Date()

    function displayName(person) { return person.realName !== "" ? person.realName : person.name }

    // The first letters of the first two words: "Alex Rivera" is "AR".
    function initials(name) {
        return name.split(/\s+/).filter(word => word !== "").slice(0, 2)
            .map(word => word[0].toUpperCase()).join("")
    }

    function login() {
        if (busy || userName === "")
            return
        // SDDM reports a missing session like a wrong password.
        if (sessionModel.count === 0) {
            message = qsTr("No desktop session is installed")
            return
        }
        busy = true
        message = ""
        sddm.login(userName, password.text, sessionModel.lastIndex)
    }

    function closeMenus() { userMenu.open = accessibilityMenu.open = powerMenu.open = false }

    Keys.onEscapePressed: closeMenus()
    Component.onCompleted: (user ? password : nameInput).forceActiveFocus()

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            root.message = text.loginFailed
            password.clear()
            password.forceActiveFocus()
        }
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }
    // SDDM's own texts, which it ships translated.
    Sddm.TextConstants { id: text }
    Instantiator {
        id: users
        model: userModel
        QtObject {
            required property string name
            required property string realName
        }
    }

    Backdrop { anchors.fill: parent }

    // The click that closes an open menu.
    MouseArea {
        anchors.fill: parent
        z: 1
        visible: userMenu.open || accessibilityMenu.open || powerMenu.open
        onClicked: root.closeMenus()
    }

    Row {
        x: 14 * Theme.unit
        height: 44 * Theme.unit
        spacing: 8 * Theme.unit

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.locale().toString(root.now, "ddd d MMM")
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: 13 * Theme.unit
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.locale().toString(root.now, "HH:mm")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13 * Theme.unit
            font.weight: Font.DemiBold
        }
    }

    IconButton {
        id: powerButton
        anchors.right: parent.right
        anchors.rightMargin: 12 * Theme.unit
        y: 7 * Theme.unit
        visible: powerMenu.entries.length > 0
        path: "M12 3v9M6.3 6.3a8 8 0 1 0 11.4 0"
        onClicked: powerMenu.toggle()
    }
    Menu {
        id: powerMenu
        anchors.right: powerButton.right
        anchors.top: powerButton.bottom
        anchors.topMargin: 4 * Theme.unit
        returnFocus: password
        entries: [
            { text: text.suspend, available: sddm.canSuspend, run: () => sddm.suspend() },
            { text: text.reboot, available: sddm.canReboot, run: () => sddm.reboot() },
            { text: text.shutdown, available: sddm.canPowerOff, run: () => sddm.powerOff() }
        ].filter(entry => entry.available)
    }
    // The language of the system. SDDM's Wayland greeter cannot switch the
    // language or the keyboard layout, so this only shows it.
    Icon {
        id: language
        anchors.right: powerButton.left
        anchors.rightMargin: 10 * Theme.unit
        anchors.verticalCenter: powerButton.verticalCenter
        size: 22 * Theme.unit
        path: "M4 3h16a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-9l-4 4v-4H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"

        Text {
            x: (parent.width - width) / 2
            y: parent.height * 0.395 - height / 2
            text: Qt.locale().name.substring(0, 2).toUpperCase()
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 8 * Theme.unit
            font.weight: Font.Bold
        }
    }
    IconButton {
        id: accessibilityButton
        anchors.right: language.left
        anchors.rightMargin: 8 * Theme.unit
        anchors.verticalCenter: powerButton.verticalCenter
        path: "M12 2a10 10 0 1 0 0 20a10 10 0 1 0 0-20zM12 6.6a.6.6 0 1 0 0 1.2a.6.6 0 1 0 0-1.2z"
            + "M7.5 10.2l4.5 1l4.5-1M12 11.2v3.3l-2.3 3.6M12 14.5l2.3 3.6"
        onClicked: accessibilityMenu.toggle()
    }
    Menu {
        id: accessibilityMenu
        anchors.right: accessibilityButton.right
        anchors.top: accessibilityButton.bottom
        anchors.topMargin: 4 * Theme.unit
        returnFocus: password
        entries: [{ text: qsTr("Large text"), checked: Theme.unit > 1, run: () => Theme.unit = Theme.unit > 1 ? 1 : 1.25 }]
    }

    Avatar {
        id: avatar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -94 * Theme.unit
        initials: root.initials(root.user ? root.displayName(root.user) : root.userName)
    }

    // The person's name; with several people, it opens the list of them.
    Rectangle {
        id: person
        visible: root.user !== null
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: avatar.verticalCenter
        anchors.verticalCenterOffset: 82 * Theme.unit
        width: personRow.width + 20 * Theme.unit
        height: 34 * Theme.unit
        color: personArea.containsMouse && personArea.enabled ? Theme.hover : "transparent"
        border.color: activeFocus ? Theme.text : "transparent"
        activeFocusOnTab: users.count > 1
        Keys.onReturnPressed: userMenu.toggle()
        Keys.onEnterPressed: userMenu.toggle()
        Keys.onSpacePressed: userMenu.toggle()

        Row {
            id: personRow
            anchors.centerIn: parent
            spacing: 8 * Theme.unit

            Text {
                text: root.user ? root.displayName(root.user) : ""
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 20 * Theme.unit
                font.weight: Font.DemiBold
            }
            Icon {
                visible: users.count > 1
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 1 * Theme.unit
                size: 14 * Theme.unit
                path: "M6 9l6 6 6-6"
            }
        }
        MouseArea {
            id: personArea
            anchors.fill: parent
            enabled: users.count > 1
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: userMenu.toggle()
        }
    }
    Menu {
        id: userMenu
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: person.bottom
        anchors.topMargin: 4 * Theme.unit
        returnFocus: password
        entries: Array.from({ length: users.count }, (_, index) => {
            const name = root.displayName(users.objectAt(index))
            return { text: name, initials: root.initials(name), run: () => {
                root.userIndex = index
                root.message = ""
                password.clear()
            } }
        })
    }
    Entry {
        id: nameInput
        visible: root.user === null
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: person.verticalCenter
        width: 346 * Theme.unit
        enabled: !root.busy
        placeholderText: text.userName
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
        onAccepted: password.forceActiveFocus()
    }

    Entry {
        id: password
        anchors.left: nameInput.left
        anchors.right: submit.left
        anchors.verticalCenter: avatar.verticalCenter
        anchors.verticalCenterOffset: (root.user ? 144 : 140) * Theme.unit
        rightPadding: 44 * Theme.unit
        enabled: !root.busy
        placeholderText: text.password
        echoMode: root.reveal ? TextInput.Normal : TextInput.Password
        passwordCharacter: "●"
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
        onAccepted: root.login()

        // Shows or hides the typed password.
        IconButton {
            anchors.right: parent.right
            anchors.rightMargin: 7 * Theme.unit
            anchors.verticalCenter: parent.verticalCenter
            iconSize: 16 * Theme.unit
            path: "M2 12s3.6-7 10-7s10 7 10 7s-3.6 7-10 7S2 12 2 12zM12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6z"
                + (root.reveal ? "M4 4l16 16" : "")
            onClicked: root.reveal = !root.reveal
        }
    }
    IconButton {
        id: submit
        anchors.right: nameInput.right
        anchors.verticalCenter: password.verticalCenter
        width: 47 * Theme.unit
        height: password.height
        fill: Theme.accent
        opacity: root.busy ? 0.6 : 1
        path: "M5 12h14M13 6l6 6l-6 6"
        onClicked: root.login()
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: password.bottom
        anchors.topMargin: 12 * Theme.unit
        text: root.message !== "" ? root.message : keyboard.capsLock ? text.capslockWarning : ""
        color: root.message !== "" ? Theme.danger : Theme.muted
        font.family: Theme.font
        font.pixelSize: 13 * Theme.unit
    }
}
