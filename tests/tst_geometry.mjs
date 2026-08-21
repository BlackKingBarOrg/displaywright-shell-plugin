// Ported from tests/test_model.py.
import assert from "node:assert/strict"
import { test } from "node:test"
import * as G from "../lib/geometry.mjs"

const LAPTOP = {
  name: "eDP-1", description: "LG Display", make: "LG Display", model: "0x07C5",
  physicalWidth: 340, physicalHeight: 220,
  width: 3200, height: 2000, refreshRate: 120.0,
  x: 0, y: 0, scale: 2, transform: 0, disabled: false, mirrorOf: "none",
  availableModes: ["3200x2000@120.00Hz", "3200x2000@60.00Hz"],
}
const ULTRAWIDE = {
  name: "DP-1", description: "CSF CS3421", make: "CSF", model: "CS3421",
  physicalWidth: 810, physicalHeight: 350,
  width: 3440, height: 1440, refreshRate: 50.0,
  x: 1600, y: 0, scale: 1, transform: 0, disabled: false, mirrorOf: "none",
  availableModes: ["3440x1440@60.00Hz", "3440x1440@99.99Hz", "2560x1440@120.00Hz"],
}

test("parses the hyprctl mode form", () => {
  assert.deepEqual(G.parseMode("3440x1440@99.99Hz"), { width: 3440, height: 1440, refresh: 99.99 })
  assert.deepEqual(G.parseMode("1920x1080"), { width: 1920, height: 1080, refresh: 0 })
  assert.equal(G.parseMode("garbage"), null)
})

test("renders the compact form Hyprland accepts", () => {
  assert.equal(G.modeHypr({ width: 2560, height: 1440, refresh: 60 }), "2560x1440@60")
  assert.equal(G.modeHypr({ width: 2560, height: 1440, refresh: 164.8 }), "2560x1440@164.80")
  assert.equal(G.modeHypr({ width: 2560, height: 1440, refresh: 0 }), "2560x1440")
})

test("reads geometry back", () => {
  const s = G.stateFromHyprctl(LAPTOP)
  assert.equal(s.name, "eDP-1")
  assert.equal(s.scale, 2)
  assert.deepEqual(G.logicalSize(s), [1600, 1000])
  assert.equal(s.enabled, true)
})

test("modes are sorted by area then refresh", () => {
  const s = G.stateFromHyprctl(ULTRAWIDE)
  assert.deepEqual(s.availableModes.map(G.modeResolution), ["3440x1440", "3440x1440", "2560x1440"])
  assert.equal(s.availableModes[0].refresh, 99.99)
})

test("an off-list refresh rate is preserved", () => {
  // 50Hz is not advertised: a link-bandwidth limit, not a panel limit.
  const s = G.stateFromHyprctl(ULTRAWIDE)
  assert.equal(s.mode.refresh, 50)
})

test("a near miss snaps to the advertised mode", () => {
  const s = G.stateFromHyprctl({ ...ULTRAWIDE, refreshRate: 99.98 })
  assert.equal(s.mode.refresh, 99.99)
})

test("a rotated output keeps the mode hyprctl reported", () => {
  // hyprctl reports the mode, not what the panel shows. Rotating it here would
  // invent a mode no display advertises, and applying it would fail.
  const s = G.stateFromHyprctl({ ...ULTRAWIDE, transform: 1 })
  assert.deepEqual(s.mode, { width: 3440, height: 1440, refresh: 50 })
  assert.ok(s.availableModes.some(m => G.modeResolution(m) === G.modeResolution(s.mode)))
  assert.deepEqual(G.logicalSize(s), [1440, 3440])
  assert.deepEqual(G.pixelSizeRotated(s), [1440, 3440])
})

test("a half turn does not swap the axes", () => {
  for (const transform of [0, 2, 4, 6]) {
    const s = G.stateFromHyprctl({ ...ULTRAWIDE, transform })
    assert.deepEqual(G.pixelSizeRotated(s), [3440, 1440], `transform ${transform}`)
    assert.equal(G.isRotated(s), false)
  }
})

test("rotation is applied before the scale", () => {
  const s = G.stateFromHyprctl({ ...LAPTOP, width: 2880, height: 1800, scale: 1.5, transform: 1,
                                 availableModes: ["2880x1800@60.00Hz"], refreshRate: 60 })
  assert.deepEqual(G.pixelSizeRotated(s), [1800, 2880])
  assert.deepEqual(G.logicalSize(s), [1200, 1920])
})

test("a zero scale is treated as one", () => {
  const s = G.stateFromHyprctl({ ...ULTRAWIDE, scale: 0 })
  assert.deepEqual(G.logicalSize(s), [3440, 1440])
})

test("focus is read back", () => {
  assert.equal(G.stateFromHyprctl({ ...ULTRAWIDE, focused: true }).focused, true)
  assert.equal(G.stateFromHyprctl(ULTRAWIDE).focused, false)
})

test("pretty name skips hex model ids", () => {
  assert.equal(G.prettyName(G.stateFromHyprctl(LAPTOP)), "LG Display")
  assert.equal(G.prettyName(G.stateFromHyprctl(ULTRAWIDE)), "CSF CS3421")
})

test("panel summary describes what a wallpaper must cover", () => {
  assert.equal(G.panelSummary(G.stateFromHyprctl(ULTRAWIDE)), "3440×1440")
  assert.equal(G.panelSummary(G.stateFromHyprctl(LAPTOP)),
    "3200×2000 · scale 2 → 1600×1000")
  assert.equal(G.panelSummary(G.stateFromHyprctl({ ...ULTRAWIDE, transform: 1 })),
    "1440×3440 · rotated")
})

test("a fractional logical size is warned about", () => {
  const ok = G.stateFromHyprctl(LAPTOP)
  assert.equal(G.scaleWarning(ok), null)
  const bad = { ...ok, scale: 1.3 }
  assert.ok(G.scaleWarning(bad).includes("fractional logical"))
  assert.equal(G.scaleWarning({ ...bad, enabled: false }), null)
})

test("scale suggestion uses physical density", () => {
  // 3200x2000 across 340mm is ~239 dpi: 2x lands at a comfortable ~120.
  assert.equal(G.suggestScale(G.stateFromHyprctl(LAPTOP)), 2)
  // A 3440x1440 at 810mm is ~108 dpi: already about right.
  assert.equal(G.suggestScale(G.stateFromHyprctl(ULTRAWIDE)), 1)
})

test("scale suggestion falls back without an EDID size", () => {
  const dense = G.stateFromHyprctl({ ...LAPTOP, physicalWidth: 0, physicalHeight: 0 })
  assert.equal(G.suggestScale(dense), 2)
  const roomy = G.stateFromHyprctl({ ...ULTRAWIDE, physicalWidth: 0, physicalHeight: 0 })
  assert.equal(G.suggestScale(roomy), 1)
})

test("config comparison ignores metadata", () => {
  const a = G.stateFromHyprctl(LAPTOP)
  const b = G.copyState(a)
  b.description = "something else"
  assert.equal(G.configEquals(a, b), true)
  b.x += 1
  assert.equal(G.configEquals(a, b), false)
})

test("copies are independent", () => {
  const a = G.stateFromHyprctl(LAPTOP)
  const b = G.copyState(a)
  b.availableModes.push({ width: 1, height: 1, refresh: 1 })
  assert.notEqual(a.availableModes.length, b.availableModes.length)
})

test("unmet requests are reported honestly", () => {
  const want = G.stateFromHyprctl(ULTRAWIDE)
  want.mode = { width: 3440, height: 1440, refresh: 60 }
  const got = G.stateFromHyprctl(ULTRAWIDE)          // still running 50Hz
  const problems = G.unmetRequests([want], [got])
  assert.equal(problems.length, 1)
  assert.ok(problems[0].includes("DP-1"))

  const nudged = G.copyState(want)
  nudged.scale = 1.25
  assert.ok(G.unmetRequests([{ ...want, scale: 1.3 }], [nudged])[0].includes("settled at"))

  assert.deepEqual(G.unmetRequests([want], [want]), [])
})

test("the laptop panel is recognised", () => {
  assert.equal(G.isBuiltin({ name: "eDP-1" }), true)
  assert.equal(G.isBuiltin({ name: "LVDS-1" }), true)
  assert.equal(G.isBuiltin({ name: "DP-1" }), false)
  assert.equal(G.isBuiltin({ name: "HDMI-A-1" }), false)
})

test("the scale list runs below 1 as well as above", () => {
  // A large low-density panel wants everything smaller, not larger.
  assert.ok(G.COMMON_SCALES.includes(0.5))
  assert.ok(G.COMMON_SCALES.includes(0.8))
  assert.ok(G.COMMON_SCALES.includes(0.95))
  assert.ok(G.COMMON_SCALES.includes(2))
  assert.deepEqual(G.COMMON_SCALES, G.COMMON_SCALES.slice().sort((a, b) => a - b),
    "the list is not in order")
})

test("the scale a display is actually running is always offered", () => {
  // Hyprland takes any scale, and Omarchy's own display settings write ones
  // this list does not have. Leaving it out means the control cannot show it.
  const odd = G.scaleChoices(0.83)
  assert.ok(odd.includes(0.83), "the current scale was dropped")
  assert.deepEqual(odd, odd.slice().sort((a, b) => a - b))
  // One already on the list is not duplicated.
  const known = G.scaleChoices(0.8)
  assert.equal(known.filter(s => s === 0.8).length, 1)
  assert.equal(known.length, G.COMMON_SCALES.length)
})

test("a scale of zero or nonsense is ignored", () => {
  assert.deepEqual(G.scaleChoices(0), G.COMMON_SCALES)
  assert.deepEqual(G.scaleChoices(undefined), G.COMMON_SCALES)
})

test("suggesting a scale still prefers the sensible one", () => {
  // The extra values must not pull the suggestion off a panel that was right.
  const laptop = G.stateFromHyprctl(LAPTOP)
  assert.equal(G.suggestScale(laptop), 2)
  assert.equal(G.suggestScale(G.stateFromHyprctl(ULTRAWIDE)), 1)
})
