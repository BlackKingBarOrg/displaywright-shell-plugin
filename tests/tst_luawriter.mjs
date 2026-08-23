// Ported from tests/test_displays_luawriter.py.
import assert from "node:assert/strict"
import { test } from "node:test"
import * as L from "../lib/luawriter.mjs"

// Shaped like a stock Omarchy ~/.config/hypr/monitors.lua.
const EXISTING = `-- See https://wiki.hypr.land/Configuring/Basics/Monitors/

local omarchy_monitor_scale = 2

hl.env("GDK_SCALE", "2")
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 2 })

-- Laptop panel pinned at origin.
hl.monitor({ output = "eDP-1", mode = "3200x2000@120", position = "0x0", scale = 2 })
`

function state(over = {}) {
  return {
    name: "eDP-1", description: "", make: "LG Display", model: "0x07C5", serial: "",
    physicalWidth: 340, physicalHeight: 220,
    enabled: true, mode: { width: 3200, height: 2000, refresh: 120 }, scale: 2,
    transform: 0, x: 0, y: 0, vrr: null, mirrorOf: null,
    availableModes: [{ width: 3200, height: 2000, refresh: 120 }], focused: false,
    ...over,
  }
}

const laptop = () => state()
const ultrawide = () => state({
  name: "DP-1", make: "CSF", model: "CS3421", scale: 1, x: 1600,
  mode: { width: 3440, height: 1440, refresh: 50 },
  availableModes: [{ width: 3440, height: 1440, refresh: 50 }],
})

test("renders the Lua a monitor rule needs", () => {
  assert.equal(L.renderCall(laptop()),
    'hl.monitor({ output = "eDP-1", mode = "3200x2000@120", position = "0x0", scale = 2 })')
})

test("a disabled output is written as disabled", () => {
  assert.equal(L.renderCall(state({ enabled: false })),
    'hl.monitor({ output = "eDP-1", disabled = true })')
})

test("extras appear only when set", () => {
  const s = state({ transform: 3, mirrorOf: "DP-1", vrr: 1, scale: 1.25 })
  assert.equal(L.renderCall(s),
    'hl.monitor({ output = "eDP-1", mode = "3200x2000@120", position = "0x0", '
    + 'scale = 1.25, transform = 3, mirror = "DP-1", vrr = 1 })')
})

test("a mode-less output asks for preferred", () => {
  assert.ok(L.renderCall(state({ mode: null })).includes('mode = "preferred"'))
})

test("quotes are escaped", () => {
  assert.equal(L.luaString('we"ird'), '"we\\"ird"')
})

test("the legacy rule form is still available", () => {
  assert.equal(L.ruleArgs(laptop()), "eDP-1,3200x2000@120,0x0,2")
  assert.equal(L.ruleArgs(state({ enabled: false })), "eDP-1,disable")
  assert.equal(L.ruleArgs(state({ transform: 3, mirrorOf: "DP-1", vrr: 1, scale: 1.25 })),
    "eDP-1,3200x2000@120,0x0,1.25,transform,3,mirror,DP-1,vrr,1")
})

test("the block carries its markers and a comment per display", () => {
  const block = L.renderBlock([laptop(), ultrawide()])
  assert.ok(block.startsWith(L.BEGIN))
  assert.ok(block.trimEnd().endsWith(L.END))
  assert.ok(block.includes("-- eDP-1: LG Display"))
  assert.ok(block.includes("-- DP-1: CSF CS3421"))
})

test("a first save keeps user lines and comments out the rules it takes over", () => {
  const merged = L.merge(EXISTING, L.renderBlock([laptop()]), new Set(["eDP-1"]))
  assert.ok(merged.includes('hl.env("GDK_SCALE", "2")'), "user line lost")
  // The catch-all rule is not ours to touch.
  assert.ok(merged.includes('hl.monitor({ output = "", mode = "preferred"'))
  assert.ok(merged.includes('-- [displaywright] replaced: hl.monitor({ output = "eDP-1"'))
  assert.ok(merged.includes("displaywright commented out 1 earlier"))
})

test("a rule for a display we do not manage is left alone", () => {
  const merged = L.merge(EXISTING, L.renderBlock([ultrawide()]), new Set(["DP-1"]))
  assert.ok(!merged.includes("[displaywright] replaced"))
})

test("a second save replaces the block in place", () => {
  const first = L.merge(EXISTING, L.renderBlock([laptop()]), new Set(["eDP-1"]))
  const second = L.merge(first, L.renderBlock([laptop(), ultrawide()]), new Set(["eDP-1", "DP-1"]))
  assert.equal(second.split(L.BEGIN).length - 1, 1, "a second block appeared")
  assert.ok(second.includes('output = "DP-1"'))
  assert.ok(second.includes('hl.env("GDK_SCALE", "2")'))
})

test("multi-line calls are commented out completely", () => {
  const text = 'hl.monitor({\n  output = "eDP-1",\n  mode = "preferred",\n})\nhl.env("KEEP", "1")\n'
  const merged = L.merge(text, L.renderBlock([laptop()]), new Set(["eDP-1"]))
  assert.ok(merged.includes('-- [displaywright] replaced:   mode = "preferred",'))
  assert.ok(merged.includes("-- [displaywright] replaced: })"))
  assert.ok(merged.includes('hl.env("KEEP", "1")'))
})

test("an empty config just gets the block", () => {
  const merged = L.merge("", L.renderBlock([laptop()]))
  assert.ok(merged.startsWith(L.BEGIN))
})

test("a hyprlayout block is rewritten in place, not appended to", () => {
  const [legacyBegin, legacyEnd] = L.LEGACY_MARKERS[0]
  const existing = `hl.env('KEEP', '1')\n${legacyBegin}\n`
    + 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1 })\n'
    + `${legacyEnd}\n-- trailing user line\n`
  const merged = L.merge(existing, L.renderBlock([laptop()]))
  assert.ok(!merged.includes(legacyBegin), "the old marker survived")
  assert.equal(merged.split(L.BEGIN).length - 1, 1)
  assert.ok(merged.includes("hl.env('KEEP', '1')"))
  assert.ok(merged.includes("-- trailing user line"))
  assert.ok(!merged.includes("replaced:"), "nothing outside the old block was touched")
})

test("a laptop panel switched off keeps an enabled rule when Omarchy can recover it", () => {
  const off = state({ enabled: false })
  const block = L.renderBlock([off], true)
  assert.ok(block.includes('output = "eDP-1"'))
  assert.ok(!block.includes("disabled = true"), "wrote a rule nothing would ever remove")
  assert.ok(block.includes("internal-monitor-disable"))
})

test("a disabled external is written as disabled", () => {
  const block = L.renderBlock([state({ name: "DP-1", enabled: false })], true)
  assert.ok(block.includes('output = "DP-1", disabled = true'))
})

test("the diff says what would change, and nothing when nothing would", () => {
  const before = L.renderFile(EXISTING, [laptop()])
  assert.equal(L.diff(before, before), "")
  const after = L.renderFile(before, [laptop(), ultrawide()])
  const patch = L.diff(before, after, "monitors.lua")
  assert.ok(patch.startsWith("--- a/monitors.lua"))
  assert.ok(patch.split("\n").some(l => l.startsWith("+") && l.includes('output = "DP-1"')))
})

test("render_file is merge plus render_block", () => {
  const a = L.renderFile(EXISTING, [laptop()])
  const b = L.merge(EXISTING, L.renderBlock([laptop()]), new Set(["eDP-1"]))
  assert.equal(a, b)
})

test("a display that is unplugged keeps its rule", () => {
  // Reported from a real desk: a rotated, scaled display was unplugged, the
  // layout was saved, and the block came back with only the two that were
  // still connected -- so plugging the third back in brought it up square and
  // unscaled, with no record anywhere of how it had been set up.
  const both = L.renderFile("", [laptop(), ultrawide()])
  const portrait = state({
    name: "DP-2", make: "Acme", model: "Portrait", scale: 0.8, transform: 1, x: 4160,
    mode: { width: 2560, height: 1440, refresh: 60 },
    availableModes: [{ width: 2560, height: 1440, refresh: 60 }],
  })
  const three = L.renderFile(both, [laptop(), ultrawide(), portrait])
  assert.ok(three.includes('output = "DP-2"'))

  // Now it is gone from hyprctl, as an unplugged display is.
  const two = L.renderFile(three, [laptop(), ultrawide()])
  assert.ok(two.includes('output = "DP-2"'), "the unplugged display lost its rule")
  assert.ok(two.includes("transform = 1"), "and lost its rotation")
  assert.ok(two.includes("scale = 0.8"), "and lost its scale")
  assert.ok(two.includes("Not connected right now"), "with nothing to say why it is there")
})

test("a display that comes back is written from the live layout, not the kept rule", () => {
  const three = L.renderFile("", [laptop(), ultrawide()])
  const gone = L.renderFile(three, [laptop()])
  assert.ok(gone.includes('output = "DP-1"'))

  // Plugged back in and moved: one rule, and it is the new one.
  const moved = state({
    name: "DP-1", make: "CSF", model: "CS3421", scale: 1, x: 9000,
    mode: { width: 3440, height: 1440, refresh: 50 },
    availableModes: [{ width: 3440, height: 1440, refresh: 50 }],
  })
  const back = L.renderFile(gone, [laptop(), moved])
  assert.equal(back.split('output = "DP-1"').length - 1, 1, "the display has two rules")
  assert.ok(back.includes('position = "9000x0"'))
})

test("rules outside the managed block are not hoovered up", () => {
  // The catch-all and any hand-written rule stay where the user put them.
  const existing = 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })\n'
  const written = L.renderFile(existing, [laptop()])
  const kept = L.rulesInBlock(written)
  assert.ok(!Object.prototype.hasOwnProperty.call(kept, ""), "adopted the catch-all")
})
