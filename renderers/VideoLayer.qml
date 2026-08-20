// A looping video.
//
// Muted by default and paused whenever nobody can see it: a wallpaper that
// keeps a decoder busy behind a fullscreen window is a laptop that runs out of
// battery for no reason. Tile and Center have no meaning for a video stream,
// so they fall back to Fit.

import QtQuick
import QtMultimedia
import Quickshell.Hyprland
import qs.Commons

Item {
  id: layer

  property var src: null
  property real dpr: 1
  property var spanGeometry: null
  property string outputName: ""

  readonly property string path: src && src.path ? String(src.path) : ""
  readonly property string fit: spanGeometry ? "span" : (src && src.fit ? String(src.fit) : "fill")
  // Ready means "the outcome is known", failure included -- a file that will
  // never play must not leave the surface stuck on the previous wallpaper.
  readonly property bool ready: path.length === 0
                                || (player.mediaStatus !== MediaPlayer.NoMedia
                                    && player.mediaStatus !== MediaPlayer.LoadingMedia)

  // Hyprland reports fullscreen per workspace; the wallpaper under a fullscreen
  // window is not on screen, so stop decoding for it.
  readonly property bool covered: {
    if (!src || src.pauseWhenCovered === false) return false
    var monitors = Hyprland.monitors ? Hyprland.monitors.values : []
    for (var i = 0; i < monitors.length; i++) {
      if (String(monitors[i].name) !== layer.outputName) continue
      var workspace = monitors[i].activeWorkspace
      var ipc = workspace ? workspace.lastIpcObject : null
      return !!(ipc && ipc.hasfullscreen)
    }
    return false
  }

  readonly property bool shouldPlay: visible && path.length > 0 && !covered

  clip: true

  MediaPlayer {
    id: player
    source: layer.path.length > 0 ? Util.fileUrl(layer.path) : ""
    loops: MediaPlayer.Infinite
    videoOutput: output
    audioOutput: AudioOutput {
      muted: !layer.src || layer.src.mute !== false
      volume: layer.src && layer.src.volume ? Number(layer.src.volume) : 0
    }
    onErrorOccurred: function (error, message) {
      console.warn("displaywright: video wallpaper failed on " + layer.outputName + ": " + message)
    }
  }

  // Driven from a change handler rather than started once, so a fullscreen
  // window going up and coming back down toggles the decoder both ways.
  onShouldPlayChanged: shouldPlay ? player.play() : player.pause()
  Component.onCompleted: if (shouldPlay) player.play()

  VideoOutput {
    id: output

    width: layer.fit === "span" && layer.spanGeometry ? layer.spanGeometry.w : layer.width
    height: layer.fit === "span" && layer.spanGeometry ? layer.spanGeometry.h : layer.height
    x: layer.fit === "span" && layer.spanGeometry ? -layer.spanGeometry.dx : 0
    y: layer.fit === "span" && layer.spanGeometry ? -layer.spanGeometry.dy : 0

    fillMode: {
      switch (layer.fit) {
      case "stretch": return VideoOutput.Stretch
      // Tile and Center have no streaming equivalent; Fit is the honest
      // approximation and keeps the whole frame visible.
      case "fit":
      case "tile":
      case "center": return VideoOutput.PreserveAspectFit
      default: return VideoOutput.PreserveAspectCrop
      }
    }
  }
}
