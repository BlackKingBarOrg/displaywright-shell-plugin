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

      // The wallpaper half. Writes are recorded rather than made.
      property var wallpapers: ({ version: 1, monitors: {} })
      property var wallpaperFiles: []
      property int wallpaperRevision: 0
      property int addCalls: 0
      property int saveCalls: 0

      function wallpaperFor(name) {
        wallpaperRevision
        if (!name || !wallpapers.monitors) return ""
        var entry = wallpapers.monitors[name]
        return entry && entry.path ? String(entry.path) : ""
      }
      function setWallpaper(path) {
        if (!selectedName || !path) return
        var m = wallpapers.monitors || {}
        var e = m[selectedName] || {}
        e.kind = "image"; e.path = String(path); if (!e.fit) e.fit = "fill"
        m[selectedName] = e
        wallpapers.monitors = m
        if (wallpapers.span) delete wallpapers.span
        saveCalls += 1
        wallpaperRevision += 1
      }
      function clearWallpaper() {
        if (!selectedName || !wallpapers.monitors) return
        delete wallpapers.monitors[selectedName]
        saveCalls += 1
        wallpaperRevision += 1
      }
      function addWallpaper() { addCalls += 1 }

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
    controller.wallpaperFiles = ["/pic/one.png", "/pic/two.png", "/pic/three.png"]
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

  // Events are addressed to the canvas, which does not move, rather than to the
  // tile, which does. Aiming at a moving frame feeds the drag a delta that has
  // already been partly applied -- the test then reports travel the user never
  // asked for, and would have hidden the fix for the real version of the same
  // mistake in the handler.
  function dragBy(name, dxLogical, dyLogical) {
    const tile = tileFor(name)
    verify(tile !== null, "no tile for " + name)
    const canvas = tile.parent
    const zoom = canvas.zoom
    const from = tile.mapToItem(canvas, tile.width / 2, tile.height / 2)
    const toX = from.x + dxLogical * zoom
    const toY = from.y + dyLogical * zoom
    mousePress(canvas, from.x, from.y)
    // Two moves: one to start the drag, one to land it. A single event can be
    // taken for a click.
    mouseMove(canvas, (from.x + toX) / 2, (from.y + toY) / 2)
    mouseMove(canvas, toX, toY)
    mouseRelease(canvas, toX, toY)
  }

  function test_a_tile_exists_for_every_display() {
    verify(tileFor("eDP-1") !== null)
    verify(tileFor("DP-1") !== null)
  }

  function test_pressing_a_tile_selects_that_display() {
    compare(controller.selectedName, "eDP-1")
    const tile = tileFor("DP-1")
    const p = tile.mapToItem(tile.parent, tile.width / 2, tile.height / 2)
    mousePress(tile.parent, p.x, p.y)
    mouseRelease(tile.parent, p.x, p.y)
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

  // --------------------------------------------------------------- sidebar
  //
  // The per-display controls had no coverage at all, which is how a resolution
  // picker that does nothing reached a real desktop.

  function test_the_sidebar_offers_every_resolution_the_panel_has() {
    const cycler = find("resolution")
    verify(cycler !== null, "no resolution control")
    // The fixture advertises one size; a real panel advertises many. Either
    // way the control has to show what the display is currently running.
    compare(cycler.current, "3200x2000")
  }

  function pick(controlName, option) {
    const control = find(controlName)
    verify(control !== null, "no " + controlName + " control")
    verify(control.options.indexOf(option) !== -1,
      option + " is not offered by " + controlName + ": " + JSON.stringify(control.options))
    mouseClick(control)                       // open the list
    compare(control.open, true, controlName + " did not open")
    // The list virtualises, so a row far down it does not exist until the view
    // is scrolled to it -- which is what a user does too.
    // The list is drawn in the view's popup layer, not under the control, so
    // it is searched from there. It virtualises too, so a row far down does
    // not exist until the view is scrolled to it -- as a user would.
    const listView = findChild(control.popup, "listView")
    listView.positionViewAtIndex(control.options.indexOf(option), ListView.Contain)
    wait(0)
    const row = findChild(control.popup, "option-" + option)
    verify(row !== null, "no row for " + option)
    mouseClick(row)
    compare(control.open, false, controlName + " stayed open after a pick")
  }

  function test_a_control_opens_a_list_rather_than_cycling() {
    const s = controller.states[0]
    s.availableModes = [
      { width: 3200, height: 2000, refresh: 120 },
      { width: 1920, height: 1200, refresh: 60 },
    ]
    controller.touch()
    const control = find("resolution")
    compare(control.open, false)
    compare(control.popup.visible, false, "the list showed before it was asked for")
    mouseClick(control)
    compare(control.open, true)
    compare(control.popup.visible, true, "the list did not appear")
  }

  function test_the_list_is_drawn_above_everything_else() {
    // z only orders siblings, so a list left inside a sidebar row is covered by
    // the rows laid out after it however high its z. It has to be reparented
    // into the layer the view draws last.
    // The fixture panel advertises one size, and a control with one option does
    // not open. Give it something to choose between first.
    controller.states[0].availableModes = [
      { width: 3200, height: 2000, refresh: 120 },
      { width: 1920, height: 1200, refresh: 60 },
    ]
    controller.touch()

    const control = find("resolution")
    const layer = find("popupLayer")
    verify(layer !== null, "the view has no popup layer")
    compare(control.popup.parent, layer, "the list is not in the popup layer")

    // And it has to land under its own field rather than at the layer origin.
    mouseClick(control)
    compare(control.open, true, "the control did not open")
    const field = control.mapToItem(layer, 0, control.height)
    verify(Math.abs(control.popup.y - (field.y + 4)) < 2,
      "the list is not positioned under its control")
    verify(Math.abs(control.popup.x - field.x) < 2)
  }

  function test_picking_a_resolution_changes_the_mode() {
    const s = controller.states[0]
    s.availableModes = [
      { width: 3200, height: 2000, refresh: 120 },
      { width: 1920, height: 1200, refresh: 60 },
    ]
    controller.touch()
    pick("resolution", "1920x1200")
    compare(controller.states[0].mode.width, 1920, "picking did not change the mode")
    compare(controller.states[0].mode.height, 1200)
  }

  function test_a_long_mode_list_is_reachable_in_one_pick() {
    // A real panel offers eleven sizes. Cycling to the last one took eleven
    // clicks and showed a stale value the whole way; a list takes two.
    const s = controller.states[0]
    s.availableModes = []
    for (const r of [[3200,2000],[2560,1440],[1920,1200],[1920,1080],[1680,1050],
                     [1600,900],[1440,900],[1366,768],[1280,1024],[1280,720],[1024,768]]) {
      s.availableModes.push({ width: r[0], height: r[1], refresh: 60 })
    }
    controller.touch()
    compare(find("resolution").options.length, 11)
    pick("resolution", "1024x768")
    compare(controller.states[0].mode.width, 1024)
  }

  function test_picking_a_refresh_rate_changes_the_mode() {
    const s = controller.states[0]
    s.availableModes = [
      { width: 3200, height: 2000, refresh: 120 },
      { width: 3200, height: 2000, refresh: 60 },
    ]
    s.mode = { width: 3200, height: 2000, refresh: 120 }
    controller.touch()
    pick("refresh", "60 Hz")
    compare(controller.states[0].mode.refresh, 60)
  }

  function test_picking_a_scale_changes_it() {
    compare(controller.states[0].scale, 2)
    pick("scale", "1.25")
    compare(controller.states[0].scale, 1.25)
  }

  function test_scales_below_one_are_offered() {
    // A large low-density panel wants everything smaller. 0.8 is not a corner
    // case here: it is what one of the displays on the machine this was
    // reported from is running.
    const options = find("scale").options
    verify(options.indexOf("0.5") !== -1, "no 0.5")
    verify(options.indexOf("0.8") !== -1, "no 0.8")
    verify(options.indexOf("0.95") !== -1, "no 0.95")
    pick("scale", "0.8")
    compare(controller.states[0].scale, 0.8)
  }

  function test_a_scale_the_display_is_running_is_shown_even_if_unusual() {
    // Hyprland takes any scale and Omarchy's display settings write ones the
    // list does not have, so the control has to fold the current value in.
    controller.states[0].scale = 0.83
    controller.touch()
    const control = find("scale")
    compare(control.current, "0.83", "the control cannot show the current scale")
    verify(control.options.indexOf("0.83") !== -1, "and cannot put it back")
  }

  function test_every_control_shows_what_the_display_is_actually_set_to() {
    // QML does not track fields of a plain object, so a binding that forgets to
    // depend on the revision counter goes stale. A control showing a stale
    // value then cycles from the wrong place and lands back where it started,
    // which reads as a control that does nothing at all -- and did.
    const s = controller.states[0]
    s.mode = { width: 3200, height: 2000, refresh: 60 }
    s.scale = 1.5
    s.transform = 2
    s.enabled = false
    controller.touch()

    compare(find("resolution").current, "3200x2000")
    compare(find("refresh").current, "60 Hz")
    compare(find("scale").current, "1.5")
    compare(find("rotation").current, "180°")
    compare(find("enabled").label, "Off")
  }

  function test_rotating_marks_the_layout_unapplied() {
    compare(controller.states[0].transform, 0)
    pick("rotation", "90°")
    compare(controller.states[0].transform, 1, "rotation did not change")
    compare(controller.dirty, true)
  }

  function test_toggling_enabled_turns_a_display_off_and_on() {
    const toggle = find("enabled")
    verify(toggle !== null)
    mouseClick(toggle)
    compare(controller.states[0].enabled, false)
    mouseClick(toggle)
    compare(controller.states[0].enabled, true)
  }

  function test_clicking_away_closes_the_list_without_reaching_what_is_behind() {
    controller.states[0].availableModes = [
      { width: 3200, height: 2000, refresh: 120 },
      { width: 1920, height: 1200, refresh: 60 },
    ]
    controller.touch()
    const control = find("resolution")
    mouseClick(control)
    compare(control.open, true)

    const before = controller.selectedName
    const layer = find("popupLayer")
    // Somewhere well away from the list, over the canvas -- a click there must
    // dismiss and stop, not also select a display.
    mouseClick(layer, 60, layer.height - 60)
    compare(control.open, false, "the list stayed open")
    compare(controller.selectedName, before, "the dismissing click went through")
  }

  function test_a_drag_moves_exactly_as_far_as_the_pointer() {
    // The tile has to track the cursor: a 300 logical-pixel gesture moves the
    // display 300 logical pixels, however many mouse events it arrives in.
    // Measuring the delta per event against the *current* position instead of
    // the position the drag started from compounds it, and a small gesture
    // throws the display across the desk.
    const tile = tileFor("DP-1")
    const canvas = tile.parent
    const zoom = canvas.zoom
    const startX = controller.states[1].x
    const from = tile.mapToItem(canvas, tile.width / 2, tile.height / 2)
    const travel = 300 * zoom          // device pixels

    mousePress(canvas, from.x, from.y)
    // Ten small steps, the way a real gesture arrives.
    for (let i = 1; i <= 10; i++) mouseMove(canvas, from.x + travel * i / 10, from.y)
    mouseRelease(canvas, from.x + travel, from.y)

    const moved = controller.states[1].x - startX
    verify(Math.abs(moved - 300) < 25,
      "a 300px gesture moved the display " + moved + "px")
  }

  function test_the_view_holds_still_while_a_display_is_being_dragged() {
    // Dragging changes the bounding box, which changes the zoom, which moves
    // every tile -- including the one under the cursor. The tile then does not
    // track the pointer and the last 88 pixels of a gesture go somewhere else.
    const tile = tileFor("DP-1")
    const canvas = tile.parent
    const from = tile.mapToItem(canvas, tile.width / 2, tile.height / 2)
    const zoomBefore = canvas.zoom

    mousePress(canvas, from.x, from.y)
    mouseMove(canvas, from.x + 400, from.y + 200)
    compare(canvas.zoom, zoomBefore, "the view rescaled mid-drag")
    mouseMove(canvas, from.x + 800, from.y + 400)
    compare(canvas.zoom, zoomBefore, "the view rescaled mid-drag")
    mouseRelease(canvas, from.x + 800, from.y + 400)

    // And picks the new layout up once the gesture is over.
    verify(canvas.zoom !== zoomBefore, "the view never caught up with the move")
  }

  // ------------------------------------------------------------ wallpapers

  function test_the_strip_lists_every_picture_it_was_given() {
    const list = find("wallpaperList")
    verify(list !== null, "no wallpaper strip")
    compare(list.count, 3)
    compare(list.orientation, ListView.Horizontal, "the strip is not horizontal")
  }

  function test_choosing_a_picture_gives_it_to_the_selected_display_only() {
    compare(controller.selectedName, "eDP-1")
    const row = findChild(find("wallpaperList"), "wallpaper-two.png")
    verify(row !== null, "no tile for two.png")
    mouseClick(row)
    compare(controller.wallpaperFor("eDP-1"), "/pic/two.png")
    compare(controller.wallpaperFor("DP-1"), "", "the other display was touched")
  }

  function test_the_preview_shows_the_wallpaper_a_display_was_given() {
    controller.setWallpaper("/pic/one.png")
    const tile = tileFor("eDP-1")
    // The tile's Image is bound to wallpaperFor, and a binding that forgets the
    // revision counter goes stale exactly the way the sidebar's did.
    var found = false
    for (var i = 0; i < tile.children.length; i++) {
      var child = tile.children[i]
      if (child.source !== undefined && String(child.source).indexOf("one.png") !== -1) found = true
    }
    verify(found, "the tile does not show the wallpaper it was given")
  }

  function test_switching_display_switches_what_the_strip_highlights() {
    controller.setWallpaper("/pic/one.png")          // eDP-1
    controller.selectedName = "DP-1"
    controller.setWallpaper("/pic/three.png")
    compare(controller.wallpaperFor("eDP-1"), "/pic/one.png")
    compare(controller.wallpaperFor("DP-1"), "/pic/three.png")
  }

  function test_follow_theme_hands_the_display_back() {
    controller.setWallpaper("/pic/one.png")
    const follow = find("followTheme")
    verify(follow !== null, "no follow-theme control")
    verify(follow.enabled, "offered nothing to undo")
    mouseClick(follow)
    compare(controller.wallpaperFor("eDP-1"), "")
  }

  function test_follow_theme_is_dead_when_the_display_already_follows_it() {
    compare(controller.wallpaperFor("eDP-1"), "")
    compare(find("followTheme").enabled, false)
  }

  function test_add_reaches_the_file_picker() {
    mouseClick(find("addWallpaper"))
    compare(controller.addCalls, 1)
  }

  function test_choosing_a_picture_ends_a_span() {
    // A span outranks the per-display entries, so writing one under it would
    // look like the pick did nothing at all.
    controller.wallpapers.span = { kind: "image", path: "/pic/wide.png" }
    controller.setWallpaper("/pic/two.png")
    compare(controller.wallpapers.span, undefined, "the span survived the pick")
    compare(controller.wallpaperFor("eDP-1"), "/pic/two.png")
  }
}
