// A still picture, placed the way Windows places one.
//
// Two of the fits are defined in *device* pixels rather than layout pixels:
// Center shows the file at its own resolution, and Tile repeats it at its own
// resolution. On a scaled display those are not the same thing as the layout
// coordinates everything else here uses, so both divide through by the
// output's device pixel ratio -- without that, a 3200x2000 photo centred on
// this 200%-scaled laptop panel would be drawn twice as large as the file is.

import QtQuick
import qs.Commons

Item {
  id: layer

  // Renderer contract, written by Surface.qml.
  property var src: null
  property real dpr: 1
  property var spanGeometry: null
  property string outputName: ""

  readonly property string path: src && src.path ? String(src.path) : ""
  readonly property url url: path.length > 0 ? Util.fileUrl(path) : Qt.resolvedUrl("")
  //: "span" is not a stored fit -- it is what a spanned source resolves to here.
  readonly property string fit: spanGeometry ? "span" : (src && src.fit ? String(src.fit) : "fill")
  readonly property bool tiling: fit === "tile"

  readonly property Image activeImage: tiling ? tileImage : plainImage
  readonly property bool ready: path.length === 0 || activeImage.status === Image.Ready

  clip: true

  Image {
    id: plainImage

    visible: !layer.tiling
    source: visible ? layer.url : Qt.resolvedUrl("")
    asynchronous: true
    cache: true
    smooth: true
    mipmap: true

    width: {
      if (layer.fit === "span") return layer.spanGeometry.w
      if (layer.fit === "center") return implicitWidth / layer.dpr
      return layer.width
    }
    height: {
      if (layer.fit === "span") return layer.spanGeometry.h
      if (layer.fit === "center") return implicitHeight / layer.dpr
      return layer.height
    }
    x: {
      if (layer.fit === "span") return -layer.spanGeometry.dx
      if (layer.fit === "center") return Math.round((layer.width - width) / 2)
      return 0
    }
    y: {
      if (layer.fit === "span") return -layer.spanGeometry.dy
      if (layer.fit === "center") return Math.round((layer.height - height) / 2)
      return 0
    }

    fillMode: {
      switch (layer.fit) {
      case "fit": return Image.PreserveAspectFit
      case "stretch": return Image.Stretch
      // Centre has already been given the exact size it wants, so there is
      // nothing left for the fill mode to decide.
      case "center": return Image.Stretch
      // Fill and span both cover their box and crop the overflow; span's box
      // is simply the whole desktop rather than this one output.
      default: return Image.PreserveAspectCrop
      }
    }
  }

  // Tiling repeats the file at its own resolution. The image is laid out at
  // device-pixel size and scaled back down, which is the only way to make one
  // tile land on exactly as many physical pixels as the file has.
  Image {
    id: tileImage

    visible: layer.tiling
    source: visible ? layer.url : Qt.resolvedUrl("")
    asynchronous: true
    cache: true
    smooth: true

    width: layer.width * layer.dpr
    height: layer.height * layer.dpr
    fillMode: Image.Tile
    horizontalAlignment: Image.AlignLeft
    verticalAlignment: Image.AlignTop
    transform: Scale {
      xScale: 1 / layer.dpr
      yScale: 1 / layer.dpr
    }
  }
}
