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
