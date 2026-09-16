import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui as Ui
import "AppsModel.js" as AppsModel

ColumnLayout {
    id: root
    spacing: Style.space(8)
    property bool keyboardVisible: true
    signal back()
    signal dismiss()
    readonly property var matches: AppsModel.matchingEntries(DesktopEntries.applications.values || [], search.text)
    onVisibleChanged: {
        if (visible) {
            search.text = ""
            keyboardVisible = true
            search.forceActiveFocus()
        }
    }
    function launch(entry) {
        if (!entry || !entry.id) return
        // Use the same scoped desktop-entry launch path as Omarchy's app menu.
        Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", entry.id + ".desktop"])
        root.dismiss()
    }
    function typeCharacter(character) {
        if (search.selectedText.length) search.remove(search.selectionStart, search.selectionEnd)
        search.insert(search.cursorPosition, character)
        search.forceActiveFocus()
    }
    function erase() {
        if (search.selectedText.length) search.remove(search.selectionStart, search.selectionEnd)
        else if (search.cursorPosition > 0) search.remove(search.cursorPosition - 1, search.cursorPosition)
        search.forceActiveFocus()
    }
    Item {
        Layout.fillWidth: true
        implicitHeight: Math.max(backButton.implicitHeight, hideButton.implicitHeight)
        Ui.Button { bordered: true;
            id: backButton
            anchors.left: parent.left
            text: "Back"
            implicitHeight: 44
            onClicked: root.back()
        }
        Text {
            anchors.centerIn: parent
            width: Math.max(0, parent.width - 2 * Math.max(backButton.width, hideButton.width) - Style.space(12))
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: "Find an app"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
        }
        Ui.Button { bordered: true;
            id: hideButton
            anchors.right: parent.right
            text: "Hide panel"
            implicitHeight: 44
            onClicked: root.dismiss()
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Ui.TextField {
            id: search
            Layout.fillWidth: true
            implicitHeight: 48
            placeholderText: "Search apps…"
            onAccepted: if (root.matches.length) root.launch(root.matches[0])
        }
        Ui.Button { bordered: true; text: "Clear"; implicitHeight: 48; onClicked: { search.clear(); search.forceActiveFocus() } }
    }
    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: Style.space(4)
        model: root.matches
        ScrollBar.vertical: ScrollBar {}
        delegate: Ui.Button { bordered: true;
            required property var modelData
            width: ListView.view.width
            height: 52
            clip: true
            text: modelData.name || modelData.id
            leftAlign: true
            tooltipText: modelData.comment || modelData.id
            onClicked: root.launch(modelData)
        }
        Text {
            anchors.centerIn: parent
            visible: root.matches.length === 0
            text: "No matching apps"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }
    }
    Ui.Button { bordered: true;
        Layout.fillWidth: true
        implicitHeight: 44
        text: root.keyboardVisible ? "Hide touch keyboard" : "Show touch keyboard"
        onClicked: root.keyboardVisible = !root.keyboardVisible
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.keyboardVisible
        spacing: 2
        Repeater {
            model: ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"]
            RowLayout {
                required property string modelData
                Layout.fillWidth: true
                spacing: 2
                Repeater {
                    model: modelData.split("")
                    Ui.Button { bordered: true;
                        required property string modelData
                        text: modelData
                        implicitWidth: 0
                        implicitHeight: 44
                        horizontalPadding: 0
                        Layout.fillWidth: true
                        onClicked: root.typeCharacter(modelData)
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Ui.Button { bordered: true; text: "Space"; implicitHeight: 44; Layout.fillWidth: true; onClicked: root.typeCharacter(" ") }
            Ui.Button { bordered: true; text: "Backspace"; implicitHeight: 44; Layout.fillWidth: true; onClicked: root.erase() }
        }
    }
}
