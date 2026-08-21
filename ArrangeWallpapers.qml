// The wallpaper strip along the bottom of the arrangement.
//
// Horizontal, because the arrangement above it is what the space is for and a
// grid would push it off the panel. Clicking a picture gives it to whichever
// display is selected, so choosing a wallpaper and choosing where the display
// sits are one job in one window.

import QtQuick
import QtQuick.Layouts

Item {
  id: strip

  property var controller: null
  property var pal: null

  function c(role, fallback) { return pal && pal[role] !== undefined ? pal[role] : fallback }

  readonly property var files: controller ? controller.wallpaperFiles : []
  readonly property string currentPath: {
    if (!controller) return ""
    controller.wallpaperRevision
    return controller.wallpaperFor(controller.selectedName)
  }

  implicitHeight: 104

  ColumnLayout {
    anchors.fill: parent
    spacing: 6

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: {
          if (!strip.controller || !strip.controller.selectedName) return "Wallpaper"
          return "Wallpaper · " + strip.controller.selectedName
        }
        color: strip.c("muted", "#9a9aa6")
        font.pixelSize: 12
      }
      Item { Layout.fillWidth: true }

      ArrangeButton {
        objectName: "addWallpaper"
        pal: strip.pal
        label: "Add…"
        onTriggered: if (strip.controller) strip.controller.addWallpaper()
      }
      ArrangeButton {
        objectName: "followTheme"
        pal: strip.pal
        label: "Follow theme"
        enabled: strip.currentPath !== ""
        onTriggered: if (strip.controller) strip.controller.clearWallpaper()
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      radius: 10
      color: strip.c("active", "#242430")
      border.color: strip.c("border", "#33333f")
      border.width: 1

      Text {
        anchors.centerIn: parent
        visible: strip.files.length === 0
        text: "No pictures found — use Add… to bring one in"
        color: strip.c("placeholder", "#6f6f7b")
        font.pixelSize: 12
      }

      ListView {
        id: list
        objectName: "wallpaperList"
        anchors.fill: parent
        anchors.margins: 6
        orientation: ListView.Horizontal
        spacing: 8
        clip: true
        model: strip.files
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
          required property string modelData
          objectName: "wallpaper-" + modelData.split("/").pop()
          width: 108
          height: list.height
          radius: 8
          color: "transparent"
          border.width: modelData === strip.currentPath ? 2 : 1
          border.color: modelData === strip.currentPath
            ? strip.c("selectedBorder", "#6aa3f0")
            : strip.c("border", "#33333f")

          Image {
            anchors.fill: parent
            anchors.margins: 2
            source: "file://" + parent.modelData
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize.width: 216      // decode small: a strip of 4K files is
            sourceSize.height: 128     // otherwise a hundred megabytes of RAM
            clip: true
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (strip.controller) strip.controller.setWallpaper(parent.modelData)
          }
        }
      }
    }
  }
}
