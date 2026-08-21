// The logic modules, run through Qt's QML engine rather than node's.
//
// node accepts JavaScript Qt does not: object spread parses cleanly under
// `node --test` and takes the wallpaper service down with `Unexpected token
// '...'`. Seventy passing node tests said nothing about that. These call the
// same functions from QML, so the next unsupported construct fails here
// instead of on somebody's desktop.

import QtQuick
import QtTest
import "../lib/geometry.mjs" as Geo
import "../lib/snapping.mjs" as Snap
import "../lib/luawriter.mjs" as Lua
import "../lib/fits.mjs" as Fits
import "../lib/span.mjs" as Span

TestCase {
  name: "modules"

  function entry(name, w, h, x, scale) {
    return {
      name: name, description: name, make: "Acme", model: name,
      physicalWidth: 340, physicalHeight: 220,
      width: w, height: h, refreshRate: 60, x: x, y: 0,
      scale: scale === undefined ? 1 : scale,
      transform: 0, disabled: false, mirrorOf: "none", focused: false,
      availableModes: [w + "x" + h + "@60.00Hz"],
    }
  }

  function test_geometry_runs_under_qml() {
    const s = Geo.stateFromHyprctl(entry("DP-1", 2560, 1440, 0))
    compare(s.name, "DP-1")
    compare(Geo.logicalSize(s)[0], 2560)
    compare(Geo.panelSummary(s), "2560×1440")
  }

  function test_copy_state_runs_under_qml() {
    // The one that broke the renderer: it used object spread.
    const s = Geo.stateFromHyprctl(entry("DP-1", 2560, 1440, 0))
    const copy = Geo.copyState(s)
    compare(copy.name, s.name)
    copy.availableModes.push({ width: 1, height: 1, refresh: 1 })
    verify(copy.availableModes.length !== s.availableModes.length, "the copy shares its modes")
  }

  function test_snapping_runs_under_qml() {
    const a = Geo.stateFromHyprctl(entry("eDP-1", 3200, 2000, 0, 2))
    const b = Geo.stateFromHyprctl(entry("DP-1", 2560, 1440, 9000))
    const result = Snap.snapAndResolve(
      { x: 1650, y: 0, w: 2560, h: 1440 }, [Geo.rectOf(a)])
    compare(result.x, 1600)
    Snap.autoArrange([a, b])
    compare(b.x, 1600)
    compare(Snap.validate([a, b]).length, 0)
  }

  function test_the_lua_writer_runs_under_qml() {
    const s = Geo.stateFromHyprctl(entry("DP-1", 2560, 1440, 1600))
    const block = Lua.renderBlock([s], true)
    verify(block.indexOf('output = "DP-1"') !== -1)
    const merged = Lua.merge("hl.env('KEEP', '1')\n", block, null)
    verify(merged.indexOf("hl.env('KEEP', '1')") !== -1)
    verify(Lua.diff(merged, merged) === "")
  }

  function test_the_fits_run_under_qml() {
    const r = Fits.fittedRect("center", 800, 600, 1600, 1000, 2)
    compare(r[2], 400)
    compare(r[3], 300)
    compare(Span.coverage([{ x: 0, y: 0, w: 100, h: 100 }]), 1)
  }
}
