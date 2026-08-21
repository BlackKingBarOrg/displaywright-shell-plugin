import QtQuick


Rectangle {
  id: button

  property var pal: null
  property string label: ""
  property bool primary: false
  property bool enabled: true
  signal triggered()

  implicitWidth: text.implicitWidth + 26
  implicitHeight: 32
  radius: 8
  opacity: enabled ? 1 : 0.4
  color: pal ? (primary ? pal.accent : pal.active) : (primary ? "#3584e4" : "#242430")
  border.color: pal ? (primary ? pal.accent : pal.border) : "#33333f"
  border.width: 1

  Text {
    id: text
    anchors.centerIn: parent
    text: button.label
    color: button.pal ? (button.primary ? button.pal.selectedText : button.pal.text)
      : (button.primary ? "#ffffff" : "#e6e6ea")
    font.pixelSize: 13
  }

  MouseArea {
    anchors.fill: parent
    enabled: button.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: button.triggered()
  }
}
