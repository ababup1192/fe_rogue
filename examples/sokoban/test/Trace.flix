// Trace (sokoban) — the game-specific inputs and shipped solutions that feed
// engine_world's Replay fold. The general machinery (Replay.Cue, Replay.play,
// Replay.timeline) lives in engine_world; this file only supplies Sokoban.Input
// values, the fixed clock, and the two levels' solutions as data.
//
// A Cue holds one Input for a number of frames; a Trace is a list of Cues. Driving
// a Trace is a fold over the pure tick (Replay.play / Replay.timeline), so one
// solution is three things at once — a unit test (pin the outcome), a film (render
// every frame), and a bug report (a failing Trace *is* the reproduction).
mod Trace {

    /// The fixed clock every replay runs on: 1/64 s per frame — dyadic, so
    /// every slide t and walk phase in the pinned outcomes is exact.
    pub def dt(): Float64 = 1.0 / 64.0

    pub def idle(): Sokoban.Input =
        { up = false, down = false, left = false, right = false,
          undo = false, enter = false, back = false, esc = false }

    def dirInput(d: Dir4.Dir4): Sokoban.Input = match d {
        case Dir4.Up    => { up = true | idle() }
        case Dir4.Down  => { down = true | idle() }
        case Dir4.Left  => { left = true | idle() }
        case Dir4.Right => { right = true | idle() }
    }

    /// Hold one input for n frames.
    pub def hold(input: Sokoban.Input, frames: Int32): Replay.Cue[Sokoban.Input] =
        { input = input, frames = frames }

    /// One walked move: tap the key for a frame, then let the slide land
    /// (a slide is 0.125 s = 8 frames at this clock).
    pub def walk(d: Dir4.Dir4): List[Replay.Cue[Sokoban.Input]] =
        hold(dirInput(d), 1) :: hold(idle(), 8) :: Nil

    /// Z held for n frames — each landed reverse slide chains the next
    /// rewind, so one long hold walks the history back move by move.
    pub def rewind(frames: Int32): Replay.Cue[Sokoban.Input] =
        hold({ undo = true | idle() }, frames)

    /// The shipped solution of level 1, as data: seven moves. The two
    /// pushes are the third move (lower crate to its goal) and the last
    /// (upper crate home — CLEAR).
    pub def solveLevelOne(): List[Replay.Cue[Sokoban.Input]] =
        List.flatMap(walk,
            Dir4.Left :: Dir4.Up :: Dir4.Right ::
            Dir4.Up :: Dir4.Right :: Dir4.Up ::
            Dir4.Left :: Nil)

    /// The shipped solution of level 2, as data: twenty-one moves. The
    /// interior walls force the detours — push the lower crate left, walk
    /// the top corridor around to above it, push it down onto (1,5), walk
    /// the corridor back, and push the upper crate right onto (6,2): CLEAR.
    pub def solveLevelTwo(): List[Replay.Cue[Sokoban.Input]] =
        List.flatMap(walk,
            Dir4.Up :: Dir4.Left ::
            Dir4.Right :: Dir4.Up :: Dir4.Right ::
            Dir4.Up :: Dir4.Up ::
            Dir4.Left :: Dir4.Left :: Dir4.Left ::
            Dir4.Down :: Dir4.Down :: Dir4.Down ::
            Dir4.Up :: Dir4.Up :: Dir4.Up ::
            Dir4.Right :: Dir4.Right :: Dir4.Right ::
            Dir4.Down :: Dir4.Right :: Nil)
}
