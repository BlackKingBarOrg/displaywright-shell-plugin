// Ported from tests/test_wallpapers_preview.py and test_wallpapers_span.py.
import assert from "node:assert/strict"
import { test } from "node:test"
import { fittedRect, naturalSize, spanRect, usesBackdrop } from "../lib/fits.mjs"
import { coverage, offsets, spanBox } from "../lib/span.mjs"

const rect = (x, y, w, h) => ({ x, y, w, h })
const near = (a, b, msg) => assert.ok(Math.abs(a - b) < 1e-6, `${msg}: ${a} != ${b}`)

test("stretch fills the box exactly", () => {
  assert.deepEqual(fittedRect("stretch", 800, 600, 1920, 1080), [0, 0, 1920, 1080])
})

test("fill covers and crops", () => {
  const [x, y, w, h] = fittedRect("fill", 1000, 1000, 1920, 1080)
  near(w, 1920, "width"); near(h, 1920, "height")
  near(x, 0, "x")
  assert.ok(y < 0, "a square on a wide display should overflow vertically")
})

test("fit contains and letterboxes", () => {
  const [x, y, w, h] = fittedRect("fit", 1000, 1000, 1920, 1080)
  near(w, 1080, "width"); near(h, 1080, "height")
  assert.ok(x > 0, "bars on the sides")
  near(y, 0, "y")
})

test("center draws at the file's own resolution", () => {
  const [x, y, w, h] = fittedRect("center", 800, 600, 1920, 1080)
  assert.deepEqual([w, h], [800, 600])
  near(x, (1920 - 800) / 2, "x"); near(y, (1080 - 600) / 2, "y")
})

test("center is device-pixel exact on a scaled display", () => {
  // 3200x2000 physical, 1600x1000 logical: an 800x600 file must still cover
  // 800x600 real pixels, which is 400x300 logical.
  const [, , w, h] = fittedRect("center", 800, 600, 1600, 1000, 2)
  assert.deepEqual([w, h], [400, 300])
})

test("tile reports one tile at its own resolution", () => {
  assert.deepEqual(fittedRect("tile", 256, 256, 1920, 1080), [0, 0, 256, 256])
  assert.deepEqual(fittedRect("tile", 256, 256, 1600, 1000, 2), [0, 0, 128, 128])
})

test("natural size divides by the device pixel ratio", () => {
  assert.deepEqual(naturalSize(800, 600, 2), [400, 300])
  assert.deepEqual(naturalSize(800, 600, 0), [800, 600], "a zero ratio is treated as one")
})

test("a degenerate box or image falls back to the box", () => {
  assert.deepEqual(fittedRect("fill", 0, 600, 1920, 1080), [0, 0, 1920, 1080])
  assert.deepEqual(fittedRect("fill", 800, 600, 0, 1080), [0, 0, 0, 1080])
})

test("only fit and center show a backdrop", () => {
  assert.equal(usesBackdrop("fit"), true)
  assert.equal(usesBackdrop("center"), true)
  for (const f of ["fill", "stretch", "tile"]) assert.equal(usesBackdrop(f), false)
})

test("a spanned picture is offset by where the output sits", () => {
  const whole = fittedRect("fill", 4000, 2000, 4160, 1882)
  const piece = spanRect(4000, 2000, 4160, 1882, 1600, 0)
  near(piece[0], whole[0] - 1600, "x shifts by the offset")
  near(piece[2], whole[2], "the picture is not resized")
})

test("the span box covers every output", () => {
  assert.equal(spanBox([]), null)
  const box = spanBox([rect(0, 56, 1600, 1000), rect(1600, -826, 2560, 1440)])
  assert.deepEqual([box.x, box.y, box.w, box.h], [0, -826, 4160, 1882])
})

test("offsets are relative to the box origin", () => {
  const got = offsets([
    { name: "eDP-1", rect: rect(0, 56, 1600, 1000) },
    { name: "DP-1", rect: rect(1600, -826, 2560, 1440) },
  ])
  assert.deepEqual(got, { "eDP-1": [0, 882], "DP-1": [1600, 0] })
})

test("a flush row wastes nothing", () => {
  near(coverage([rect(0, 0, 1920, 1080), rect(1920, 0, 1920, 1080)]), 1, "coverage")
})

test("a staggered pair leaves gaps", () => {
  const pair = [rect(0, 56, 1600, 1000), rect(1600, -826, 2560, 1440)]
  near(coverage(pair), (1600 * 1000 + 2560 * 1440) / (4160 * 1882), "coverage")
})

test("overlapping outputs are not counted twice", () => {
  near(coverage([rect(0, 0, 1920, 1080), rect(0, 0, 1920, 1080)]), 1, "coverage")
})

test("no outputs cover nothing", () => {
  assert.equal(coverage([]), 0)
})
