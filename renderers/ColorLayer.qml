// A flat colour. Also the stand-in for a source kind this build cannot draw,
// so an unknown entry shows the backdrop instead of a black hole.

import QtQuick

Item {
  id: layer

  property var src: null
  property real dpr: 1
  property var spanGeometry: null
  property string outputName: ""

  readonly property bool ready: true

  Rectangle {
    anchors.fill: parent
    color: {
      var value = String(layer.src && layer.src.color ? layer.src.color : "#000000")
      return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(value) ? value : "#000000"
    }
  }
}
