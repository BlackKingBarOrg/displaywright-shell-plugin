// Monitor geometry, in the coordinate space Hyprland lays displays out in.
//
// Ported from the Python that used to back the GTK window, and kept as a plain
// ES module so QML can import it and `node` can test it. Nothing in here knows
// about Qt: it takes `hyprctl -j monitors all` and gives back numbers.

/** Transform -> [label, turns the picture through a quarter turn?] */
export const TRANSFORMS = {
  0: ["Normal", false],
  1: ["90°", true],
  2: ["180°", false],
  3: ["270°", true],
  4: ["Flipped", false],
  5: ["Flipped + 90°", true],
  6: ["Flipped + 180°", false],
  7: ["Flipped + 270°", true],
}

/** How Omarchy identifies the laptop panel. */
const BUILTIN_RE = /^(eDP|LVDS|DSI)-/i
const MODE_RE = /^\s*(\d+)\s*x\s*(\d+)\s*(?:@\s*([\d.]+)\s*(?:Hz)?)?\s*$/i

/** How far a reported refresh rate may drift and still be the same mode. */
export const REFRESH_TOLERANCE = 1.5

export function parseMode(text) {
  const m = MODE_RE.exec(String(text || ""))
  if (!m) return null
  return { width: +m[1], height: +m[2], refresh: m[3] ? parseFloat(m[3]) : 0 }
}

export function modeResolution(mode) {
  return `${mode.width}x${mode.height}`
}

/** The form Hyprland accepts in a monitor rule. */
export function modeHypr(mode) {
  if (!mode.refresh) return modeResolution(mode)
  // Hyprland matches refresh with a tolerance, so two decimals is plenty --
  // and dropping a trailing ".00" keeps generated config tidy.
  let text = mode.refresh.toFixed(2)
  if (text.endsWith(".00")) text = text.slice(0, -3)
  return `${modeResolution(mode)}@${text}`
}

export function modeLabel(mode) {
  if (!mode.refresh) return `${mode.width}×${mode.height}`
  return `${mode.width}×${mode.height} @ ${trimNumber(mode.refresh)} Hz`
}

export function modesEqual(a, b) {
  if (!a || !b) return a === b
  return a.width === b.width && a.height === b.height && a.refresh === b.refresh
}

/** Render a number the way "%g" would: no trailing zeros. */
export function trimNumber(value) {
  return String(Math.round(value * 1e6) / 1e6)
}

function closestMode(target, modes, tolerance = REFRESH_TOLERANCE) {
  const sameRes = modes.filter(m => m.width === target.width && m.height === target.height)
  if (sameRes.length === 0) return null
  let best = sameRes[0]
  for (const m of sameRes) {
    if (Math.abs(m.refresh - target.refresh) < Math.abs(best.refresh - target.refresh)) best = m
  }
  // A genuinely off-list rate -- a link-limited ultrawide running 50Hz -- is
  // preserved verbatim rather than rewritten to a neighbouring one.
  if (target.refresh && Math.abs(best.refresh - target.refresh) > tolerance) return null
  return best
}

/**
 * One output, as the arrangement UI edits it.
 *
 * `hyprctl` reports the *mode*, which is always the panel's native landscape
 * resolution: a portrait 2560x1440 is still reported 2560x1440, and every entry
 * in availableModes agrees. Rotating it here would invent a mode no display
 * has, and applying that mode fails.
 */
export function stateFromHyprctl(data) {
  const modes = []
  for (const raw of data.availableModes || []) {
    const parsed = parseMode(raw)
    if (parsed && !modes.some(m => modesEqual(m, parsed))) modes.push(parsed)
  }
  modes.sort((a, b) => (b.width * b.height - a.width * a.height) || (b.refresh - a.refresh))

  const disabled = !!data.disabled
  const scale = Number(data.scale) > 0 ? Number(data.scale) : 1
  const transform = Number(data.transform) || 0

  let mode = null
  const width = Number(data.width) || 0
  const height = Number(data.height) || 0
  if (width && height) {
    mode = { width, height, refresh: Number(data.refreshRate) || 0 }
    mode = closestMode(mode, modes) || mode
  }

  const mirror = data.mirrorOf || "none"
  return {
    name: data.name || "?",
    description: data.description || "",
    make: data.make || "",
    model: data.model || "",
    serial: data.serial || "",
    physicalWidth: Number(data.physicalWidth) || 0,
    physicalHeight: Number(data.physicalHeight) || 0,
    enabled: !disabled,
    mode: disabled ? null : mode,
    scale,
    transform,
    x: Number(data.x) || 0,
    y: Number(data.y) || 0,
    vrr: null,
    mirrorOf: (mirror === "none" || mirror === "") ? null : mirror,
    availableModes: modes,
    focused: !!data.focused,
  }
}

export function copyState(state) {
  // Written out rather than spread: Qt's QML engine rejects object spread, and
  // this module is imported by the renderer as well as by node.
  const copy = {}
  for (const key in state) copy[key] = state[key]
  copy.availableModes = state.availableModes.slice()
  return copy
}

/** Compare only the fields that get pushed to Hyprland. */
export function configEquals(a, b) {
  return a.enabled === b.enabled
    && modesEqual(a.mode, b.mode)
    && a.scale === b.scale
    && a.transform === b.transform
    && a.x === b.x
    && a.y === b.y
    && a.vrr === b.vrr
    && a.mirrorOf === b.mirrorOf
}

export function preferredMode(state) {
  if (!state.availableModes.length) return { width: 1920, height: 1080, refresh: 60 }
  return state.availableModes.reduce((best, m) =>
    (m.width * m.height > best.width * best.height
      || (m.width * m.height === best.width * best.height && m.refresh > best.refresh)) ? m : best)
}

/** Native pixels of the selected mode, before rotation and scaling. */
export function pixelSize(state) {
  if (state.mode) return [state.mode.width, state.mode.height]
  if (state.availableModes.length) {
    const best = preferredMode(state)
    return [best.width, best.height]
  }
  return [1920, 1080]
}

export function isRotated(state) {
  const entry = TRANSFORMS[state.transform]
  return entry ? entry[1] : false
}

/** Device pixels as the panel actually shows them: what a wallpaper covers. */
export function pixelSizeRotated(state) {
  const [w, h] = pixelSize(state)
  return isRotated(state) ? [h, w] : [w, h]
}

/** Size in layout coordinates, after rotation and scaling. */
export function logicalSize(state) {
  const [w, h] = pixelSizeRotated(state)
  const scale = state.scale || 1
  return [w / scale, h / scale]
}

export function rectOf(state) {
  const [w, h] = logicalSize(state)
  return { x: state.x, y: state.y, w, h }
}

export function rectRight(r) { return r.x + r.w }
export function rectBottom(r) { return r.y + r.h }
export function rectContains(r, px, py) {
  return r.x <= px && px <= rectRight(r) && r.y <= py && py <= rectBottom(r)
}

export function rectsOverlap(a, b, tol = 0.5) {
  return a.x < rectRight(b) - tol && b.x < rectRight(a) - tol
    && a.y < rectBottom(b) - tol && b.y < rectBottom(a) - tol
}

export function boundingBox(rects) {
  if (!rects.length) return { x: 0, y: 0, w: 0, h: 0 }
  const x0 = Math.min(...rects.map(r => r.x))
  const y0 = Math.min(...rects.map(r => r.y))
  const x1 = Math.max(...rects.map(rectRight))
  const y1 = Math.max(...rects.map(rectBottom))
  return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }
}

export function isBuiltin(state) {
  return BUILTIN_RE.test(state.name)
}

export function prettyName(state) {
  const parts = [state.make, state.model].filter(p => p && !p.startsWith("0x"))
  if (parts.length) return parts.join(" ")
  return state.description || state.name
}

/** What the arrangement view says about a display. */
export function summary(state) {
  if (!state.enabled) return "disabled"
  if (state.mirrorOf) return `mirrors ${state.mirrorOf}`
  const [w, h] = logicalSize(state)
  const bits = [state.mode ? modeLabel(state.mode) : "preferred"]
  if (Math.abs(state.scale - 1) > 1e-6) {
    bits.push(`scale ${trimNumber(state.scale)} → ${Math.round(w)}×${Math.round(h)}`)
  }
  if (state.transform) bits.push(TRANSFORMS[state.transform][0])
  return bits.join(" · ")
}

/** The resolution a wallpaper has to fill, and what the desktop makes of it. */
export function panelSummary(state) {
  const [pw, ph] = pixelSizeRotated(state)
  let text = `${pw}×${ph}`
  if (Math.abs(state.scale - 1) > 1e-6) {
    const [w, h] = logicalSize(state)
    text += ` · scale ${trimNumber(state.scale)} → ${Math.round(w)}×${Math.round(h)}`
  }
  if (isRotated(state)) text += " · rotated"
  return text
}

export function dpi(state) {
  if (state.physicalWidth <= 0) return 0
  const [pw] = pixelSize(state)
  return pw / (state.physicalWidth / 25.4)
}

export function diagonalInches(state) {
  if (state.physicalWidth <= 0 || state.physicalHeight <= 0) return 0
  return Math.hypot(state.physicalWidth, state.physicalHeight) / 25.4
}

/**
 * Scales worth suggesting: the ones that stay predictable across toolkits.
 *
 * Below 1 as well as above. A scale under 1 makes everything smaller, which is
 * what a large low-density panel wants -- a 40" 4K at arm's length is under
 * 60dpi, and 1 leaves it enormous.
 */
export const COMMON_SCALES = [
  0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95,
  1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 3,
]

/**
 * The scales the arrangement offers, with whatever the display is *actually*
 * running folded in. Hyprland accepts any scale and Omarchy's own display
 * settings write ones this list does not have; leaving the current value out
 * means the control cannot show it and cannot put it back.
 */
export function scaleChoices(current) {
  const out = COMMON_SCALES.slice()
  const value = Number(current)
  if (value > 0 && !out.some(s => Math.abs(s - value) < 1e-9)) out.push(value)
  out.sort((a, b) => a - b)
  return out
}
export const TARGET_DPI = 110

export function suggestScale(state) {
  const [pw, ph] = pixelSize(state)
  const density = dpi(state)
  if (density <= 0) return ph >= 1800 ? 2 : 1
  const integral = s => [pw, ph].every(px => Math.abs(px / s - Math.round(px / s)) < 0.001)
  const candidates = COMMON_SCALES.filter(integral)
  const pool = candidates.length ? candidates : COMMON_SCALES
  return pool.reduce((best, s) =>
    Math.abs(density / s - TARGET_DPI) < Math.abs(density / best - TARGET_DPI) ? s : best)
}

/** Hyprland nudges scales that do not yield an integer logical size. */
export function scaleWarning(state) {
  if (!state.enabled) return null
  const [w, h] = logicalSize(state)
  for (const [value, axis] of [[w, "width"], [h, "height"]]) {
    if (Math.abs(value - Math.round(value)) > 0.001) {
      return `scale ${trimNumber(state.scale)} gives a fractional logical ${axis} `
        + `(${value.toFixed(3)}px) — Hyprland will nudge it to the nearest usable scale`
    }
  }
  return null
}

/** What Hyprland did not actually deliver, compared with what was asked. */
export function unmetRequests(requested, achieved) {
  const byName = new Map(achieved.map(s => [s.name, s]))
  const problems = []
  for (const want of requested) {
    const got = byName.get(want.name)
    if (!got || !want.enabled || !got.enabled) continue
    if (want.mode && got.mode && !modesEqual(got.mode, want.mode)) {
      problems.push(`${want.name} is running ${modeLabel(got.mode)}, not the requested `
        + `${modeLabel(want.mode)}`)
    }
    if (Math.abs(got.scale - want.scale) > 0.001) {
      problems.push(`${want.name} scale settled at ${trimNumber(got.scale)}, `
        + `not ${trimNumber(want.scale)}`)
    }
  }
  return problems
}
