// The arrangement interface, driven offscreen against a fake controller.
//
// This exists because testing inside omarchy-shell costs a restart per change
// and reports cached components as if they were the new ones. Everything below
// runs under qmltestrunner with no compositor: it builds the real view, the
// real canvas and the real sidebar, and drives them through the same contract
// Arrange.qml implements.

import QtQuick
import QtTest
import ".." as Dw
import "../lib/geometry.mjs" as Geo
import "../lib/snapping.mjs" as Snap
import "../lib/luawriter.mjs" as Lua

TestCase {
  id: suite
  name: "arrange"
  when: windowShown
  width: 1200
  visible: true
  height: 800

  function monitor(name, w, h, x, y, scale) {
    return Geo.stateFromHyprctl({
      name: name, description: name, make: "Acme", model: name,
      physicalWidth: 340, physicalHeight: 220,
      width: w, height: h, refreshRate: 60,
      x: x, y: y, scale: scale === undefined ? 1 : scale,
      transform: 0, disabled: false, mirrorOf: "none", focused: false,
      availableModes: [w + "x" + h + "@60.00Hz", w + "x" + h + "@120.00Hz"],
    })
  }

  // Stands in for Arrange.qml: the same properties and actions, with the
  // compositor calls recorded instead of made.
  Component {
    id: fakeController
    QtObject {
      property var geo: Geo
      property var snap: Snap
      property var lua: Lua
      property var states: []
      property var liveStates: []
      property string selectedName: ""
      property int revision: 0
      property string busy: ""
      property string notice: ""
      property int countdown: 0
      property bool hidden: false
      property int applyCalls: 0
      property int keepCalls: 0
      property int revertCalls: 0

      function touch() { revision += 1 }
      function hide() { hidden = true }
      function apply() { applyCalls += 1 }
      function keep() { keepCalls += 1 }
      function revert() { revertCalls += 1 }
      function autoArrange() { snap.autoArrange(states); touch() }

      readonly property var selected: {
        revision
        for (var i = 0; i < states.length; i++) {
          if (states[i].name === selectedName) return states[i]
        }
        return null
      }
      readonly property bool dirty: {
        revision
        if (states.length !== liveStates.length) return true
        for (var i = 0; i < states.length; i++) {
          if (!geo.configEquals(states[i], liveStates[i])) return true
        }
        return false
      }
      readonly property var problems: { revision; return snap.validate(states) }
    }
  }

  Component { id: paletteComp; Dw.ArrangePalette {} }
  Component { id: viewComp; Dw.ArrangeView {} }

  property var controller: null
  property var view: null

  function init() {
    controller = fakeController.createObject(suite)
    controller.states = [monitor("eDP-1", 3200, 2000, 0, 0, 2), monitor("DP-1", 2560, 1440, 1600, 0)]
    controller.liveStates = controller.states.map(Geo.copyState)
    controller.selectedName = "eDP-1"
    view = viewComp.createObject(suite, {
      controller: controller,
      pal: paletteComp.createObject(suite),
      width: 1100, height: 720,
    })
    wait(0)
  }

  function cleanup() {
    if (view) { view.destroy(); view = null }
    if (controller) { controller.destroy(); controller = null }
  }

  function find(name) {
    return findChild(view, name)
  }

  function test_the_view_builds_and_summarises_the_desk() {
    verify(view !== null, "the view did not instantiate")
    const summary = find("summary")
    verify(summary !== null, "no summary line")
    // 1600x1000 logical beside 2560x1440 → 4160 wide, 1440 tall.
    compare(summary.text, "2 displays · 4160×1440")
  }

  function test_apply_is_dead_until_something_changes() {
    const apply = find("apply")
    verify(apply !== null)
    compare(apply.enabled, false, "Apply offered with nothing to apply")

    controller.states[1].x = 2000
    controller.touch()
    compare(apply.enabled, true, "Apply stayed dead after a move")
    verify(find("summary").text.indexOf("unapplied") !== -1)
  }

  function test_apply_reaches_the_controller() {
    controller.states[1].x = 2000
    controller.touch()
    mouseClick(find("apply"))
    compare(controller.applyCalls, 1)
  }

  function test_auto_arrange_packs_the_displays() {
    controller.states[1].x = 9000
    controller.touch()
    mouseClick(find("autoArrange"))
    compare(controller.states[1].x, 1600, "not packed against its neighbour")
    compare(Snap.validate(controller.states).length, 0)
  }

  function test_the_countdown_dialog_only_shows_while_counting() {
    const dialog = find("countdownDialog")
    verify(dialog !== null)
    compare(dialog.visible, false)
    controller.countdown = 15
    compare(dialog.visible, true)
  }

  function test_keep_and_revert_reach_the_controller() {
    controller.countdown = 15
    wait(0)
    mouseClick(find("keep"))
    compare(controller.keepCalls, 1)
    mouseClick(find("revert"))
    compare(controller.revertCalls, 1)
  }

  function test_an_invalid_layout_is_called_out() {
    // Drop one display on top of the other.
    controller.states[1].x = 0
    controller.states[1].y = 0
    controller.touch()
    verify(controller.problems.length > 0)
    verify(controller.problems[0].indexOf("overlap") !== -1)
  }

  function test_the_view_survives_having_no_controller_yet() {
    // The shell injects `service` after the component is built, so every
    // binding runs once with nothing behind it.
    const bare = viewComp.createObject(suite, { width: 800, height: 600 })
    verify(bare !== null, "the view threw when built without a controller")
    bare.destroy()
  }

  // ------------------------------------------------------------- dragging
  //
  // The press-move-release path is where an arrangement tool is actually used
  // and where the arithmetic is easiest to get wrong, so it is driven for real
  // rather than by calling snapAndResolve directly.

  function tileFor(name) { return find("tile-" + name) }

  function dragBy(name, dxLogical, dyLogical) {
    const tile = tileFor(name)
    verify(tile !== null, "no tile for " + name)
    // Moving a display changes the bounding box, and with it the zoom the next
    // drag is measured in, so this is read fresh every time.
    const zoom = tile.parent.zoom
    const cx = tile.width / 2
    const cy = tile.height / 2
    mousePress(tile, cx, cy)
    // Two moves: one to start the drag, one to land it. A single event can be
    // taken for a click.
    mouseMove(tile, cx + dxLogical * zoom / 2, cy + dyLogical * zoom / 2)
    mouseMove(tile, cx + dxLogical * zoom, cy + dyLogical * zoom)
    mouseRelease(tile, cx + dxLogical * zoom, cy + dyLogical * zoom)
  }

  function test_a_tile_exists_for_every_display() {
    verify(tileFor("eDP-1") !== null)
    verify(tileFor("DP-1") !== null)
  }

  function test_pressing_a_tile_selects_that_display() {
    compare(controller.selectedName, "eDP-1")
    const tile = tileFor("DP-1")
    mousePress(tile, tile.width / 2, tile.height / 2)
    mouseRelease(tile, tile.width / 2, tile.height / 2)
    compare(controller.selectedName, "DP-1")
  }

  function test_a_rough_drag_lands_flush_against_the_neighbour() {
    // eDP-1 is 1600x1000 logical at the origin, so the shared edge is x=1600.
    // Drag DP-1 well clear, then drop it *near* the edge rather than on it:
    // landing exactly is the snapping's job, not the test's.
    dragBy("DP-1", 900, 0)
    verify(controller.states[1].x > 1600, "the drag did not move anything")

    // Aim 40px short of flush -- inside the snap threshold, nowhere near it by
    // accident.
    dragBy("DP-1", 1640 - controller.states[1].x, 0)
    compare(controller.states[1].x, 1600, "did not snap flush")
    compare(controller.states[1].y, 0)
  }

  function test_a_drop_far_from_anything_keeps_the_free_position() {
    dragBy("DP-1", 3000, 900)
    verify(controller.states[1].x > 3000, "a far drop was pulled back to a neighbour")
    verify(controller.states[1].y > 600)
  }

  function test_a_drag_never_lands_on_top_of_a_neighbour() {
    dragBy("DP-1", -1400, 0)
    verify(!Geo.rectsOverlap(Geo.rectOf(controller.states[0]), Geo.rectOf(controller.states[1])),
      "a drag left two displays overlapping")
  }

  function test_dragging_marks_the_layout_unapplied() {
    compare(controller.dirty, false)
    dragBy("DP-1", 0, 700)
    compare(controller.dirty, true, "a drag did not register as a change")
    verify(find("apply").enabled)
  }
}
