// A one-click cycler. A dropdown would be better, but this is the whole of what
// picking from a short list needs and it costs no popup plumbing.
import QtQuick


Rectangle {
  id: cycler

  property var pal: null
  property var options: []
  property string current: ""
  signal picked(string value)

  implicitWidth: Math.max(72, label.implicitWidth + 22)
  implicitHeight: 30
  radius: 8
  color: pal ? pal.active : "#242430"
  border.color: pal ? pal.border : "#33333f"
  border.width: 1

  Text {
    id: label
    anchors.centerIn: parent
    text: cycler.current
    color: cycler.pal ? cycler.pal.text : "#e6e6ea"
    font.pixelSize: 13
  }

  MouseArea {
    anchors.fill: parent
    enabled: !!cycler.options && cycler.options.length > 1
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      const i = cycler.options.indexOf(cycler.current)
      cycler.picked(cycler.options[(i + 1) % cycler.options.length])
    }
  }
}
