// Layout geometry: edge snapping, collision push-out and sanity checks.
//
// All coordinates are Hyprland *logical* pixels -- the space monitor positions
// live in -- so what the canvas produces can go straight into a monitor rule.

import { boundingBox, logicalSize, rectBottom, rectOf, rectRight, rectsOverlap }
  from "./geometry.mjs"

// How close an edge has to be before it snaps. Generous, because the canvas is
// heavily zoomed out: 120px of layout space is a few px of mouse travel.
export const SNAP_THRESHOLD = 120

function candidates(size, others, axis) {
  const out = []
  for (const o of others) {
    const lo = axis === "x" ? o.x : o.y
    const hi = axis === "x" ? rectRight(o) : rectBottom(o)
    const oSize = axis === "x" ? o.w : o.h
    const center = lo + oSize / 2
    out.push([hi, hi])                            // attach after
    out.push([lo - size, lo])                     // attach before
    out.push([lo, lo])                            // align leading edges
    out.push([hi - size, hi])                     // align trailing edges
    out.push([center - size / 2, center])         // align centres
  }
  return out
}

function nearest(list, target) {
  let best = null
  for (const c of list) {
    if (best === null || Math.abs(c[0] - target) < Math.abs(best[0] - target)) best = c
  }
  return best
}

/**
 * Snap `moving` to the nearest edges of `others`, each axis independently --
 * which is what makes "drag roughly right and let go" land pixel-perfect.
 */
export function snapPosition(moving, others, threshold = SNAP_THRESHOLD) {
  let { x, y } = moving
  const guides = []
  if (others.length) {
    const bx = nearest(candidates(moving.w, others, "x"), moving.x)
    if (bx && Math.abs(bx[0] - moving.x) <= threshold) { x = bx[0]; guides.push(["v", bx[1]]) }
    const by = nearest(candidates(moving.h, others, "y"), moving.y)
    if (by && Math.abs(by[0] - moving.y) <= threshold) { y = by[0]; guides.push(["h", by[1]]) }
  }
  return { x: Math.round(x), y: Math.round(y), guides }
}

/** Resolve overlap by shifting `moving` along its cheapest escape axis. */
export function pushOut(moving, others) {
  let { x, y } = moving
  for (let i = 0; i <= others.length; i++) {
    const current = { x: x, y: y, w: moving.w, h: moving.h }
    const hit = others.find(o => rectsOverlap(current, o))
    if (!hit) break
    const options = [
      [rectRight(hit) - current.x, [rectRight(hit), y]],
      [rectRight(current) - hit.x, [hit.x - current.w, y]],
      [rectBottom(hit) - current.y, [x, rectBottom(hit)]],
      [rectBottom(current) - hit.y, [x, hit.y - current.h]],
    ]
    const best = options.reduce((a, b) => (b[0] < a[0] ? b : a))
    x = best[1][0]
    y = best[1][1]
  }
  return [Math.round(x), Math.round(y)]
}

/** Snap, then guarantee the result does not overlap anything. */
export function snapAndResolve(moving, others, threshold = SNAP_THRESHOLD) {
  const snapped = snapPosition(moving, others, threshold)
  const [x, y] = pushOut({ x: snapped.x, y: snapped.y, w: moving.w, h: moving.h }, others)
  // Pushing out invalidates the guides we were about to draw.
  if (x !== snapped.x || y !== snapped.y) return { x, y, guides: [] }
  return snapped
}

/**
 * Shift everything so the top-left of the desktop sits at (0, 0). Hyprland
 * accepts negative coordinates; keeping the origin at zero makes generated
 * config far easier to read. Returns true if anything moved.
 */
export function normalize(states) {
  const enabled = states.filter(s => s.enabled)
  if (!enabled.length) return false
  const box = boundingBox(enabled.map(rectOf))
  const dx = -Math.round(box.x)
  const dy = -Math.round(box.y)
  if (dx === 0 && dy === 0) return false
  for (const s of enabled) { s.x += dx; s.y += dy }
  return true
}

/** Lay the enabled monitors out left to right, vertically centred. */
export function autoArrange(states) {
  const enabled = states.filter(s => s.enabled)
  if (!enabled.length) return
  enabled.sort((a, b) => (a.x - b.x) || (a.y - b.y))
  const tallest = Math.max(...enabled.map(s => logicalSize(s)[1]))
  let cursor = 0
  for (const s of enabled) {
    const [w, h] = logicalSize(s)
    // Positions must stay integral: Hyprland parses "1600x0", not "1600.0x0".
    s.x = Math.round(cursor)
    s.y = Math.round((tallest - h) / 2)
    cursor += w
  }
}

/** True when two rectangles share a border segment of non-zero length. */
function touches(a, b, tol = 1) {
  const vertical = (Math.abs(rectRight(a) - b.x) <= tol || Math.abs(rectRight(b) - a.x) <= tol)
    && Math.min(rectBottom(a), rectBottom(b)) - Math.max(a.y, b.y) > tol
  const horizontal = (Math.abs(rectBottom(a) - b.y) <= tol || Math.abs(rectBottom(b) - a.y) <= tol)
    && Math.min(rectRight(a), rectRight(b)) - Math.max(a.x, b.x) > tol
  return vertical || horizontal
}

/** Human-readable problems with a layout; an empty list means all good. */
export function validate(states) {
  const problems = []
  const enabled = states.filter(s => s.enabled)

  if (!enabled.length) {
    problems.push("Every display is disabled — you would end up with a black screen.")
    return problems
  }

  for (let i = 0; i < enabled.length; i++) {
    for (let j = i + 1; j < enabled.length; j++) {
      if (rectsOverlap(rectOf(enabled[i]), rectOf(enabled[j]))) {
        problems.push(`${enabled[i].name} and ${enabled[j].name} overlap.`)
      }
    }
  }

  // Islands: Hyprland allows gaps, but the pointer cannot cross them.
  if (enabled.length > 1) {
    let groups = []
    for (let i = 0; i < enabled.length; i++) {
      let linked = new Set([i])
      for (let j = 0; j < enabled.length; j++) {
        if (i !== j && touches(rectOf(enabled[i]), rectOf(enabled[j]))) linked.add(j)
      }
      const merged = groups.filter(g => Array.from(g).some(v => linked.has(v)))
      groups = groups.filter(g => !merged.includes(g))
      for (const g of merged) for (const v of g) linked.add(v)
      groups.push(linked)
    }
    if (groups.length > 1) {
      const sorted = groups.slice().sort((a, b) => a.size - b.size).slice(0, -1)
      const stranded = sorted.map(g => Array.from(g).map(i => enabled[i].name).sort().join(", "))
      problems.push("Not all displays touch — the pointer cannot reach "
        + stranded.join("; ") + ".")
    }
  }

  const names = new Set(states.map(s => s.name))
  for (const s of states) {
    if (s.mirrorOf && !names.has(s.mirrorOf)) {
      problems.push(`${s.name} mirrors unknown output ${s.mirrorOf}.`)
    }
    if (s.mirrorOf === s.name) problems.push(`${s.name} cannot mirror itself.`)
  }

  return problems
}
