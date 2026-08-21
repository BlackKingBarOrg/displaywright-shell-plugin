// Pick one of a list. A real list: cycling through eleven resolutions one
// click at a time was the first thing that got called out, and a control whose
// current value is one click ahead of what you can see is worse than useless.
//
// The list is drawn inside the overlay rather than in a window of its own --
// there is nothing above a fullscreen layer surface to put a popup in.

import QtQuick

Item {
  id: select

  property var pal: null
  //: An Item above the layouts to draw the list in. Without it the list is
  //: covered by whatever is laid out after this control.
  property var popupLayer: null
  property var options: []
  property string current: ""
  //: The list, which lives in popupLayer rather than under this item.
  readonly property alias popup: list
  property bool open: false
  signal picked(string value)

  function c(role, fallback) { return pal && pal[role] !== undefined ? pal[role] : fallback }

  implicitWidth: Math.max(96, label.implicitWidth + 34)
  implicitHeight: 30

  Rectangle {
    id: field
    anchors.fill: parent
    radius: 8
    color: c("active", "#242430")
    border.color: select.open ? c("accent", "#3584e4") : c("border", "#33333f")
    border.width: 1

    Text {
      id: label
      anchors.left: parent.left
      anchors.leftMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      text: select.current
      color: c("text", "#e6e6ea")
      font.pixelSize: 13
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: 9
      anchors.verticalCenter: parent.verticalCenter
      text: "⌄"
      color: c("muted", "#9a9aa6")
      font.pixelSize: 13
      visible: select.options.length > 1
    }

    MouseArea {
      anchors.fill: parent
      enabled: !!select.options && select.options.length > 1
      cursorShape: Qt.PointingHandCursor
      onClicked: select.open = !select.open
    }
  }

  // Above everything else in the sidebar, and tall enough for a real mode list
  // without running off the panel.
  onOpenChanged: if (open) place()

  //: Positioned once on opening: the panel does not move while a list is down,
  //: and a binding through mapToItem would not re-evaluate when it did anyway.
  function place() {
    if (!list.parent || list.parent === select) return
    var p = select.mapToItem(list.parent, 0, select.height + 4)
    list.x = p.x
    list.y = p.y
  }

  //: Catches the click that dismisses the list, so it neither stays open nor
  //: lets the click through to the canvas behind it.
  MouseArea {
    objectName: "dismiss"
    parent: select.popupLayer ? select.popupLayer : select
    anchors.fill: parent
    visible: select.open
    z: 99
    onClicked: select.open = false
  }

  Rectangle {
    id: list
    objectName: "list"
    parent: select.popupLayer ? select.popupLayer : select
    visible: select.open
    z: 100
    width: Math.max(select.width, 132)
    height: Math.min(view.contentHeight + 8, 216)
    radius: 8
    color: c("background", "#16161d")
    border.color: c("border", "#33333f")
    border.width: 1

    ListView {
      id: view
      objectName: "listView"
      anchors.fill: parent
      anchors.margins: 4
      clip: true
      model: select.options
      boundsBehavior: Flickable.StopAtBounds

      delegate: Rectangle {
        required property string modelData
        objectName: "option-" + modelData
        width: view.width
        height: 26
        radius: 6
        color: modelData === select.current ? select.c("selectedBackground", "#25324a")
          : (hover.hovered ? select.c("active", "#242430") : "transparent")

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          text: parent.modelData
          color: select.c("text", "#e6e6ea")
          font.pixelSize: 13
        }

        HoverHandler { id: hover }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            select.open = false
            select.picked(parent.modelData)
          }
        }
      }
    }
  }
}
