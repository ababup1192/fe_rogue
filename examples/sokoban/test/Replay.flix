// Replay — a Trace is a list of inputs, and this module is its whole engine.
//
// A Cue holds one Input for a number of frames; a Trace is a list of Cues.
// Because tick is pure and the clock arrives as a value, driving a Trace is
// a fold: same list in, same Worldline out, every time, on every machine.
// That determinism is what lets one solution be three things at once — a
// unit test (pin the outcome), a film (render every frame), and a bug
// report (a failing Trace *is* the reproduction).
mod Replay {

    /// One beat of a Trace: hold this input for n frames.
    pub type alias Cue = { input = Sokoban.Input, frames = Int32 }

    /// The fixed clock every replay runs on: 1/64 s per frame — dyadic, so
    /// every slide t and walk phase in the pinned outcomes is exact.
    pub def dt(): Float64 = 1.0 / 64.0

    pub def idle(): Sokoban.Input =
        { up = false, down = false, left = false, right = false,
          undo = false, enter = false, back = false, esc = false }

    def dirInput(d: Robot.Direction): Sokoban.Input = match d {
        case Robot.Direction.Up    => { up = true | idle() }
        case Robot.Direction.Down  => { down = true | idle() }
        case Robot.Direction.Left  => { left = true | idle() }
        case Robot.Direction.Right => { right = true | idle() }
    }

    /// Hold one input for n frames.
    pub def hold(input: Sokoban.Input, frames: Int32): Cue =
        { input = input, frames = frames }

    /// One walked move: tap the key for a frame, then let the slide land
    /// (a slide is 0.125 s = 8 frames at this clock).
    pub def walk(d: Robot.Direction): List[Cue] =
        hold(dirInput(d), 1) :: hold(idle(), 8) :: Nil

    /// Z held for n frames — each landed reverse slide chains the next
    /// rewind, so one long hold walks the history back move by move.
    pub def rewind(frames: Int32): Cue =
        hold({ undo = true | idle() }, frames)

    /// The shipped solution of level 1, as data: seven moves. The two
    /// pushes are the third move (lower crate to its goal) and the last
    /// (upper crate home — CLEAR).
    pub def solveLevelOne(): List[Cue] =
        List.flatMap(walk,
            Robot.Direction.Left :: Robot.Direction.Up :: Robot.Direction.Right ::
            Robot.Direction.Up :: Robot.Direction.Right :: Robot.Direction.Up ::
            Robot.Direction.Left :: Nil)

    /// The shipped solution of level 2, as data: twenty-one moves. The
    /// interior walls force the detours — push the lower crate left, walk
    /// the top corridor around to above it, push it down onto (1,5), walk
    /// the corridor back, and push the upper crate right onto (6,2): CLEAR.
    pub def solveLevelTwo(): List[Cue] =
        List.flatMap(walk,
            Robot.Direction.Up :: Robot.Direction.Left ::
            Robot.Direction.Right :: Robot.Direction.Up :: Robot.Direction.Right ::
            Robot.Direction.Up :: Robot.Direction.Up ::
            Robot.Direction.Left :: Robot.Direction.Left :: Robot.Direction.Left ::
            Robot.Direction.Down :: Robot.Direction.Down :: Robot.Direction.Down ::
            Robot.Direction.Up :: Robot.Direction.Up :: Robot.Direction.Up ::
            Robot.Direction.Right :: Robot.Direction.Right :: Robot.Direction.Right ::
            Robot.Direction.Down :: Robot.Direction.Right :: Nil)

    /// Play a Trace to its end. (`run` is a Flix keyword, so the driver is
    /// named after what it does to the film.)
    pub def play(cues: List[Cue], line: Worldline[Sokoban.World]): Worldline[Sokoban.World] =
        List.foldLeft((l, cue) -> playCue(cue#frames, cue#input, l), line, cues)

    def playCue(n: Int32, input: Sokoban.Input, line: Worldline[Sokoban.World]): Worldline[Sokoban.World] =
        if (n <= 0) line
        else playCue(n - 1, input, Sokoban.tick(input, dt(), line))

    /// Every frame of a Trace, in order — the film the GIFs are cut from.
    pub def timeline(cues: List[Cue], line: Worldline[Sokoban.World]): List[Worldline[Sokoban.World]] =
        let (_, rev) = List.foldLeft((acc, cue) -> {
            let (l, filmed) = acc;
            cueFrames(cue#frames, cue#input, l, filmed)
        }, (line, Nil), cues);
        List.reverse(rev)

    def cueFrames(n: Int32, input: Sokoban.Input, line: Worldline[Sokoban.World],
                  filmed: List[Worldline[Sokoban.World]]):
            (Worldline[Sokoban.World], List[Worldline[Sokoban.World]]) =
        if (n <= 0) (line, filmed)
        else {
            let l1 = Sokoban.tick(input, dt(), line);
            cueFrames(n - 1, input, l1, l1 :: filmed)
        }
}
