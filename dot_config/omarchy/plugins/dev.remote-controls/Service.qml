import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui as Ui

Item {
    id: root
    property bool opened: false
    property bool appsMode: false
    property bool requested: false
    property string activeScreen: ""
    property string selected: ""
    property string closeTarget: ""
    onSelectedChanged: closeTarget = ""
    property int selectedWorkspace: 1
    property string message: ""
    property var windows: []
    readonly property string helper: Qt.resolvedUrl("control.py").toString().replace("file://", "")
    readonly property bool busy: snapshotProcess.running || actionProcess.running

    function open(payload) {
        if (busy) return
        requested = true
        closeTarget = ""
        message = ""
        snapshotProcess.running = true
    }
    function close() {
        requested = false
        closeTarget = ""
        opened = false
    }
    function toggle() {
        if (opened || requested) close()
        else {
            appsMode = false
            activeScreen = ""
            open("{}")
        }
    }
    function perform(action, workspace) {
        if (!selected || busy) return
        closeTarget = ""
        var args = ["python3", helper, action, selected]
        if (workspace !== undefined) args.push(String(workspace))
        actionProcess.command = args
        actionProcess.running = true
    }
    function requestClose() {
        if (!selected || busy) return
        if (closeTarget !== selected) closeTarget = selected
        else perform("close")
    }
    function acceptSnapshot(text) {
        var state = JSON.parse(text)
        windows = state.windows
        selected = state.active
        if (!windows.some(function(w) { return w.address === selected }))
            selected = windows.length ? windows[0].address : ""
        if (!activeScreen) activeScreen = state.screen
        opened = true
        requested = false
    }

    IpcHandler {
        target: "remote-controls"
        function toggle(): string { root.toggle(); return "ok" }
        function close(): string { root.close(); return "ok" }
        function apps(): string {
            root.appsMode = true
            if (!root.opened) { root.activeScreen = ""; root.open("{}") }
            return "ok"
        }
        function state(): string {
            return JSON.stringify({ opened: root.opened, apps: root.appsMode, appCount: DesktopEntries.applications.values.length, selected: root.selected, screen: root.activeScreen, error: root.message })
        }
    }
    Process {
        id: snapshotProcess
        command: ["python3", root.helper, "snapshot"]
        stdout: StdioCollector { id: snapshotOutput }
        stderr: StdioCollector { id: snapshotError }
        onExited: function(code) {
            if (!root.requested) return
            if (code !== 0) {
                root.message = snapshotError.text || "Could not read windows"
                root.requested = false
                root.opened = true
                return
            }
            try { root.acceptSnapshot(snapshotOutput.text) }
            catch (error) { root.message = String(error); root.requested = false; root.opened = true }
        }
    }
    Process {
        id: actionProcess
        stderr: StdioCollector { id: actionError }
        onExited: function(code) {
            if (code === 0) root.close()
            else root.message = actionError.text || "Window action failed"
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            property bool revealed: false
            property real revealProgress: root.opened && root.activeScreen === modelData.name ? 1 : 0
            readonly property bool expanded: (root.opened && root.activeScreen === modelData.name) || revealProgress > 0
            onRevealProgressChanged: if (revealProgress === 0 && !root.opened && !root.requested) root.appsMode = false
            Behavior on revealProgress {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            anchors { top: true; right: true }
            margins { top: panel.expanded ? 8 : 0; right: panel.expanded ? 8 : 0 }
            implicitWidth: expanded ? Math.min(Style.space(380), modelData.width - 16) : (revealed ? 56 : 18)
            implicitHeight: expanded ? Math.min(Style.space(650), modelData.height - 16) : 56
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "dev-remote-controls"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.opened && panel.expanded && root.appsMode ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            onExpandedChanged: if (!expanded) revealed = false

            Timer {
                id: revealTimer
                interval: 350
                onTriggered: panel.revealed = true
            }
            Timer {
                id: hideTimer
                interval: 900
                onTriggered: if (!hotspot.containsMouse) panel.revealed = false
            }
            Ui.BorderSurface {
                anchors.fill: parent
                visible: !panel.expanded
                color: panel.revealed ? Color.popups.background : "transparent"
                radius: Style.cornerRadius
                borderSpec: panel.revealed ? Border.surfaceSpec("popups", "border", Color.popups.border, Style.normalBorderWidth) : Border.none()
                RemoteMark {
                    anchors.centerIn: parent
                    visible: panel.revealed
                    width: 30
                    height: 30
                }
                MouseArea {
                    id: hotspot
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: { hideTimer.stop(); revealTimer.restart() }
                    onExited: { revealTimer.stop(); hideTimer.restart() }
                    onClicked: {
                        if (!panel.revealed) { panel.revealed = true; hideTimer.restart(); return }
                        root.activeScreen = panel.modelData.name
                        root.open("{}")
                    }
                }
            }
            Ui.BorderSurface {
                anchors.fill: parent
                visible: panel.expanded
                enabled: root.opened
                opacity: panel.revealProgress
                transform: Translate { x: (1 - panel.revealProgress) * Style.space(16) }
                color: Color.popups.background
                borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Style.normalBorderWidth)
                radius: Style.cornerRadius
                AppsPane {
                    anchors.fill: parent
                    anchors.margins: Style.space(14)
                    visible: panel.expanded && root.appsMode
                    onBack: root.appsMode = false
                    onDismiss: root.close()
                }
                ColumnLayout {
                    visible: !root.appsMode
                    anchors.fill: parent
                    anchors.margins: Style.space(14)
                    spacing: Style.space(8)
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "OmniPick"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; Layout.fillWidth: true }
                        Ui.Button { bordered: true; text: "Apps"; implicitHeight: 44; enabled: !root.busy; onClicked: { root.closeTarget = ""; root.appsMode = true } }
                        Ui.Button { bordered: true; text: "Hide panel"; implicitHeight: 44; onClicked: root.close() }
                    }
                    Text {
                        text: "Choose the window to control"
                        color: Color.foreground
                        font.family: Style.font.family; font.pixelSize: Style.font.body
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: root.windows
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 58
                            radius: Style.cornerRadius
                            color: windowMouse.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent)
                                : root.selected === modelData.address ? Style.selectedFillFor(Color.foreground, Color.accent) : "transparent"
                            Column {
                                anchors.fill: parent
                                anchors.margins: 6
                                Text { textFormat: Text.PlainText; width: parent.width; text: modelData.title || modelData.class || "Untitled"; color: Color.foreground; elide: Text.ElideRight; font.family: Style.font.family; font.pixelSize: Style.font.body }
                                Text { text: "Workspace " + (modelData.workspace ? modelData.workspace.name : "?"); color: Color.foreground; opacity: 0.7; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                            }
                            MouseArea { id: windowMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.selected = parent.modelData.address }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: root.message !== ""
                        text: root.message
                        color: Color.urgent
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        enabled: root.selected !== "" && !root.busy
                        Ui.Button { bordered: true; text: "Fullscreen"; implicitHeight: 48; Layout.fillWidth: true; onClicked: root.perform("fullscreen") }
                        Ui.Button { bordered: true; text: "Windowed"; implicitHeight: 48; Layout.fillWidth: true; onClicked: root.perform("windowed") }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: root.closeTarget !== ""
                        text: "Close the selected window? Unsaved progress may be lost."
                        textFormat: Text.PlainText
                        color: Color.urgent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Ui.Button { bordered: true;
                            text: root.closeTarget === "" ? "Close window" : "Confirm close window"
                            foreground: Color.urgent
                            implicitHeight: 48
                            Layout.fillWidth: true
                            enabled: root.selected !== "" && !root.busy
                            onClicked: root.requestClose()
                        }
                        Ui.Button { bordered: true;
                            text: "Cancel"
                            visible: root.closeTarget !== ""
                            implicitHeight: 48
                            onClicked: root.closeTarget = ""
                        }
                    }
                    Text { text: "Destination workspace"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 5
                        Repeater {
                            model: 10
                            Ui.Button { bordered: true;
                                required property int index
                                text: String(index + 1)
                                selected: root.selectedWorkspace === index + 1
                                implicitHeight: 44
                                Layout.fillWidth: true
                                onClicked: root.selectedWorkspace = index + 1
                            }
                        }
                    }
                    Ui.Button { bordered: true; text: "Move to workspace " + root.selectedWorkspace + " and follow"; implicitHeight: 48; Layout.fillWidth: true; enabled: root.selected !== "" && !root.busy; onClicked: root.perform("move", root.selectedWorkspace) }
                    RowLayout {
                        Layout.fillWidth: true
                        Ui.Button { bordered: true; text: "Refresh"; implicitHeight: 48; enabled: !root.busy; onClicked: root.open("{}") }
                        Ui.Button { bordered: true; text: "Show bar"; implicitHeight: 48; onClicked: Quickshell.execDetached(["omarchy", "toggle", "bar", "off"]) }
                        Ui.Button { bordered: true; text: "Back to window"; implicitHeight: 48; Layout.fillWidth: true; enabled: root.selected !== "" && !root.busy; onClicked: root.perform("focus") }
                    }
                }
            }
        }
    }
}
