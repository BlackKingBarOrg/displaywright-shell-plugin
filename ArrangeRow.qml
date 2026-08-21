import QtQuick

import QtQuick.Layouts

RowLayout {
  property var pal: null
  property string label: ""
  default property alias content: holder.data

  Layout.fillWidth: true
  spacing: 8

  Text {
    text: parent.label
    color: pal.muted
    font.pixelSize: 13
    Layout.preferredWidth: 84
  }
  RowLayout { id: holder; Layout.fillWidth: true; spacing: 6 }
}
