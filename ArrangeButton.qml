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
  color: primary ? pal.accent : pal.active
  border.color: primary ? pal.accent : pal.border
  border.width: 1

  Text {
    id: text
    anchors.centerIn: parent
    text: button.label
    color: button.primary ? pal.selectedText : pal.text
    font.pixelSize: 13
  }

  MouseArea {
    anchors.fill: parent
    enabled: button.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: button.triggered()
  }
}
