// Sokoban — a World that holds the state, a pure step that advances it, and a frame
// that projects it into the list of things to draw.
// The launcher repeats read input |> tick |> frame until the window closes.
//
// The World holds a whole board. Walls, goals and crates are Stores: one World
// field each, holding a Set of grid positions. The rules live on the grid; the
// picture slides between cells, and the slide's progress is state like
// everything else.
//
// The session's history is a Worldline (engine_world's zipper of Worlds): every
// committed move records the pre-move World, and Z rewinds to it. The Worldline
// itself lives in the loop, outside the World — the time machine is not inside
// time.

mod Sokoban {

    // Colors come only from Palette (DB32) role names. No color literals in drawing code.

    // Design resolution 320x240; the board is centered slightly below the middle
    // to clear the title line.
    def centerX(): Float64 = 160.0
    def boardCenterY(): Float64 = 132.0

    // One board cell on screen, in design px.
    def tile(): Float64 = 24.0

    def zBadge(): Int32 = 10
    def zTitle(): Int32 = 100

    // ── Input: this frame's keys as plain data ──
    // The keyboard lives outside the World. Every frame the loop reads it once and
    // hands step the result as a value — so step can stay pure. enter is an
    // edge, not a level: true only on the frame the key went down, so one
    // press turns exactly one page. The loop tells held from pressed; the
    // pure world only ever sees the verdict.
    pub type alias Input = { up = Bool, down = Bool, left = Bool, right = Bool,
                             undo = Bool, enter = Bool, back = Bool, esc = Bool }

    // ── World: where the state lives ──
    // walls / goals / crates are Stores: many things of one kind, one Set each.
    // slide is the picture's state: when a hop (or a rewind) commits, the
    // robot's cell changes at once — the drawn position then travels from the
    // old cell for a fraction of a second, and how far it has come (t) must
    // survive between frames, so it lives in the World like everything else.
    // reverse marks a rewind slide: same mechanism, film played backwards.
    pub type alias Slide = { fromCell = (Int32, Int32), pushing = Bool, reverse = Bool, t = Float64 }

    /// The rewind clock over the robot's head: spin counts rewound moves (the
    /// needle turns once counterclockwise per move, in step with the reverse
    /// slide), linger is the time since rewinding stopped — the clock fades
    /// out shortly after.
    pub type alias UndoFx = { spin = Float64, linger = Float64 }

    // ── Screen: which page of the game the frame shows ──
    // The screen is state like everything else, so it lives in the World and
    // the pure tick owns every transition: Title --Enter--> level 1,
    // CLEAR --Enter--> the next level (or back to Title after the last one),
    // X abandons a level. Each transition starts a fresh Worldline — history
    // belongs to one attempt at one board.
    pub enum Screen with Eq {
        case Title
        case Playing
    }

    pub type alias Board = {
        walls = Set[(Int32, Int32)],
        goals = Set[(Int32, Int32)],
        crates = Set[(Int32, Int32)],
        robot = (Int32, Int32),
        cols = Int32,
        rows = Int32,
        facing = Robot.Direction,
        walkPhase = Float64,
        slide = Option[Slide],
        undoFx = Option[UndoFx],
        screen = Screen,
        level = Int32,
        clearElapsed = Float64
    }

    pub enum World {
        case World(Board)
    }

    pub def initialWorld(): World = titleWorld()

    pub def levelCount(): Int32 = 2

    def levelText(n: Int32): String =
        if (n <= 1) Level.one() else Level.two()

    /// The title page. It still carries a (level 1) board — every World has
    /// one — but the frame never draws it there.
    pub def titleWorld(): World = fromLevel(Screen.Title, 1)

    /// A fresh attempt at level n, ready to play.
    pub def playingWorld(n: Int32): World = fromLevel(Screen.Playing, n)

    /// The shipped level strings are pinned parseable by the tests; a broken
    /// string degrades to a bare floor instead of crashing the launcher.
    def fromLevel(screen: Screen, n: Int32): World =
        match Level.parse(levelText(n)) {
            case Result.Ok(p)  => toWorld(screen, n, p)
            case Result.Err(_) => toWorld(screen, n,
                                          { walls = Set.empty(), goals = Set.empty(),
                                            crates = Set.empty(), robot = (0, 0),
                                            cols = 1, rows = 1 })
        }

    def toWorld(screen: Screen, n: Int32, p: Level.Parsed): World =
        World.World({ walls = p#walls, goals = p#goals, crates = p#crates,
                      robot = p#robot, cols = p#cols, rows = p#rows,
                      facing = Robot.Direction.Down, walkPhase = 0.0,
                      slide = None, undoFx = None,
                      screen = screen, level = n, clearElapsed = 0.0 })

    /// The win condition is not stored anywhere: it is derived from the Stores.
    /// A board with no crates poses no puzzle, so it never counts as solved.
    pub def won(w: World): Bool =
        let World.World(b) = w;
        not Set.isEmpty(b#crates) and Set.isSubsetOf(b#crates, b#goals)

    // ── tick: one frame of the whole session, time machine included ──
    // The Worldline records one snapshot per committed move — the game's natural
    // beat — never per frame. Z rewinds move by move; each rewind plays the
    // move's slide backwards, and the next command (walk or rewind alike) is
    // accepted only when the picture lands: one gate for both directions of time.

    /// Snapshots to keep. At the engine benchmark's ~172 bytes per record this
    /// is under 2 MB: unlimited undo is, in effect, free.
    pub def historyCap(): Int32 = 10000

    pub def tick(input: Input, dt: Float64, line: Worldline[World]): Worldline[World] =
        let World.World(b) = Worldline.current(line);
        match b#screen {
            case Screen.Title =>
                if (input#enter) freshLine(playingWorld(1)) else line
            case Screen.Playing =>
                let world = Worldline.current(line);
                if (won(world))
                    // CLEAR is modal: only Enter and Escape are heard. The
                    // picture still breathes — the winning slide lands, the
                    // clock fades — but walking and rewinding fall silent.
                    if (input#enter)
                        (if (b#level < levelCount()) freshLine(playingWorld(b#level + 1))
                         else freshLine(titleWorld()))
                    else if (input#esc)
                        freshLine(titleWorld())
                    else {
                        // The party clock: confetti is a pure function of
                        // how long the board has been solved.
                        let World.World(b1) = step(noKeys(), dt, world);
                        Worldline.replaceCurrent(
                            World.World({ clearElapsed = b1#clearElapsed + dt | b1 }), line)
                    }
                else if (input#back)
                    freshLine(titleWorld())
                else
                    playTick(input, dt, line)
        }

    /// A brand new Worldline around one World: how every screen transition
    /// begins. The previous history is dropped with the previous screen.
    def freshLine(w: World): Worldline[World] =
        Worldline.make(w, historyCap())

    /// One frame of actual play: motion, moves committing to history, Z
    /// rewinding through it.
    def playTick(input: Input, dt: Float64, line: Worldline[World]): Worldline[World] =
        let world = Worldline.current(line);
        // Holding Z takes the walk keys away; rewinding has right of way.
        let moveInput = if (input#undo) noKeys() else input;
        let next = step(moveInput, dt, world);
        if (hopStarted(world, next))
            // A move committed: file the pre-move World in the past.
            Worldline.record(next, Worldline.replaceCurrent(normalize(world), line))
        else if (input#undo and not inFlight(next))
            // The gate is open (nothing sliding) and Z is down: rewind one move.
            fireUndo(Worldline.replaceCurrent(next, line))
        else
            // Just motion; adjust the current point in place, no history made.
            Worldline.replaceCurrent(next, line)

    /// Rewind one move: the Stores return to the snapshot at once, and a
    /// reverse slide carries the picture back — the robot glides backwards
    /// wearing the undone move's facing, feet dragging, while the clock
    /// turns; the snapshot's own facing waits at the landing.
    def fireUndo(line: Worldline[World]): Worldline[World] =
        if (not Worldline.canUndo(line)) line
        else {
            let World.World(l) = Worldline.current(line);
            let line1 = Worldline.undo(line);
            let World.World(r) = Worldline.current(line1);
            let back = World.World({
                slide = Some({ fromCell = l#robot, pushing = l#crates != r#crates,
                               reverse = true, t = 0.0 }),
                walkPhase = l#walkPhase,
                undoFx = Some({ spin = spinOf(l#undoFx), linger = 0.0 })
                | r });
            Worldline.replaceCurrent(back, line1)
        }

    /// A hop committed exactly when the robot's cell changed (every legal move
    /// moves the robot; a blocked one moves nothing).
    def hopStarted(before: World, after: World): Bool =
        let World.World(a) = before;
        let World.World(z) = after;
        a#robot != z#robot

    def inFlight(w: World): Bool =
        let World.World(b) = w;
        not Option.isEmpty(b#slide)

    def noKeys(): Input =
        { up = false, down = false, left = false, right = false,
          undo = false, enter = false, back = false, esc = false }

    /// What goes into history: the logical state. The picture's travel and the
    /// rewind clock stay out of the past.
    def normalize(w: World): World =
        let World.World(b) = w;
        World.World({ slide = None, undoFx = None | b })

    def spinOf(fx: Option[UndoFx]): Float64 =
        match fx {
            case Some(f) => f#spin
            case None    => 0.0
        }

    /// Seconds the clock outlives its last rewind before fading away.
    def fxLinger(): Float64 = 0.4

    /// The clock's aging. While a reverse slide runs, the needle turns with it
    /// (spinAdvance = the slide's progress this frame) and the clock stays
    /// fresh; otherwise it just gets older until it fades.
    def tickFx(dt: Float64, spinAdvance: Float64, b: Board): Board =
        match b#undoFx {
            case None    => b
            case Some(f) =>
                if (spinAdvance > 0.0)
                    { undoFx = Some({ spin = f#spin + spinAdvance, linger = 0.0 }) | b }
                else if (f#linger + dt > fxLinger())
                    { undoFx = None | b }
                else
                    { undoFx = Some({ spin = f#spin, linger = f#linger + dt }) | b }
        }

    /// Needle angle in radians for a given spin — a pure derivation: one full
    /// counterclockwise turn per move rewound.
    pub def needleAngle(spin: Float64): Float64 =
        spin * 6.283185307179586


    // ── step: advances the world by dt seconds ──
    // Still pure: the keys arrive as an argument, and so does the clock — dt is
    // this frame's elapsed seconds, read by the loop and handed in as a value.
    // While a slide is travelling the keys are ignored; the moment it lands, a
    // key still held starts the next square — taps move exactly one cell, holds
    // glide cell by cell in rhythm, at the same speed on any display.

    /// Seconds one tile's slide takes: the single knob for movement speed.
    def slideDuration(): Float64 = 0.125

    /// Seconds one rewound move's reverse slide takes — twice the walking
    /// slide: rewinding should feel heavier, and the clock deserves the time.
    def undoDuration(): Float64 = 0.25

    /// The walk cycle advances one beat (0.25 of the cycle) per tile slid.
    def strideBeat(): Float64 = 0.25

    /// Walk cycles per second while standing: a slow march in place — about a
    /// third of the walking rate, alive rather than busy.
    def idleBeat(): Float64 = 0.75

    pub def step(input: Input, dt: Float64, w: World): World =
        let World.World(b0) = w;
        match b0#slide {
            case Some(s) =>
                // A rewind slide runs on its own, slower clock; the needle
                // turns exactly as far as the picture travels.
                let dur = if (s#reverse) undoDuration() else slideDuration();
                let progress = dt / dur;
                let b = tickFx(dt, if (s#reverse) progress else 0.0, b0);
                let t = s#t + progress;
                let walked = { walkPhase = fract(b#walkPhase + strideBeat() * progress) | b };
                if (t < 1.0)
                    World.World({ slide = Some({ t = t | s }) | walked })
                else
                    // The slide has landed: only now does the keyboard get a say.
                    World.World(beginHop(input, { slide = None | walked }))
            case None =>
                // A standing robot marches slowly in place; a starting hop
                // carries the phase along, so the legs never snap.
                let b = tickFx(dt, 0.0, b0);
                let marched = { walkPhase = fract(b#walkPhase + idleBeat() * dt) | b };
                World.World(beginHop(input, marched))
        }

    /// Start a hop if a direction key is down, else keep standing.
    def beginHop(input: Input, b: Board): Board =
        match pick(input#up, input#down, input#left, input#right) {
            case None    => b
            case Some(d) => move(d, b)
        }

    /// The whole rulebook of sokoban. The target cell decides: a wall stops the
    /// robot; a crate moves along only if the cell behind it is free; otherwise
    /// nothing moves and the robot just turns. A legal hop changes the cells at
    /// once and starts the slide that lets the picture catch up.
    def move(d: Robot.Direction, b: Board): Board =
        let (dx, dy) = deltaOf(d);
        let (rx, ry) = b#robot;
        let target = (rx + dx, ry + dy);
        let (tx, ty) = target;
        let beyond = (tx + dx, ty + dy);
        let pushing = Set.memberOf(target, b#crates);
        let blocked = Set.memberOf(target, b#walls)
            or (pushing and (Set.memberOf(beyond, b#walls) or Set.memberOf(beyond, b#crates)));
        if (blocked)
            { facing = d | b }
        else
            { robot = target,
              crates = if (pushing) Set.insert(beyond, Set.remove(target, b#crates)) else b#crates,
              facing = d,
              slide = Some({ fromCell = b#robot, pushing = pushing, reverse = false, t = 0.0 })
              | b }

    /// Among several held keys: up, then down, then left, then right.
    def pick(u: Bool, d: Bool, l: Bool, r: Bool): Option[Robot.Direction] =
        if (u) Some(Robot.Direction.Up)
        else if (d) Some(Robot.Direction.Down)
        else if (l) Some(Robot.Direction.Left)
        else if (r) Some(Robot.Direction.Right)
        else None

    def deltaOf(d: Robot.Direction): (Int32, Int32) = match d {
        case Robot.Direction.Up    => (0, -1)
        case Robot.Direction.Down  => (0, 1)
        case Robot.Direction.Left  => (-1, 0)
        case Robot.Direction.Right => (1, 0)
    }

    /// Keep only the fractional part (the walk cycle repeats on 0..1).
    def fract(x: Float64): Float64 = x - Float64.floor(x)

    // ── frame: projects the World into the list of things to draw ──
    // Insertion order layers the board: floor and walls, then goal marks, then
    // crates, then the robot, then the on-goal badges and text on top.
    // The Title page draws nothing here: everything on it is Spec (see the UI
    // section below), rendered from the UI store by the loop.
    pub def frame(atlas: FontAtlas, w: World): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let World.World(b) = w;
        if (b#screen == Screen.Title) (Nil, Nil)
        else {
            let boxes = List.flatten(
                boardTiles(b) ::
                goalMarks(b) ::
                crateBoxes(b) ::
                Robot.parts(robotDrawCenter(b), tile(), drawnFacing(b), b#walkPhase) ::
                onGoalBadges(b) ::
                clockBoxes(b) ::
                texts(atlas) :: Nil);
            (Render.draw(boxes),
             List.flatten(cratePolys(b) :: clockNeedle(b) :: confettiQuads(b) :: Nil))
        }

    /// Top-left corner of the board, chosen so the whole grid sits centered.
    def origin(b: Board): Vec2.Vec2 =
        { x = centerX() - Int32.toFloat64(b#cols) * tile() / 2.0,
          y = boardCenterY() - Int32.toFloat64(b#rows) * tile() / 2.0 }

    def cellCenter(b: Board, p: (Int32, Int32)): Vec2.Vec2 =
        let o = origin(b);
        let (x, y) = p;
        { x = o#x + (Int32.toFloat64(x) + 0.5) * tile(),
          y = o#y + (Int32.toFloat64(y) + 0.5) * tile() }

    /// Where the robot is drawn: its cell — or partway out of the previous one.
    def robotCenter(b: Board): Vec2.Vec2 =
        match b#slide {
            case None    => cellCenter(b, b#robot)
            case Some(s) => lerp(cellCenter(b, s#fromCell), cellCenter(b, b#robot), s#t)
        }

    /// The robot leans into its work: while a forward push slides, the whole
    /// picture sits one pixel lower — weight on the crate, nothing more.
    def robotDrawCenter(b: Board): Vec2.Vec2 =
        let c = robotCenter(b);
        { x = c#x, y = c#y + pushSink(b) }

    def pushSink(b: Board): Float64 =
        match b#slide {
            case Some(s) => if (s#pushing and not s#reverse) 1.0 else 0.0
            case None    => 0.0
        }

    /// The facing the picture wears. A rewind slide shows the direction of
    /// the undone move — that move went from the restored cell out to
    /// fromCell, so that line names it — and only when the slide lands does
    /// the snapshot's own facing (already in the Board) take over.
    pub def drawnFacing(b: Board): Robot.Direction =
        match b#slide {
            case Some(s) => if (s#reverse) directionTo(b#robot, s#fromCell) else b#facing
            case None    => b#facing
        }

    /// The unit direction that leads a to z (one cell apart on the grid).
    def directionTo(a: (Int32, Int32), z: (Int32, Int32)): Robot.Direction =
        let (ax, ay) = a;
        let (zx, zy) = z;
        if (zy < ay) Robot.Direction.Up
        else if (zy > ay) Robot.Direction.Down
        else if (zx < ax) Robot.Direction.Left
        else Robot.Direction.Right

    /// While a push is sliding forward, the pushed crate sits one cell past
    /// the robot's destination, along the direction the robot came from.
    def slidingCrate(b: Board, s: Slide): (Int32, Int32) =
        let (fx, fy) = s#fromCell;
        let (rx, ry) = b#robot;
        (2 * rx - fx, 2 * ry - fy)

    /// While a push is rewinding, the returning crate now rests where the
    /// robot stood after the push (s#fromCell) — and its picture travels home
    /// from one cell further out.
    def crateReturnStart(b: Board, s: Slide): (Int32, Int32) =
        let (fx, fy) = s#fromCell;
        let (rx, ry) = b#robot;
        (2 * fx - rx, 2 * fy - ry)

    /// Where a crate is drawn: its cell — unless it is the one being pushed
    /// (or un-pushed), which travels in lockstep with the robot, forward or
    /// backward: the same slide, film reversed.
    def crateCenter(b: Board, p: (Int32, Int32)): Vec2.Vec2 =
        match b#slide {
            case Some(s) =>
                if (s#pushing and not s#reverse and p == slidingCrate(b, s))
                    lerp(cellCenter(b, b#robot), cellCenter(b, p), settle(s#t))
                else if (s#pushing and s#reverse and p == s#fromCell)
                    lerp(cellCenter(b, crateReturnStart(b, s)), cellCenter(b, p), s#t)
                else cellCenter(b, p)
            case None => cellCenter(b, p)
        }

    /// The pushed crate's travel. It rides the robot's linear slide (a
    /// pushed thing cannot outrun its pusher), then over the last stretch
    /// pops about a pixel past the target and settles exactly as it lands.
    pub def settle(t: Float64): Float64 =
        if (t < 0.8) t
        else t + 0.06 * RenderUtil.sinF(3.141592653589793 * (t - 0.8) / 0.2)

    def lerp(a: Vec2.Vec2, z: Vec2.Vec2, t: Float64): Vec2.Vec2 =
        { x = a#x + (z#x - a#x) * t, y = a#y + (z#y - a#y) * t }

    def cells(b: Board): List[(Int32, Int32)] =
        List.flatMap(y -> List.map(x -> (x, y), List.range(0, b#cols)), List.range(0, b#rows))

    def boardTiles(b: Board): List[(Vec2.Vec2, Render.RenderItem)] =
        List.flatMap(p ->
            if (Set.memberOf(p, b#walls)) wallTile(cellCenter(b, p))
            else floorTile(cellCenter(b, p)),
            cells(b))

    /// Floor: one flat box per cell; the board reads as a lit area on the dark
    /// clear color around it.
    def floorTile(c: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        boxAt(c#x - tile() / 2.0, c#y - tile() / 2.0, tile(), tile(), Palette.floorTile(), 0) :: Nil

    /// Wall: a stone block — flat face with a lit top edge and a shaded foot.
    def wallTile(c: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        let t = tile();
        let x0 = c#x - t / 2.0;
        let y0 = c#y - t / 2.0;
        let bevel = t * 0.16;
        boxAt(x0, y0, t, t, Palette.wallFace(), 0) ::
        boxAt(x0, y0, t, bevel, Palette.wallTop(), 1) ::
        boxAt(x0, y0 + t - bevel, t, bevel, Palette.wallShade(), 1) :: Nil

    /// Goal: a small round marker on the floor (crates and the robot draw over it).
    def goalMarks(b: Board): List[(Vec2.Vec2, Render.RenderItem)] =
        List.map(p -> circleAt(cellCenter(b, p), tile() * 0.34, Palette.goalMark(), 0),
                 Set.toList(b#goals))

    /// A crate parked on (or sliding onto) a goal gets a small badge on top:
    /// the goal answers back.
    def onGoalBadges(b: Board): List[(Vec2.Vec2, Render.RenderItem)] =
        List.map(p -> circleAt(crateCenter(b, p), tile() * 0.25, Palette.goalMark(), zBadge()),
                 Set.toList(Set.intersection(b#crates, b#goals)))

    def crateBoxes(b: Board): List[(Vec2.Vec2, Render.RenderItem)] =
        List.flatMap(p -> Crate.boxes(crateCenter(b, p), tile()), Set.toList(b#crates))

    def cratePolys(b: Board): List[GameEngine.PolygonRenderCmd] =
        List.flatMap(p -> Crate.polys(crateCenter(b, p), tile()), Set.toList(b#crates))

    def boxAt(x: Float64, y: Float64, w: Float64, h: Float64,
              c: Color, z: Int32): (Vec2.Vec2, Render.RenderItem) =
        ({x = x, y = y}, Render.solidBox({x = w, y = h}, c, z))

    def circleAt(c: Vec2.Vec2, d: Float64, color: Color, z: Int32): (Vec2.Vec2, Render.RenderItem) =
        let style = { cornerRadius = d / 2.0, borderWidth = 0.0, borderColor = color,
                      borderAlpha = 0.0f32, stripeColor = color, stripeAlpha = 0.0f32,
                      stripeWidth = 0.0, stripePeriod = 0.0 };
        ({x = c#x - d / 2.0, y = c#y - d / 2.0},
         Render.RenderItem.Box({ size = {x = d, y = d}, color = color, alpha = 1.0f32,
                                 style = Some(style), zIndex = z }))

    // ── The rewind clock: an alarm clock over the robot's head ──
    // Everything about it is derived: position follows the robot (jumps
    // included), the needle angle comes from spin, and the whole thing fades
    // with linger. It never touches the rules and is never recorded.

    def zClock(): Int32 = 50

    def clockCenter(b: Board): Vec2.Vec2 =
        let r = robotCenter(b);
        { x = r#x, y = r#y - tile() * 0.95 }

    def clockAlpha(f: UndoFx): Float32 =
        RenderUtil.f32(1.0 - f#linger / fxLinger())

    /// Dial: a dark outer circle (the rim), a white inner circle (the face),
    /// and a small square alarm button on top.
    def clockBoxes(b: Board): List[(Vec2.Vec2, Render.RenderItem)] =
        match b#undoFx {
            case None    => Nil
            case Some(f) =>
                let c = clockCenter(b);
                let d = tile() * 0.8;
                let a = clockAlpha(f);
                fxBox({x = c#x - d * 0.1, y = c#y - d / 2.0 - d * 0.12}, {x = d * 0.2, y = d * 0.14},
                      Palette.clockRim(), a, zClock()) ::
                fxCircle(c, d, Palette.clockRim(), a, zClock()) ::
                fxCircle(c, d - 3.0, Palette.clockFace(), a, zClock() + 1) :: Nil
        }

    /// The needle: a thin quad from just behind the center to the face's edge,
    /// pointing along the (counterclockwise-spinning) needle angle.
    def clockNeedle(b: Board): List[GameEngine.PolygonRenderCmd] =
        match b#undoFx {
            case None    => Nil
            case Some(f) =>
                let c = clockCenter(b);
                let a = needleAngle(f#spin);
                // 12 o'clock spun counterclockwise on screen (y points down).
                let dir = {x = -RenderUtil.sinF(a), y = -RenderUtil.cosF(a)};
                let n = {x = -dir#y, y = dir#x};
                let reach = (tile() * 0.8 - 3.0) / 2.0 - 1.2;
                let halfW = 0.7;
                let p0 = Vec2.sub(c, Vec2.mul(dir, 1.5));
                let p1 = Vec2.add(c, Vec2.mul(dir, reach));
                { vertices = Vec2.add(p0, Vec2.mul(n, -halfW)) :: Vec2.add(p1, Vec2.mul(n, -halfW)) ::
                             Vec2.add(p1, Vec2.mul(n, halfW)) :: Vec2.add(p0, Vec2.mul(n, halfW)) :: Nil,
                  color = Palette.clockRim(), alpha = clockAlpha(f), zIndex = zClock() + 2 } :: Nil
        }

    def fxBox(pos: Vec2.Vec2, size: Vec2.Vec2, c: Color, a: Float32,
              z: Int32): (Vec2.Vec2, Render.RenderItem) =
        (pos, Render.RenderItem.Box({ size = size, color = c, alpha = a,
                                      style = None, zIndex = z }))

    def fxCircle(center: Vec2.Vec2, d: Float64, c: Color, a: Float32,
                 z: Int32): (Vec2.Vec2, Render.RenderItem) =
        let style = { cornerRadius = d / 2.0, borderWidth = 0.0, borderColor = c,
                      borderAlpha = 0.0f32, stripeColor = c, stripeAlpha = 0.0f32,
                      stripeWidth = 0.0, stripePeriod = 0.0 };
        ({x = center#x - d / 2.0, y = center#y - d / 2.0},
         Render.RenderItem.Box({ size = {x = d, y = d}, color = c, alpha = a,
                                 style = Some(style), zIndex = z }))

    // ── Confetti: rain without a particle system ──
    // No particle is stored anywhere. Each piece's position, spin and color
    // are a pure function of (its index, the seconds since the board was
    // solved): the whole rain is a derivation from one number in the World,
    // clearElapsed. There is nothing to spawn, update or free — leaving the
    // screen simply stops asking for the picture.

    def confettiCount(): Int32 = 48

    def zConfetti(): Int32 = 95

    /// A cheap integer hash onto [0, 1): piece i's k-th personal constant.
    /// The same piece always gets the same answers, so it always flutters
    /// the same way — determinism all the way down to the party.
    def chip(i: Int32, k: Int32): Float64 =
        let h = i * 374761393 + k * 668265263 + 1442695041;
        Int32.toFloat64(Int32.modulo(h * (h + 30011), 100003)) / 100003.0

    /// Where piece i hangs t seconds into the party: it falls at its own
    /// speed, sways on its own sine, spins at its own rate, and wraps back
    /// above the screen so the rain never runs out.
    def confettiQuad(t: Float64, i: Int32): GameEngine.PolygonRenderCmd =
        let speed = 55.0 + 50.0 * chip(i, 1);
        let sway = 6.0 + 10.0 * chip(i, 2);
        let phase = 6.283185307179586 * chip(i, 3);
        let spin = (2.0 + 4.0 * chip(i, 4)) * (if (chip(i, 5) < 0.5) -1.0 else 1.0);
        let x = 320.0 * chip(i, 6) + sway * RenderUtil.sinF(1.5 * t + phase);
        let y = fract((speed * t + 260.0 * chip(i, 7)) / 260.0) * 260.0 - 10.0;
        let a = spin * t + phase;
        let u = { x = RenderUtil.cosF(a), y = RenderUtil.sinF(a) };
        let v = { x = -u#y, y = u#x };
        let c = { x = x, y = y };
        let corner = (sx, sy) -> Vec2.add(c, Vec2.add(Vec2.mul(u, sx * 2.2), Vec2.mul(v, sy * 1.4)));
        { vertices = corner(-1.0, -1.0) :: corner(1.0, -1.0) ::
                     corner(1.0, 1.0) :: corner(-1.0, 1.0) :: Nil,
          color = Palette.confetti(i), alpha = 1.0f32, zIndex = zConfetti() }

    /// The whole rain: one quad per index while the party clock runs.
    pub def confettiQuads(b: Board): List[GameEngine.PolygonRenderCmd] =
        if (b#clearElapsed <= 0.0) Nil
        else List.map(confettiQuad(b#clearElapsed), List.range(0, confettiCount()))

    /// The in-game header. The CLEAR panel that used to be drawn here is a
    /// Spec now (assets/Clear.ui.json); the board keeps only its title line.
    def texts(atlas: FontAtlas): List[(Vec2.Vec2, Render.RenderItem)] =
        centeredText("Sokoban", atlas, 28.0, Palette.titleText(), 10.0) :: Nil

    def centeredText(text: String, atlas: FontAtlas, size: Float64,
                     color: Color, y: Float64): (Vec2.Vec2, Render.RenderItem) =
        let width = Label2D.measure(Label2D.make(text, atlas, size))#x;
        ({x = centerX() - width / 2.0, y = y}, Render.textTinted(text, atlas, size, color, zTitle()))

    // ── UI: the Title and Clear pages are Specs ──
    // Their whole look lives in assets/*.ui.json — data, not code. At startup
    // both files are spawned into one UiWorld (engine_world's UI store), a
    // plain value that lives in the loop next to the Worldline. Every frame a
    // projection stamps the World's verdicts onto it — which page shows, how
    // many moves the clear took — and UiRender turns it into boxes and glyphs.

    pub def titleUiPath(): String = "assets/Title.ui.json"
    pub def clearUiPath(): String = "assets/Clear.ui.json"

    def designSize(): Vec2.Vec2 = { x = 320.0, y = 240.0 }

    /// Spawn both page Specs into one UiWorld. A broken or missing file
    /// degrades to no page — the game still runs, like a broken level string.
    def loadUi(): UiStore.UiWorld \ Fs.FileRead =
        UiStore.empty() |> spawnPage(titleUiPath()) |> spawnPage(clearUiPath())

    def spawnPage(path: String, ui: UiStore.UiWorld): UiStore.UiWorld \ Fs.FileRead =
        match UiSpec.spawnAsset(path, ui) {
            case Result.Ok((_, ui1)) => ui1
            case Result.Err(_)       => ui
        }

    /// Stamp the World onto the UI store: page visibility and the move count.
    /// The count is nobody's counter — it is Worldline.pastLength, handed in
    /// by the loop: the history was already counting the moves.
    pub def projectUi(moves: Int32, w: World, ui: UiStore.UiWorld): UiStore.UiWorld =
        let World.World(b) = w;
        ui |> UiStore.setVisible("Title", b#screen == Screen.Title)
           |> UiStore.setVisible("Clear", b#screen == Screen.Playing and won(w))
           |> UiStore.setText("Clear/panel/moves", "Moves: ${moves}")

    // ── Sound: a projection for the ear ──
    // The four wav files are generated assets (test/SfxBake.flix writes
    // them); which one to play is pure — a derivation over this frame's
    // step, read off the two Worldlines like everything else. Only the
    // playing itself is an effect, and it lives in the loop with the other
    // boundary crossings: keys in, pixels and sound out.

    /// What this frame sounds like: the winning push is a fanfare, a rewind
    /// ticks, a committed move thuds if it pushed and blips if it walked.
    /// Guarded to one page of one level, so screen changes stay silent.
    pub def sfxEvent(before: Worldline[World], after: Worldline[World]): Option[String] =
        let wb = Worldline.current(before);
        let wa = Worldline.current(after);
        let World.World(b) = wb;
        let World.World(a) = wa;
        let samePage = b#screen == Screen.Playing and a#screen == Screen.Playing
            and b#level == a#level;
        if (not samePage) None
        else if (won(wa) and not won(wb)) Some("clear")
        else if (Worldline.pastLength(after) == Worldline.pastLength(before) - 1) Some("undo")
        else if (Worldline.pastLength(after) == Worldline.pastLength(before) + 1)
            (if (a#crates != b#crates) Some("push") else Some("move"))
        else None

    // ── Launcher: read input and the clock |> tick |> frame, until the window closes ──
    pub def start(atlas: FontAtlas): Unit \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead} =
        loop(atlas, loadUi(), Worldline.make(initialWorld(), historyCap()),
             { enter = true, esc = true, f1 = false })

    /// Reading the keyboard touches something outside the program, and the
    /// signature says so: `\ GameEngine.Game`. This is the only place the keys
    /// are read; past this point they are just a value. The Enter and Escape
    /// edges are computed by the loop (it holds last frame's state) and
    /// arrive here as verdicts.
    def readInput(enterEdge: Bool, escEdge: Bool): Input \ GameEngine.Game =
        { up    = GameEngine.Game.isKeyPressed(GameEngine.Key.Up),
          down  = GameEngine.Game.isKeyPressed(GameEngine.Key.Down),
          left  = GameEngine.Game.isKeyPressed(GameEngine.Key.Left),
          right = GameEngine.Game.isKeyPressed(GameEngine.Key.Right),
          undo  = GameEngine.Game.isKeyPressed(GameEngine.Key.Z),
          enter = enterEdge,
          back  = GameEngine.Game.isKeyPressed(GameEngine.Key.X),
          esc   = escEdge }

    /// The clock lives outside the World too. The engine clamps the value, so a
    /// long hiccup (or the first frame) never teleports the game forward.
    def readDt(): Float64 \ GameEngine.Game =
        Duration.toSeconds(GameEngine.Game.getDeltaTime())

    /// While the CLEAR panel is up, Escape closes the panel (back to the
    /// title) instead of the window.
    def clearModal(w: World): Bool =
        let World.World(b) = w;
        b#screen == Screen.Playing and won(w)

    /// The loop threads three values: the UI store, the Worldline, and last
    /// frame's key state (enter and esc start true so a key already held at
    /// launch says nothing until released once).
    def loop(atlas: FontAtlas, ui: UiStore.UiWorld, line: Worldline[World],
             prev: { enter = Bool, esc = Bool, f1 = Bool }): Unit \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead} =
        let escDown = GameEngine.Game.isKeyPressed(GameEngine.Key.Escape);
        let escEdge = escDown and not prev#esc;
        if (GameEngine.Game.shouldClose()
            or (escEdge and not clearModal(Worldline.current(line)))) ()
        else {
            let enterDown = GameEngine.Game.isKeyPressed(GameEngine.Key.Enter);
            let f1Down = GameEngine.Game.isKeyPressed(GameEngine.Key.F1);
            let line1 = tick(readInput(enterDown and not prev#enter, escEdge), readDt(), line);
            match sfxEvent(line, line1) {
                case Some(name) => GameEngine.Audio.playAudio(name)
                case None       => ()
            };
            // F1 re-reads every spawned Spec from disk: edit the json while
            // the game runs, press F1, and the page changes under you.
            let ui1 = if (f1Down and not prev#f1) UiSpec.reloadAll(ui) else ui;
            let world = Worldline.current(line1);
            let ui2 = projectUi(Worldline.pastLength(line1), world, ui1);
            let (drawables, polys) = frame(atlas, world);
            let out = UiRender.renderUi(ui2, designSize());
            GameEngine.Game.renderCommands(
                List.append(drawables, out#drawables), Nil,
                List.append(polys, out#polygons));
            loop(atlas, ui2, line1, { enter = enterDown, esc = escDown, f1 = f1Down })
        }
}
