// The apply cycle: push an arrangement to Hyprland, then give the user fifteen
// seconds to confirm it. The countdown is the guard against an arrangement
// that leaves no readable screen to click Keep on -- if nothing is clicked,
// the previous arrangement comes back on its own.
//
// The subtlety is that reverting is itself an apply. It runs the same hyprctl
// call, so "hyprctl finished" cannot mean "start a countdown" on its own: a
// revert would arm a second countdown, expire, revert again, and the dialog
// would return every fifteen seconds until something was clicked. The phase
// is what tells those two finishes apart.

export const IDLE = "idle"
export const APPLYING = "applying"
export const CONFIRMING = "confirming"
export const REVERTING = "reverting"

export const COUNTDOWN_SECONDS = 15

export function idle() {
  return { phase: IDLE, seconds: 0 }
}

/** The user pressed Apply. Refused while a hyprctl call is in flight. */
export function begin(flow) {
  if (flow.phase === APPLYING || flow.phase === REVERTING) return flow
  return { phase: APPLYING, seconds: 0 }
}

/** hyprctl returned. Only an apply earns a countdown; a revert ends the cycle. */
export function finished(flow) {
  if (flow.phase === APPLYING) return { phase: CONFIRMING, seconds: COUNTDOWN_SECONDS }
  return idle()
}

/** One second of the confirmation window. Hitting zero reverts. */
export function tick(flow) {
  if (flow.phase !== CONFIRMING) return flow
  const seconds = flow.seconds - 1
  if (seconds > 0) return { phase: CONFIRMING, seconds }
  return { phase: REVERTING, seconds: 0 }
}

/** The user confirmed. The new arrangement stands. */
export function keep(flow) {
  if (flow.phase !== CONFIRMING) return flow
  return idle()
}

/** The user asked for the previous arrangement back. */
export function revert(flow) {
  if (flow.phase !== CONFIRMING) return flow
  return { phase: REVERTING, seconds: 0 }
}

/** Whether the caller must now push the snapshot back to Hyprland. */
export function pushesSnapshot(flow) {
  return flow.phase === REVERTING
}
