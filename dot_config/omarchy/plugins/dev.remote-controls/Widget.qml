import QtQuick
import Quickshell
import qs.Ui

BarIconButton {
    id: widget
    iconComponent: Component { RemoteMark { ink: widget.foreground } }
    tooltipText: "OmniPick (Super+F12)"
    onPressed: function(button) {
        if (button === Qt.LeftButton)
            Quickshell.execDetached(["omarchy-shell", "remote-controls", "toggle"])
    }
}
