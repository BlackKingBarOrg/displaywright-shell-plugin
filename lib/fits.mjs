// Where a picture lands inside a rectangle, for each fit.
//
// The renderer and the preview call this same function, so "what you see is
// what the display gets" is a property of the code rather than a promise.
//
// Everything is in *logical* pixels, the space Hyprland lays displays out in.
// Two fits are defined in device pixels instead: Center draws the file at its
// own resolution and Tile repeats it at its own resolution, so both take the
// output's device pixel ratio and divide through by it.

export const FITS = ["fill", "fit", "stretch", "tile", "center"]

export const FIT_LABELS = {
  fill: "Fill", fit: "Fit", stretch: "Stretch", tile: "Tile", center: "Center",
}

/** True when the fit can leave bare space the backdrop shows through. */
export function usesBackdrop(fit) {
  return fit === "fit" || fit === "center"
}

/** The size a 1:1 rendering of the file occupies, in logical pixels. */
export function naturalSize(imageW, imageH, dpr = 1) {
  const scale = dpr > 0 ? dpr : 1
  return [imageW / scale, imageH / scale]
}

/**
 * `[x, y, width, height]` of the drawn image, relative to the box.
 *
 * A negative x or y means the picture overflows and gets cropped, which is
 * what Fill does on every display whose aspect ratio differs from the file's.
 */
export function fittedRect(fit, imageW, imageH, boxW, boxH, dpr = 1) {
  if (imageW <= 0 || imageH <= 0 || boxW <= 0 || boxH <= 0) return [0, 0, boxW, boxH]

  if (fit === "stretch") return [0, 0, boxW, boxH]

  if (fit === "center") {
    const [w, h] = naturalSize(imageW, imageH, dpr)
    return [(boxW - w) / 2, (boxH - h) / 2, w, h]
  }

  if (fit === "tile") {
    // The tile itself; the caller repeats it from the top-left corner.
    const [w, h] = naturalSize(imageW, imageH, dpr)
    return [0, 0, w, h]
  }

  // Fill crops to cover, Fit letterboxes to contain. Both keep the aspect.
  const scale = fit === "fill"
    ? Math.max(boxW / imageW, boxH / imageH)
    : Math.min(boxW / imageW, boxH / imageH)
  const w = imageW * scale
  const h = imageH * scale
  return [(boxW - w) / 2, (boxH - h) / 2, w, h]
}

/**
 * Where a spanned picture sits relative to *one* output's top-left corner.
 *
 * `box` is the bounding box of every output and `offset` is where this output
 * sits inside it. The picture covers the whole box the way Fill covers one
 * display, and each output shows the slice that falls on it.
 */
export function spanRect(imageW, imageH, boxW, boxH, offsetX, offsetY) {
  const [x, y, w, h] = fittedRect("fill", imageW, imageH, boxW, boxH)
  return [x - offsetX, y - offsetY, w, h]
}
