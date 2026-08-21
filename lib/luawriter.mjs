// Rendering a layout into Omarchy's Lua monitor config.
//
// Omarchy configures Hyprland in Lua, so persisting a layout means emitting
// `hl.monitor({ ... })` into ~/.config/hypr/monitors.lua. Field names come from
// Hyprland's own HL.MonitorSpec stub (/usr/share/hypr/stubs/hl.meta.lua).
//
// Writes are conservative: everything outside the managed block is preserved,
// pre-existing hl.monitor calls are commented out rather than deleted, and the
// caller is expected to take a backup first.

import { isBuiltin, modeHypr, prettyName, summary, trimNumber } from "./geometry.mjs"

export const BEGIN =
  "-- >>> displaywright managed block: edited by `displaywright`, safe to move as a whole >>>"
export const END = "-- <<< displaywright managed block <<<"

// The markers hyprlayout wrote, before it and wallwright became one app. A
// config still carrying them is rewritten in place rather than given a second
// block underneath the first.
export const LEGACY_MARKERS = [
  [
    "-- >>> hyprlayout managed block: edited by `hyprlayout`, safe to move as a whole >>>",
    "-- <<< hyprlayout managed block <<<",
  ],
]

const HEADER =
  "-- Generated from displaywright. Anything outside this block is left\n"
  + "-- alone; anything inside it is replaced on the next save."

export function luaString(value) {
  return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`
}

/** `hl.monitor({ ... })` for one output: what gets written *and* evaluated. */
export function renderCall(state) {
  const fields = [`output = ${luaString(state.name)}`]
  if (!state.enabled) {
    fields.push("disabled = true")
  } else {
    fields.push(`mode = ${luaString(state.mode ? modeHypr(state.mode) : "preferred")}`)
    fields.push(`position = ${luaString(`${state.x}x${state.y}`)}`)
    fields.push(`scale = ${trimNumber(state.scale)}`)
    if (state.transform) fields.push(`transform = ${state.transform}`)
    if (state.mirrorOf) fields.push(`mirror = ${luaString(state.mirrorOf)}`)
    if (state.vrr !== null && state.vrr !== undefined) fields.push(`vrr = ${state.vrr}`)
  }
  return `hl.monitor({ ${fields.join(", ")} })`
}

/** The comma-separated argument list of a legacy (hyprlang) monitor rule. */
export function ruleArgs(state) {
  if (!state.enabled) return `${state.name},disable`
  const mode = state.mode ? modeHypr(state.mode) : "preferred"
  const parts = [state.name, mode, `${state.x}x${state.y}`, trimNumber(state.scale)]
  if (state.transform) parts.push("transform", String(state.transform))
  if (state.mirrorOf) parts.push("mirror", state.mirrorOf)
  if (state.vrr !== null && state.vrr !== undefined) parts.push("vrr", String(state.vrr))
  return parts.join(",")
}

/**
 * The full managed block, markers included.
 *
 * With `toggleBuiltin`, a switched-off laptop panel is still written as an
 * *enabled* rule: its "off" lives in Omarchy's internal-monitor-disable toggle
 * instead, the only place something removes again when the external display
 * goes away. The rule left here is what Omarchy reads to restore the panel.
 */
export function renderBlock(states, toggleBuiltin = false) {
  const ordered = states.slice().sort((a, b) =>
    (Number(!a.enabled) - Number(!b.enabled)) || (a.x - b.x) || (a.y - b.y)
      || a.name.localeCompare(b.name))
  const lines = [BEGIN, HEADER]
  for (const state of ordered) {
    const viaToggle = toggleBuiltin && isBuiltin(state) && !state.enabled
    let written = state
    if (viaToggle) {
      written = {}
      for (const key in state) written[key] = state[key]
      written.enabled = true
    }
    const label = prettyName(written)
    const detail = summary(written)
    lines.push(label && label !== written.name
      ? `-- ${written.name}: ${label} — ${detail}`
      : `-- ${written.name}: ${detail}`)
    if (viaToggle) {
      lines.push("-- currently switched off via Omarchy's internal-monitor-disable toggle,")
      lines.push("-- which comes back automatically when no external display is left.")
    }
    lines.push(renderCall(written))
  }
  lines.push(END)
  return lines.join("\n") + "\n"
}

const OUTPUT_RE = /output\s*=\s*"([^"]*)"/

/** Inclusive line ranges of top-level `hl.monitor(...)` calls. */
function callSpans(lines) {
  const spans = []
  let start = -1
  let depth = 0
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index]
    // Qt's JS engine has no String.trimStart.
    if (depth === 0 && /^\s*hl\.monitor\(/.test(line)) {
      start = index
      depth = 0
    } else if (start < 0) {
      continue
    }
    depth += (line.split("(").length - 1) - (line.split(")").length - 1)
    if (start >= 0 && depth <= 0) {
      spans.push([start, index])
      start = -1
      depth = 0
    }
  }
  if (start >= 0) spans.push([start, lines.length - 1])   // unbalanced; take the rest
  return spans
}

/**
 * Comment out the `hl.monitor` calls this tool now owns. Rules we are *not*
 * managing are left alone: the catch-all (`output = ""`) that configures
 * displays on first plug-in, and rules for monitors that are not connected.
 */
function commentOutMonitorCalls(text, managed) {
  const lines = text.split("\n")
  const doomed = new Set()
  let commented = 0
  for (const [start, end] of callSpans(lines)) {
    const match = OUTPUT_RE.exec(lines.slice(start, end + 1).join("\n"))
    const name = match ? match[1] : null
    if (name === null || name === "" || name === "*") continue
    if (managed && !managed.has(name)) continue
    for (let i = start; i <= end; i++) doomed.add(i)
    commented += 1
  }
  const out = lines.map((line, index) =>
    doomed.has(index) ? `-- [displaywright] replaced: ${line}` : line)
  return [out.join("\n"), commented]
}

function existingMarkers(text) {
  for (const [begin, end] of [[BEGIN, END]].concat(LEGACY_MARKERS)) {
    if (text.includes(begin) && text.includes(end)) return [begin, end]
  }
  return null
}

/** Splice `block` into `existing`, preserving the user's own lines. */
export function merge(existing, block, managed = null) {
  const markers = existingMarkers(existing)
  if (markers) {
    const [begin, end] = markers
    const head = existing.slice(0, existing.indexOf(begin))
    const tail = existing.slice(existing.indexOf(end) + end.length)
    return head + block.replace(/\n+$/, "") + tail
  }

  let [body, commented] = commentOutMonitorCalls(existing, managed)
  if (body && !body.endsWith("\n")) body += "\n"
  let note = ""
  if (commented) {
    note = `-- displaywright commented out ${commented} earlier hl.monitor call(s);\n`
      + "-- delete them once you are happy with the block below.\n"
  }
  const separator = body.trim() ? "\n" : ""
  return `${body}${separator}${note}${block}`
}

export function renderFile(existing, states, toggleBuiltin = false) {
  return merge(existing, renderBlock(states, toggleBuiltin), new Set(states.map(s => s.name)))
}

/** A unified diff, enough for the confirmation dialog to be honest. */
export function diff(oldText, newText, path = "monitors.lua") {
  const a = oldText.split("\n")
  const b = newText.split("\n")
  if (oldText === newText) return ""
  // Longest common subsequence over lines. Configs are small; clarity wins.
  const lcs = []
  for (let i = 0; i <= a.length; i++) lcs.push(new Array(b.length + 1).fill(0))
  for (let i = a.length - 1; i >= 0; i--) {
    for (let j = b.length - 1; j >= 0; j--) {
      lcs[i][j] = a[i] === b[j] ? lcs[i + 1][j + 1] + 1 : Math.max(lcs[i + 1][j], lcs[i][j + 1])
    }
  }
  const out = [`--- a/${path}`, `+++ b/${path}`]
  let i = 0
  let j = 0
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) { out.push(` ${a[i]}`); i++; j++ }
    else if (lcs[i + 1][j] >= lcs[i][j + 1]) { out.push(`-${a[i]}`); i++ }
    else { out.push(`+${b[j]}`); j++ }
  }
  while (i < a.length) out.push(`-${a[i++]}`)
  while (j < b.length) out.push(`+${b[j++]}`)
  return out.join("\n") + "\n"
}
