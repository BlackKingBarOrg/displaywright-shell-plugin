// One wallpaper surface, covering one output.
//
// What it draws is decided in this order: a spanned source if one is set, then
// this output's own source, then the Omarchy theme background. Changing any of
// those crossfades through a slanted wipe rather than cutting, and a theme
// switch applies its palette at the moment the wipe starts so the bar and the
// picture change together.

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui

PanelWindow {
  id: surface

  required property var modelData
  property var controller: null

  screen: modelData

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "displaywright"
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  visible: !remapGuard.remapping

  // A background surface that parks its render loop has been seen to lose its
  // committed buffer and leave the desktop black. Wallpapers are cheap to keep
  // alive, so correctness wins over the saved repaints.
  updatesEnabled: true

  ScreenMoveRemap {
    id: remapGuard
    window: surface
  }

  // Moving a display changes where a spanned image is cut, and the controller
  // owns that arithmetic for every surface at once.
  Connections {
    target: surface.screen
    enabled: surface.controller !== null
    function onXChanged() { surface.controller.refreshSpanBox() }
    function onYChanged() { surface.controller.refreshSpanBox() }
    function onWidthChanged() { surface.controller.refreshSpanBox() }
    function onHeightChanged() { surface.controller.refreshSpanBox() }
  }

  // ------------------------------------------------------- what to draw

  readonly property string outputName: screen ? String(screen.name) : ""
  readonly property real dpr: screen && screen.devicePixelRatio > 0 ? screen.devicePixelRatio : 1

  readonly property var pinnedSource: controller ? controller.sourceFor(outputName) : null
  readonly property bool spanning: !!(controller && controller.spanSource && controller.spanBox)

  // Where this output sits inside the bounding box of every output, and how
  // big that box is. Null unless a spanned source is active.
  readonly property var spanGeometry: {
    if (!spanning) return null
    var box = controller.spanBox
    if (!box || box.w <= 0 || box.h <= 0 || !screen) return null
    return { dx: screen.x - box.x, dy: screen.y - box.y, w: box.w, h: box.h }
  }

  readonly property bool followsTheme: pinnedSource === null

  // The theme background is modelled as an ordinary source so the renderers
  // need no special case for it.
  readonly property var effectiveSource: {
    if (pinnedSource) return pinnedSource
    var path = controller ? String(controller.themeBackground || "") : ""
    if (path.length === 0) return null
    return { kind: "image", path: path, fit: "fill" }
  }

  // Identity of a source for change detection. Span geometry is deliberately
  // left out: nudging a display should re-cut the picture, not wipe to it.
  function signatureOf(src) {
    if (!src) return ""
    if (String(src.kind) === "color") return "color|" + String(src.color || "")
    return [String(src.kind || "image"), String(src.path || ""), String(src.fit || "fill"),
            String(src.backdrop || "")].join("|")
  }

  readonly property string effectiveSignature: signatureOf(effectiveSource)

  // ------------------------------------------------------- transition state

  property var shownSource: null
  property var incomingSource: null
  property real revealProgress: 1

  onEffectiveSignatureChanged: adopt()

  function adopt() {
    var next = effectiveSource
    if (!next) {
      shownSource = null
      incomingSource = null
      revealProgress = 1
      return
    }
    if (!shownSource || signatureOf(shownSource) === "") {
      // First picture on this surface: no transition to run.
      shownSource = next
      incomingSource = null
      revealProgress = 1
      if (controller) controller.applyPendingTheme()
      return
    }
    if (signatureOf(next) === signatureOf(shownSource)) {
      incomingSource = null
      revealProgress = 1
      return
    }
    revealAnimation.stop()
    // Order matters: assigning incomingSource synchronously re-runs the
    // incoming loader's bindings, and whatever they trigger has to see a
    // transition already in progress. Zero the progress first, then start the
    // reveal by hand -- a picture that is already decoded fires no further
    // readyChanged, so waiting for one would hang the surface on the old image.
    revealProgress = 0
    incomingSource = next
    maybeStartReveal()
  }

  // The wipe waits for the incoming picture to be decoded, so it never reveals
  // an empty rectangle on a slow disk.
  function maybeStartReveal() {
    if (!incomingSource || revealProgress !== 0) return
    if (!incomingLoader.item || !incomingLoader.item.ready) {
      revealTimeout.restart()
      return
    }
    revealTimeout.stop()
    if (controller) controller.applyPendingTheme()
    revealAnimation.restart()
  }

  // Last resort. Every renderer is supposed to report ready eventually, even
  // on failure, but a surface that believes otherwise would sit on the old
  // wallpaper forever and give no clue why.
  Timer {
    id: revealTimeout
    interval: 3000
    onTriggered: {
      if (!surface.incomingSource || surface.revealProgress !== 0) return
      console.warn("displaywright: " + surface.outputName
                   + " gave up waiting for " + surface.signatureOf(surface.incomingSource))
      if (surface.controller) surface.controller.applyPendingTheme()
      revealAnimation.restart()
    }
  }

  NumberAnimation {
    id: revealAnimation
    target: surface
    property: "revealProgress"
    from: 0
    to: 1
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      // Promote the incoming picture but keep it drawn until the bottom layer
      // has the same one ready, otherwise the handover shows one bare frame.
      revealTimeout.stop()
      if (surface.incomingSource) surface.shownSource = surface.incomingSource
      surface.revealProgress = 1
    }
  }

  function retireIncoming() {
    if (!incomingSource || revealProgress < 1) return
    if (signatureOf(shownSource) !== signatureOf(incomingSource)) return
    if (!shownLoader.item || !shownLoader.item.ready) return
    incomingSource = null
  }

  Component.onCompleted: adopt()

  // ------------------------------------------------------------- rendering

  function rendererFor(src) {
    if (!src) return ""
    switch (String(src.kind)) {
    case "color": return Qt.resolvedUrl("renderers/ColorLayer.qml")
    case "video": return Qt.resolvedUrl("renderers/VideoLayer.qml")
    case "image": return Qt.resolvedUrl("renderers/ImageLayer.qml")
    default:
      // A config written by a newer displaywright. Draw the backdrop rather than
      // a black rectangle, and say why in the log exactly once per change.
      console.warn("displaywright: no renderer for kind '" + String(src.kind) + "' on " + surface.outputName)
      return Qt.resolvedUrl("renderers/ColorLayer.qml")
    }
  }

  // Shows through wherever a Fit or Center does not reach.
  Rectangle {
    anchors.fill: parent
    color: {
      var src = surface.shownSource
      if (!src) return "#000000"
      var value = String(src.backdrop || "#000000")
      return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(value) ? value : "#000000"
    }
  }

  Loader {
    id: shownLoader
    anchors.fill: parent
    property var src: surface.shownSource
    source: surface.rendererFor(src)
    onSrcChanged: surface.retireIncoming()
    onLoaded: {
      if (!item) return
      item.src = Qt.binding(function() { return shownLoader.src })
      item.dpr = Qt.binding(function() { return surface.dpr })
      item.spanGeometry = Qt.binding(function() { return surface.spanGeometry })
      item.outputName = Qt.binding(function() { return surface.outputName })
      item.readyChanged.connect(surface.retireIncoming)
      surface.retireIncoming()
    }
  }

  Item {
    id: incomingLayer
    anchors.fill: parent
    visible: surface.incomingSource !== null
    layer.enabled: surface.incomingSource !== null && surface.revealProgress < 1
    layer.smooth: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: revealMask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 0.02
    }

    Rectangle {
      anchors.fill: parent
      color: {
        var src = surface.incomingSource
        if (!src) return "#000000"
        var value = String(src.backdrop || "#000000")
        return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(value) ? value : "#000000"
      }
    }

    Loader {
      id: incomingLoader
      anchors.fill: parent
      property var src: surface.incomingSource
      source: src ? surface.rendererFor(src) : ""
      onSrcChanged: surface.maybeStartReveal()
      onLoaded: {
        if (!item) return
        item.src = Qt.binding(function() { return incomingLoader.src })
        item.dpr = Qt.binding(function() { return surface.dpr })
        item.spanGeometry = Qt.binding(function() { return surface.spanGeometry })
        item.outputName = Qt.binding(function() { return surface.outputName })
        item.readyChanged.connect(surface.maybeStartReveal)
        surface.maybeStartReveal()
      }
    }
  }

  // A slanted band opening from the centre outwards. The skew is a fraction of
  // the surface height so the angle reads the same on a 16:9 panel and on an
  // ultrawide.
  Item {
    id: revealMask
    anchors.fill: parent
    visible: false
    layer.enabled: true

    readonly property real skew: 0.09 * height
    readonly property real reach: width / 2 + Math.abs(skew) + 4
    readonly property real spread: reach * surface.revealProgress

    Shape {
      anchors.fill: parent
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: "white"
        strokeColor: "transparent"
        startX: revealMask.width / 2 - revealMask.skew - revealMask.spread
        startY: 0
        PathLine {
          x: revealMask.width / 2 - revealMask.skew + revealMask.spread
          y: 0
        }
        PathLine {
          x: revealMask.width / 2 + revealMask.skew + revealMask.spread
          y: revealMask.height
        }
        PathLine {
          x: revealMask.width / 2 + revealMask.skew - revealMask.spread
          y: revealMask.height
        }
        PathLine {
          x: revealMask.width / 2 - revealMask.skew - revealMask.spread
          y: 0
        }
      }
    }
  }

  // Double-click acts on whatever governs this output: displaywright's own
  // window where it decides the picture, Omarchy's switcher where the theme
  // still does. Right-click always reaches the theme switcher, as before.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onDoubleClicked: function (mouse) {
      if (mouse.button === Qt.RightButton) themeSwitcherProc.running = true
      else if (surface.followsTheme) backgroundSwitcherProc.running = true
      else displaywrightProc.running = true
      mouse.accepted = true
    }
  }

  Process {
    id: backgroundSwitcherProc
    command: ["bash", "-c",
      "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
  }

  Process {
    id: themeSwitcherProc
    command: ["bash", "-c",
      "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
  }

  Process {
    id: displaywrightProc
    command: ["displaywright"]
  }
}
