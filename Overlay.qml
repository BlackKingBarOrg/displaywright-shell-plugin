import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
  id: root
  property bool opened: false
  function open(payload) { root.opened = true }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "#dd101014"
    WlrLayershell.namespace: "displaywright-arrange"
    WlrLayershell.layer: WlrLayer.Overlay
  }
}
