// Geometry for one image stretched across every display.
//
// Windows calls this fit "Span". The image covers the bounding box of all the
// outputs, and each output shows whatever part of that box it sits on. Displays
// are rarely flush, so part of the picture can fall in the gap between them
// where nothing can draw it; `coverage` reports how much lands on glass.

import { boundingBox, rectBottom, rectRight } from "./geometry.mjs"

/** The smallest box containing every lit output, in logical coordinates. */
export function spanBox(rects) {
  if (!rects.length) return null
  return boundingBox(rects)
}

/** Where each output sits inside the bounding box, keyed by name. */
export function offsets(outputs) {
  const box = spanBox(outputs.map(o => o.rect))
  if (!box) return {}
  const out = {}
  for (const o of outputs) {
    out[o.name] = [Math.round(o.rect.x - box.x), Math.round(o.rect.y - box.y)]
  }
  return out
}

/** Area covered by at least one rect, counting overlaps once. */
function unionArea(rects) {
  const live = rects.filter(r => r.w > 0 && r.h > 0)
  if (!live.length) return 0
  // No Array.prototype.flatMap in Qt's JS engine, and Array.from over a Set
  // is the portable way to unique a list of edges.
  const edges = []
  for (const r of live) { edges.push(r.x); edges.push(rectRight(r)) }
  const xs = Array.from(new Set(edges)).sort((a, b) => a - b)
  let total = 0
  for (let i = 0; i + 1 < xs.length; i++) {
    const left = xs[i]
    const right = xs[i + 1]
    const strip = right - left
    if (strip <= 0) continue
    const spans = live.filter(r => r.x < right && rectRight(r) > left)
      .map(r => [r.y, rectBottom(r)])
      .sort((a, b) => a[0] - b[0])
    let covered = 0
    let cursor = null
    let end = 0
    for (const [y1, y2] of spans) {
      if (cursor === null || y1 > end) {
        if (cursor !== null) covered += end - cursor
        cursor = y1
        end = y2
      } else {
        end = Math.max(end, y2)
      }
    }
    if (cursor !== null) covered += end - cursor
    total += strip * covered
  }
  return total
}

/** Fraction of the spanned image that lands on a display, 0..1. */
export function coverage(rects) {
  const box = spanBox(rects)
  if (!box || box.w * box.h === 0) return 0
  return unionArea(rects) / (box.w * box.h)
}
