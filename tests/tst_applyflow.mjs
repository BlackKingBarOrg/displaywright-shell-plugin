import assert from "node:assert/strict"
import { test } from "node:test"
import {
  APPLYING, CONFIRMING, COUNTDOWN_SECONDS, IDLE, REVERTING,
  begin, finished, idle, keep, pushesSnapshot, revert, tick,
} from "../lib/applyflow.mjs"

const expire = flow => {
  let f = flow
  for (let i = 0; i < COUNTDOWN_SECONDS; i++) f = tick(f)
  return f
}

test("a fresh flow is idle", () => {
  assert.equal(idle().phase, IDLE)
  assert.equal(pushesSnapshot(idle()), false)
})

test("Apply waits for hyprctl before counting down", () => {
  const f = begin(idle())
  assert.equal(f.phase, APPLYING)
  assert.equal(f.seconds, 0, "no countdown until the change is actually on screen")
})

test("the countdown starts when hyprctl returns", () => {
  const f = finished(begin(idle()))
  assert.equal(f.phase, CONFIRMING)
  assert.equal(f.seconds, COUNTDOWN_SECONDS)
})

test("Keep ends the cycle", () => {
  const f = keep(finished(begin(idle())))
  assert.equal(f.phase, IDLE)
  assert.equal(pushesSnapshot(f), false, "keeping must not push the old arrangement back")
})

test("letting the countdown run out reverts", () => {
  const f = expire(finished(begin(idle())))
  assert.equal(f.phase, REVERTING)
  assert.ok(pushesSnapshot(f))
})

test("the countdown ticks down one second at a time", () => {
  let f = finished(begin(idle()))
  f = tick(f)
  assert.equal(f.seconds, COUNTDOWN_SECONDS - 1)
  assert.equal(f.phase, CONFIRMING, "still asking, not reverting")
})

test("the revert's own hyprctl call does not arm a second countdown", () => {
  // The bug this module exists for: a revert re-arming itself, expiring,
  // reverting again -- a dialog every fifteen seconds forever.
  const reverting = expire(finished(begin(idle())))
  const after = finished(reverting)
  assert.equal(after.phase, IDLE)
  assert.equal(after.seconds, 0)
})

test("Revert pressed by hand behaves like the countdown expiring", () => {
  const byHand = revert(finished(begin(idle())))
  const byTimeout = expire(finished(begin(idle())))
  assert.deepEqual(byHand, byTimeout)
})

test("ticking outside the confirmation window changes nothing", () => {
  for (const f of [idle(), begin(idle()), expire(finished(begin(idle())))]) {
    assert.deepEqual(tick(f), f)
  }
})

test("Keep and Revert are ignored unless the dialog is up", () => {
  for (const f of [idle(), begin(idle())]) {
    assert.deepEqual(keep(f), f)
    assert.deepEqual(revert(f), f)
  }
})

test("Apply is refused while hyprctl is in flight", () => {
  const applying = begin(idle())
  assert.deepEqual(begin(applying), applying)
  const reverting = expire(finished(begin(idle())))
  assert.deepEqual(begin(reverting), reverting)
})

test("Apply again during the confirmation window restarts the cycle", () => {
  // Dragging a display further and pressing Apply again is ordinary use; it
  // must not be blocked by the dialog that the previous Apply put up.
  const f = begin(finished(begin(idle())))
  assert.equal(f.phase, APPLYING)
  assert.equal(f.seconds, 0)
})
