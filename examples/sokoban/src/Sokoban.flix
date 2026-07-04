// Sokoban — a World that holds the state, a pure step that advances it, and a frame
// that projects it into the list of things to draw.
// The launcher repeats read input |> step |> frame until the window closes.
//
// The World now holds a whole board. Walls, goals and crates are Stores: one
// World field each, holding a Set of grid positions. The rules live on the
// grid; the picture slides between cells, and the slide's progress is state
// like everything else.

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
    // hands step the result as a value — so step can stay pure.
    pub type alias Input = { up = Bool, down = Bool, left = Bool, right = Bool }

    // ── World: where the state lives ──
    // walls / goals / crates are Stores: many things of one kind, one Set each.
    // slide is the picture's state: when a hop starts, the robot's cell changes
    // at once — the drawn position then travels from the old cell for a fraction
    // of a second, and how far it has come (t) must survive between frames, so
    // it lives in the World like everything else.
    pub type alias Slide = { fromCell = (Int32, Int32), pushing = Bool, t = Float64 }

    pub type alias Board = {
        walls = Set[(Int32, Int32)],
        goals = Set[(Int32, Int32)],
        crates = Set[(Int32, Int32)],
        robot = (Int32, Int32),
        cols = Int32,
        rows = Int32,
        facing = Robot.Direction,
        walkPhase = Float64,
        slide = Option[Slide]
    }

    pub enum World {
        case World(Board)
    }

    pub def initialWorld(): World = fromLevel(Level.one())

    /// The shipped level strings are pinned parseable by the tests; a broken
    /// string degrades to a bare floor instead of crashing the launcher.
    pub def fromLevel(text: String): World =
        match Level.parse(text) {
            case Result.Ok(p)  => toWorld(p)
            case Result.Err(_) => toWorld({ walls = Set.empty(), goals = Set.empty(),
                                            crates = Set.empty(), robot = (0, 0),
                                            cols = 1, rows = 1 })
        }

    def toWorld(p: Level.Parsed): World =
        World.World({ walls = p#walls, goals = p#goals, crates = p#crates,
                      robot = p#robot, cols = p#cols, rows = p#rows,
                      facing = Robot.Direction.Down, walkPhase = 0.0,
                      slide = None })

    /// The win condition is not stored anywhere: it is derived from the Stores.
    pub def won(w: World): Bool =
        let World.World(b) = w;
        Set.isSubsetOf(b#crates, b#goals)

    // ── step: advances the world by dt seconds ──
    // Still pure: the keys arrive as an argument, and so does the clock — dt is
    // this frame's elapsed seconds, read by the loop and handed in as a value.
    // While a slide is travelling the keys are ignored; the moment it lands, a
    // key still held starts the next square — taps move exactly one cell, holds
    // glide cell by cell in rhythm, at the same speed on any display.

    /// Seconds one tile's slide takes: the single knob for movement speed.
    def slideDuration(): Float64 = 0.125

    /// The walk cycle advances one beat (0.25 of the cycle) per tile slid.
    def strideBeat(): Float64 = 0.25

    /// Walk cycles per second while standing: a slow march in place — about a
    /// third of the walking rate, alive rather than busy.
    def idleBeat(): Float64 = 0.75

    pub def step(input: Input, dt: Float64, w: World): World =
        let World.World(b) = w;
        match b#slide {
            case Some(s) =>
                let t = s#t + dt / slideDuration();
                let walked = { walkPhase = fract(b#walkPhase + strideBeat() * (dt / slideDuration())) | b };
                if (t < 1.0)
                    World.World({ slide = Some({ t = t | s }) | walked })
                else
                    // The slide has landed: only now does the keyboard get a say.
                    World.World(beginHop(input, { slide = None | walked }))
            case None =>
                // A standing robot marches slowly in place; a starting hop
                // carries the phase along, so the legs never snap.
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
              slide = Some({ fromCell = b#robot, pushing = pushing, t = 0.0 })
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
    pub def frame(atlas: FontAtlas, w: World): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let World.World(b) = w;
        let boxes = List.flatten(
            boardTiles(b) ::
            goalMarks(b) ::
            crateBoxes(b) ::
            Robot.parts(robotCenter(b), tile(), b#facing, b#walkPhase) ::
            onGoalBadges(b) ::
            texts(atlas, w) :: Nil);
        (Render.draw(boxes), cratePolys(b))

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

    /// While a push is sliding, the pushed crate sits one cell past the robot's
    /// destination, along the same direction the robot came from.
    def slidingCrate(b: Board, s: Slide): (Int32, Int32) =
        let (fx, fy) = s#fromCell;
        let (rx, ry) = b#robot;
        (2 * rx - fx, 2 * ry - fy)

    /// Where a crate is drawn: its cell — unless it is the one being pushed,
    /// which travels in lockstep with the robot.
    def crateCenter(b: Board, p: (Int32, Int32)): Vec2.Vec2 =
        match b#slide {
            case Some(s) =>
                if (s#pushing and p == slidingCrate(b, s))
                    lerp(cellCenter(b, b#robot), cellCenter(b, p), s#t)
                else cellCenter(b, p)
            case None => cellCenter(b, p)
        }

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

    /// Title always; "CLEAR!" appears the moment every crate sits on a goal —
    /// not stored anywhere, just projected from the Stores.
    def texts(atlas: FontAtlas, w: World): List[(Vec2.Vec2, Render.RenderItem)] =
        let title = centeredText("Sokoban", atlas, 28.0, Palette.titleText(), 10.0);
        if (won(w)) title :: centeredText("CLEAR!", atlas, 36.0, Palette.clearText(), 104.0) :: Nil
        else title :: Nil

    def centeredText(text: String, atlas: FontAtlas, size: Float64,
                     color: Color, y: Float64): (Vec2.Vec2, Render.RenderItem) =
        let width = Label2D.measure(Label2D.make(text, atlas, size))#x;
        ({x = centerX() - width / 2.0, y = y}, Render.textTinted(text, atlas, size, color, zTitle()))

    // ── Launcher: read input and the clock |> step |> frame, until the window closes ──
    pub def start(atlas: FontAtlas): Unit \ GameEngine.Game =
        loop(atlas, initialWorld())

    /// Reading the keyboard touches something outside the program, and the
    /// signature says so: `\ GameEngine.Game`. This is the only place the keys
    /// are read; past this point they are just a value.
    def readInput(): Input \ GameEngine.Game =
        { up    = GameEngine.Game.isKeyPressed(GameEngine.Key.Up),
          down  = GameEngine.Game.isKeyPressed(GameEngine.Key.Down),
          left  = GameEngine.Game.isKeyPressed(GameEngine.Key.Left),
          right = GameEngine.Game.isKeyPressed(GameEngine.Key.Right) }

    /// The clock lives outside the World too. The engine clamps the value, so a
    /// long hiccup (or the first frame) never teleports the game forward.
    def readDt(): Float64 \ GameEngine.Game =
        Duration.toSeconds(GameEngine.Game.getDeltaTime())

    def loop(atlas: FontAtlas, world: World): Unit \ GameEngine.Game =
        if (GameEngine.Game.shouldClose() or GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let next = step(readInput(), readDt(), world);
            let (drawables, polys) = frame(atlas, next);
            GameEngine.Game.renderCommands(drawables, Nil, polys);
            loop(atlas, next)
        }
}
