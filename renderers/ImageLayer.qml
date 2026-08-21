// A still picture, placed the way Windows places one.
//
// Every fit's geometry comes from lib/fits.mjs, the same module the
// arrangement overlay draws its preview from. That is deliberate: the fits used
// to be computed twice, once in QML for the screen and once in Python for the
// preview, and "the preview matches the screen" was a promise maintained by
// hand. Now it is one function, and the arithmetic has tests.
//
// Two of the fits are defined in *device* pixels rather than layout pixels:
// Center shows the file at its own resolution and Tile repeats it at its own
// resolution. On a scaled display those are not the same thing as the layout
// coordinates everything else uses, so both divide through by the output's
// device pixel ratio -- without that, a 3200x2000 photo centred on a
// 200%-scaled laptop panel would be drawn twice as large as the file is.

import QtQuick
import qs.Commons
import "../lib/fits.mjs" as Fits

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

  // The file's own pixel size, once it has been decoded. Zero until then, which
  // fits.mjs treats as "nothing to place" and answers with the whole box.
  readonly property real sourceWidth: plainImage.implicitWidth
  readonly property real sourceHeight: plainImage.implicitHeight

  // [x, y, w, h] for this fit, in this output's logical pixels.
  readonly property var placement: {
    if (fit === "span") {
      return Fits.spanRect(sourceWidth, sourceHeight,
                           spanGeometry.w, spanGeometry.h,
                           spanGeometry.dx, spanGeometry.dy)
    }
    return Fits.fittedRect(fit, sourceWidth, sourceHeight, layer.width, layer.height, layer.dpr)
  }

  clip: true

  Image {
    id: plainImage

    visible: !layer.tiling
    source: visible ? layer.url : Qt.resolvedUrl("")
    asynchronous: true
    cache: true
    smooth: true
    mipmap: true

    // The rectangle is already exact, so there is nothing left for a fill mode
    // to decide: stretching into a box of the right aspect ratio is the same
    // picture PreserveAspectCrop would have drawn, minus a second opinion about
    // where it goes.
    fillMode: Image.Stretch
    x: layer.placement[0]
    y: layer.placement[1]
    width: layer.placement[2]
    height: layer.placement[3]
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
