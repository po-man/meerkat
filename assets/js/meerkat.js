// The Meerkat key visual.
//
// A small, dependency-free state machine on top of the inline SVG rendered by
// QaAppWeb.Components.Meerkat. The SVG is a static figure carrying data-part
// hooks; CSS owns the continuous ambient motion (breathing body, tail sway) so
// the meerkat is alive from the first paint and survives a JavaScript failure.
// This module owns the discrete beats:
//
//   blink  - the eye groups squash, occasionally twice
//   roll   - the pupils arc inside their sockets, sometimes with a head tilt
//   ask    - the raised paw pumps
//   reach  - it stretches taller, rises onto its toes, perches its ears and
//            sometimes scans
//
// The mascot is deliberately eager: the paw raise is the point of the pose, so
// it is the most frequent beat, and the reach follows close behind. Beats are
// scheduled on randomized timers and gated by viewport visibility and tab focus.
// Everything animates transform only, so every beat stays on the compositor.
//
// Only the tail, head, arm and feet rotate. Rotating the body of a standing
// animal reads as a shake, so whole-body motion stays vertical: it breathes and
// it rises. The feet pivot on their toes, which is what makes the rise read as
// a tiptoe rather than as a rubber stretch.
//
// The SVG is not on a LiveView root (the landing page is a static controller)
// so this is a plain module, not a phx-hook.

const REDUCED_MOTION = "(prefers-reduced-motion: reduce)"

const EASE = "cubic-bezier(0.33, 0, 0.2, 1)"

const PREFERS_REDUCED_MOTION = () => window.matchMedia(REDUCED_MOTION).matches

const rand = (min, max) => min + Math.random() * (max - min)

const BLINK = [
  {transform: "scaleY(1)"},
  {transform: "scaleY(0.08)", offset: 0.5},
  {transform: "scaleY(1)"},
]

const ROLL = [
  {transform: "translate(0, 0)"},
  {transform: "translate(-4px, -5px)", offset: 0.18},
  {transform: "translate(5px, -4px)", offset: 0.4},
  {transform: "translate(4px, 4px)", offset: 0.68},
  {transform: "translate(-3px, 3px)", offset: 0.85},
  {transform: "translate(0, 0)"},
]

const ROLL_HEAD = [
  {transform: "rotate(0deg)"},
  {transform: "rotate(-3deg)", offset: 0.35},
  {transform: "rotate(2deg)", offset: 0.7},
  {transform: "rotate(0deg)"},
]

const ASK = [
  {transform: "rotate(0deg)"},
  {transform: "rotate(-13deg)", offset: 0.16},
  {transform: "rotate(2.5deg)", offset: 0.38},
  {transform: "rotate(-12deg)", offset: 0.58},
  {transform: "rotate(1.5deg)", offset: 0.78},
  {transform: "rotate(0deg)"},
]

const PERK = [
  {transform: "scaleY(1)"},
  {transform: "scaleY(1.07)", offset: 0.32},
  {transform: "scaleY(1)"},
]

// The body's own rise is deliberately small, because it is what opens the joint:
// where the leg's lower edge crosses the foot's top edge (~x=191 front, the heel
// of the back foot), the leg rising faster than that edge leaves a notch. A sweep
// of the two parameters measured the worst gap at each combination, and 4 units
// here with 10 degrees in TIPTOE keeps it under 2 units (~2px) while the heel
// still lifts ~19px on screen. The trunk stretch supplies the rest of the height,
// so the reach loses nothing.
const ALERT_BODY = [
  {transform: "translateY(0) scaleX(1) scaleY(1)"},
  {transform: "translateY(-3px) scaleX(0.995) scaleY(1.03)", offset: 0.22},
  {transform: "translateY(-4px) scaleX(0.99) scaleY(1.035)", offset: 0.42},
  {transform: "translateY(-4px) scaleX(0.99) scaleY(1.035)", offset: 0.62},
  {transform: "translateY(0) scaleX(1) scaleY(1)"},
]

// The heels come off the ground. They reach full lift *before* the body reaches
// full height, which is the safe order as well as the physical one: while the
// foot is still flat its silhouette only covers a body rise of ~11 units, and
// rotating it first raises that allowance to ~18. The back foot trails the front
// slightly (see BACK_FOOT_LAG_MS) so the pair does not move as one rigid piece.
const TIPTOE = [
  {transform: "rotate(0deg)"},
  {transform: "rotate(10deg)", offset: 0.26},
  {transform: "rotate(10deg)", offset: 0.62},
  {transform: "rotate(0deg)"},
]

const BACK_FOOT_LAG_MS = 40

// A single sweep, not a wiggle. It fires on roughly half the reaches, so a
// more frequent reach does not turn the head into a metronome.
const ALERT_SCAN = [
  {transform: "rotate(0deg)"},
  {transform: "rotate(-3.5deg)", offset: 0.3},
  {transform: "rotate(3.5deg)", offset: 0.65},
  {transform: "rotate(0deg)"},
]

class Meerkat {
  constructor(root) {
    this.root = root
    this.running = false
    this.visible = true
    this.timers = new Set()
    this.animations = new Map()

    const part = name => root.querySelector(`[data-part="${name}"]`)
    this.body = part("meerkat")
    this.arm = part("arm-raised")
    this.footBack = part("foot-back")
    this.footFront = part("foot-front")
    this.head = part("head-unit")
    this.earLeft = part("ear-left")
    this.earRight = part("ear-right")
    this.eyeLeft = part("eye-left")
    this.eyeRight = part("eye-right")
    this.pupilLeft = part("pupil-left")
    this.pupilRight = part("pupil-right")

    this.onPointer = () => this.wave()
    this.onVisibilityChange = () => (document.hidden ? this.pause() : this.resume())

    this.observer = new IntersectionObserver(
      entries => {
        for (const entry of entries) {
          this.visible = entry.isIntersecting
          if (this.visible) this.resume()
          else this.pause()
        }
      },
      {threshold: 0.15}
    )
  }

  // One beat per part: starting a new animation on a part cancels the one in
  // flight, so overlapping beats never fight over the same transform.
  play(el, keyframes, options) {
    if (!el) return

    this.animations.get(el)?.cancel()

    const animation = el.animate(keyframes, {easing: EASE, ...options})
    this.animations.set(el, animation)
  }

  busy(el) {
    return el != null && this.animations.get(el)?.playState === "running"
  }

  blink() {
    const options = {duration: 130, easing: "ease-in-out"}
    const blink = () => {
      this.play(this.eyeLeft, BLINK, options)
      this.play(this.eyeRight, BLINK, options)
    }

    blink()
    if (Math.random() < 0.35) this.schedule(blink, 200)
  }

  roll() {
    const options = {duration: 820, easing: "ease-in-out"}
    this.play(this.pupilLeft, ROLL, options)
    this.play(this.pupilRight, ROLL, options)

    // The alert scan already owns the head; don't cut it off mid-sweep.
    if (Math.random() < 0.5 && !this.busy(this.head)) {
      this.play(this.head, ROLL_HEAD, {duration: 1000, easing: EASE})
    }
  }

  // The signature beat. Only the arm moves: the body used to bob along with it,
  // which read as a shiver rather than as eagerness.
  pump(duration = 1050) {
    this.play(this.arm, ASK, {duration, easing: EASE})
  }

  // Skipped rather than restarted while one is in flight, so the rhythm stays
  // even instead of stuttering.
  ask() {
    if (this.busy(this.arm)) return

    this.pump()
  }

  // Up onto the toes. The heels lift; the back foot trails the front by a frame
  // or two so the pair does not move as one rigid piece. The body's rise is small
  // on purpose (see ALERT_BODY) so the legs never outrun the feet's silhouette.
  tipToe(duration) {
    const options = {duration, easing: EASE}
    this.play(this.footFront, TIPTOE, options)
    this.play(this.footBack, TIPTOE, {...options, delay: BACK_FOOT_LAG_MS})
  }

  // The whole "look at me" gesture: rise, then the feet follow.
  reach(duration) {
    this.play(this.body, ALERT_BODY, {duration, easing: EASE})
    this.tipToe(duration)
  }

  // Hovering or tapping is the reader answering the mascot, so it goes all the
  // way up onto its toes and waves back, on a shorter beat than the idle reach.
  wave() {
    if (!this.running) return

    const duration = 900
    this.reach(duration)
    this.pump(duration)
  }

  alert() {
    const duration = 1500
    const perk = {duration: 650, easing: "ease-out"}

    this.reach(duration)
    this.play(this.earLeft, PERK, perk)
    this.play(this.earRight, PERK, perk)

    // Every other reach also scans, and never cuts an eye-roll head tilt short.
    if (Math.random() < 0.5 && !this.busy(this.head)) {
      this.play(this.head, ALERT_SCAN, {duration, easing: EASE})
    }
  }

  schedule(callback, delay) {
    const id = window.setTimeout(() => {
      this.timers.delete(id)
      if (this.running) callback()
    }, delay)

    this.timers.add(id)
    return id
  }

  every(callback, min, max) {
    const tick = () => {
      if (!this.running) return
      callback()
      this.schedule(tick, rand(min, max))
    }

    this.schedule(tick, rand(min, max))
  }

  start() {
    if (this.started) {
      this.resume()
      return
    }

    this.started = true
    this.root.addEventListener("pointerenter", this.onPointer)
    this.root.addEventListener("click", this.onPointer)
    document.addEventListener("visibilitychange", this.onVisibilityChange)
    this.observer.observe(this.root)
    this.resume()
  }

  resume() {
    if (this.running || document.hidden || !this.visible || PREFERS_REDUCED_MOTION()) return

    this.running = true
    this.root.dataset.meerkatState = "running"

    // Greet the reader once, shortly after load, then settle into the loop.
    if (!this.greeted) {
      this.greeted = true
      this.schedule(() => this.alert(), 600)
    }

    this.every(() => this.blink(), 1300, 2900)
    this.every(() => this.roll(), 4000, 7000)
    this.every(() => this.ask(), 1500, 2800)
    this.every(() => this.alert(), 2600, 4400)
  }

  pause() {
    if (!this.running) return

    this.running = false
    this.root.dataset.meerkatState = "paused"
    this.clearTimers()
  }

  clearTimers() {
    for (const id of this.timers) window.clearTimeout(id)
    this.timers.clear()
  }

  stop() {
    this.pause()
    this.started = false
    this.root.removeEventListener("pointerenter", this.onPointer)
    this.root.removeEventListener("click", this.onPointer)
    document.removeEventListener("visibilitychange", this.onVisibilityChange)
    this.observer.disconnect()

    for (const animation of this.animations.values()) animation.cancel()
    this.animations.clear()
  }
}

export function initMeerkat() {
  const roots = document.querySelectorAll("[data-meerkat]")
  if (roots.length === 0) return []

  const meerkats = Array.from(roots, root => new Meerkat(root))

  const sync = () => {
    for (const meerkat of meerkats) {
      if (PREFERS_REDUCED_MOTION()) meerkat.stop()
      else meerkat.start()
    }
  }

  sync()
  window.matchMedia(REDUCED_MOTION).addEventListener("change", sync)

  return meerkats
}
