// Ported from tests/test_displays_snapping.py, assertion for assertion.
import assert from "node:assert/strict"
import { test } from "node:test"
import {
  SNAP_THRESHOLD, autoArrange, normalize, pushOut, snapAndResolve, snapPosition, validate,
} from "../lib/snapping.mjs"
import { rectOf } from "../lib/geometry.mjs"

const rect = (x, y, w, h) => ({ x, y, w, h })

function monitor(name, w, h, { x = 0, y = 0, scale = 1, enabled = true, mirrorOf = null } = {}) {
  return {
    name, description: "", make: "", model: "", serial: "",
    physicalWidth: 0, physicalHeight: 0,
    enabled, mode: { width: w, height: h, refresh: 60 }, scale, transform: 0,
    x, y, vrr: null, mirrorOf,
    availableModes: [{ width: w, height: h, refresh: 60 }], focused: false,
  }
}

test("snaps a near edge flush", () => {
  const got = snapPosition(rect(1550, 10, 3440, 1440), [rect(0, 0, 1600, 1000)])
  assert.equal(got.x, 1600)
  assert.equal(got.y, 0)
})

test("leaves a far edge alone", () => {
  const other = [rect(0, 0, 1600, 1000)]
  const got = snapPosition(rect(5000, 5000, 800, 600), other)
  assert.deepEqual([got.x, got.y], [5000, 5000])
  assert.deepEqual(got.guides, [])
})

test("snapping is per axis", () => {
  // Close enough on x to snap, far away on y.
  const got = snapPosition(rect(1590, 4000, 800, 600), [rect(0, 0, 1600, 1000)])
  assert.equal(got.x, 1600)
  assert.equal(got.y, 4000)
})

test("centre alignment is available", () => {
  // Dropped below the anchor and roughly centred on it: y attaches to the
  // bottom edge, x is already on the centre line and stays put.
  const got = snapPosition(rect(500, 1030, 600, 400), [rect(0, 0, 1600, 1000)])
  assert.deepEqual([got.x, got.y], [500, 1000])
})

test("attaches to the left of a neighbour", () => {
  const got = snapPosition(rect(-3400, 10, 3440, 1440), [rect(0, 0, 1600, 1000)])
  assert.equal(got.x, -3440)
})

test("the threshold is respected exactly", () => {
  const other = [rect(0, 0, 1600, 1000)]
  const inside = snapPosition(rect(1600 + SNAP_THRESHOLD, 0, 800, 600), other)
  assert.equal(inside.x, 1600)
  const outside = snapPosition(rect(1600 + SNAP_THRESHOLD + 1, 0, 800, 600), other)
  assert.equal(outside.x, 1600 + SNAP_THRESHOLD + 1)
})

test("push-out resolves an overlap along the cheapest axis", () => {
  const [x, y] = pushOut(rect(100, 0, 800, 600), [rect(0, 0, 1600, 1000)])
  assert.ok(!(x < 1600 && x + 800 > 0 && y < 1000 && y + 600 > 0),
    "still overlapping after push-out")
})

test("snap and resolve never leaves an overlap", () => {
  const others = [rect(0, 0, 1600, 1000)]
  const got = snapAndResolve(rect(200, 100, 800, 600), others)
  const moved = rect(got.x, got.y, 800, 600)
  const o = others[0]
  assert.ok(!(moved.x < o.x + o.w && o.x < moved.x + moved.w
    && moved.y < o.y + o.h && o.y < moved.y + moved.h))
  assert.deepEqual(got.guides, [], "guides survive a push-out")
})

test("normalize moves the layout to the origin", () => {
  const states = [monitor("A", 1600, 1000, { x: -400, y: 56 }),
                  monitor("B", 2560, 1440, { x: 1200, y: -826 })]
  assert.equal(normalize(states), true)
  const box = states.map(rectOf)
  assert.equal(Math.min(...box.map(r => r.x)), 0)
  assert.equal(Math.min(...box.map(r => r.y)), 0)
  assert.equal(normalize(states), false, "a second pass should be a no-op")
})

test("normalize ignores disabled displays", () => {
  const states = [monitor("A", 1600, 1000, { x: 0, y: 0 }),
                  monitor("B", 800, 600, { x: -5000, y: 0, enabled: false })]
  assert.equal(normalize(states), false)
})

test("auto arrange lays displays out left to right, centred", () => {
  const states = [monitor("A", 1600, 1000, { x: 900, y: 400 }),
                  monitor("B", 2560, 1440, { x: 0, y: 0 })]
  autoArrange(states)
  const byName = Object.fromEntries(states.map(s => [s.name, s]))
  assert.equal(byName.B.x, 0)
  assert.equal(byName.A.x, 2560)
  assert.equal(byName.B.y, 0)               // the tallest sits at the top
  assert.equal(byName.A.y, (1440 - 1000) / 2)
  assert.deepEqual(validate(states), [])
})

test("validate is quiet about a flush pair", () => {
  const states = [monitor("A", 1600, 1000), monitor("B", 2560, 1440, { x: 1600 })]
  assert.deepEqual(validate(states), [])
})

test("validate reports an overlap", () => {
  const states = [monitor("A", 1600, 1000), monitor("B", 2560, 1440, { x: 100 })]
  assert.ok(validate(states).some(p => p.includes("overlap")))
})

test("validate reports a display the pointer cannot reach", () => {
  const states = [monitor("A", 1600, 1000), monitor("B", 2560, 1440, { x: 4000 })]
  assert.ok(validate(states).some(p => p.includes("cannot reach")))
})

test("validate refuses a layout with nothing enabled", () => {
  const states = [monitor("A", 1600, 1000, { enabled: false })]
  assert.ok(validate(states)[0].includes("black screen"))
})

test("validate catches a mirror of something that is not there", () => {
  const states = [monitor("A", 1600, 1000, { mirrorOf: "GHOST-1" })]
  assert.ok(validate(states).some(p => p.includes("unknown output")))
})

test("validate catches a display mirroring itself", () => {
  const states = [monitor("A", 1600, 1000, { mirrorOf: "A" })]
  assert.ok(validate(states).some(p => p.includes("cannot mirror itself")))
})
