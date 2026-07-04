// Sokoban — a World that holds the state, a pure step that advances it, and a frame
// that projects it into the list of things to draw.
// The launcher repeats read input |> step |> frame until the window closes.
//
// The robot uses no image: every pose comes out of Robot.parts as a list of boxes.

mod Sokoban {

    // Colors come only from Palette (DB32) role names. No color literals in drawing code.

    // Design resolution 320x240 and its center.
    def designW(): Float64 = 320.0
    def designH(): Float64 = 240.0
    def centerX(): Float64 = 160.0
    def centerY(): Float64 = 120.0

    // The robot is one 16px grid tile shown at 6x magnification: 96px square.
    def robotSize(): Float64 = 96.0

    def zTitle(): Int32 = 100

    // ── Input: this frame's keys as plain data ──
    // The keyboard lives outside the World. Every frame the loop reads it once and
    // hands step the result as a value — so step can stay pure.
    pub type alias Input = { up = Bool, down = Bool, left = Bool, right = Bool }

    // ── World: where the state lives ──
    // One value that holds everything that changes: where the robot is, which way
    // it faces, and where it is in its walk cycle.
    pub enum World {
        case World({ robotX = Float64, robotY = Float64,
                     facing = Robot.Direction, walkPhase = Float64 })
    }

    pub def initialWorld(): World =
        World.World({ robotX = centerX(), robotY = centerY(),
                      facing = Robot.Direction.Down, walkPhase = 0.0 })

    // ── step: advances the world by one frame ──
    // Still no effect annotation: the keys arrive as an argument, so the same
    // (Input, World) always steps to the same next World.

    // Design px per frame while a key is held.
    def robotSpeed(): Float64 = 1.5
    // Walk-cycle phase per moving frame: a full 4-beat cycle every 32 frames.
    def walkRate(): Float64 = 1.0 / 32.0

    pub def step(input: Input, w: World): World =
        let World.World(r) = w;
        let dx = axis(input#left, input#right);
        let dy = axis(input#up, input#down);
        if (dx == 0.0 and dy == 0.0)
            World.World({ walkPhase = 0.0 | r })    // no key: snap to the rest pose, keep the facing
        else
            World.World({
                robotX = clamp(robotSize() / 2.0, designW() - robotSize() / 2.0,
                               r#robotX + dx * robotSpeed()),
                robotY = clamp(robotSize() / 2.0, designH() - robotSize() / 2.0,
                               r#robotY + dy * robotSpeed()),
                facing = facingOf(dx, dy, r#facing),
                walkPhase = fract(r#walkPhase + walkRate())
            })

    /// -1.0, 0.0 or +1.0 from an opposing key pair (both held cancel out).
    def axis(negative: Bool, positive: Bool): Float64 =
        (if (positive) 1.0 else 0.0) - (if (negative) 1.0 else 0.0)

    /// Facing follows the movement; the horizontal wins a diagonal, and standing
    /// still keeps whatever facing the robot already had.
    def facingOf(dx: Float64, dy: Float64, current: Robot.Direction): Robot.Direction =
        if (dx > 0.0)      Robot.Direction.Right
        else if (dx < 0.0) Robot.Direction.Left
        else if (dy > 0.0) Robot.Direction.Down
        else if (dy < 0.0) Robot.Direction.Up
        else current

    def clamp(lo: Float64, hi: Float64, v: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))

    /// Keep only the fractional part (the walk cycle repeats on 0..1).
    def fract(x: Float64): Float64 = x - Float64.floor(x)

    // ── frame: projects the World into the list of things to draw ──
    // The same Robot.parts that baked the gallery draws the player: a character
    // with no image file, composed box by box at whatever size we ask for.
    pub def frame(atlas: FontAtlas, w: World): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let World.World(r) = w;
        let center = {x = r#robotX, y = r#robotY};
        let boxes = List.append(
            Robot.parts(center, robotSize(), r#facing, r#walkPhase),
            titlePlacement(atlas) :: Nil);
        (Render.draw(boxes), Nil)

    /// Title text horizontally centered near the top of the screen.
    def titlePlacement(atlas: FontAtlas): (Vec2.Vec2, Render.RenderItem) =
        let size = 28.0;
        let width = Label2D.measure(Label2D.make("Sokoban", atlas, size))#x;
        let pos = {x = centerX() - width / 2.0, y = 24.0};
        (pos, Render.textTinted("Sokoban", atlas, size, Palette.titleText(), zTitle()))

    // ── Launcher: read input |> step |> frame, every frame, until the window closes ──
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

    def loop(atlas: FontAtlas, world: World): Unit \ GameEngine.Game =
        if (GameEngine.Game.shouldClose() or GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let next = step(readInput(), world);
            let (drawables, polys) = frame(atlas, next);
            GameEngine.Game.renderCommands(drawables, Nil, polys);
            loop(atlas, next)
        }
}
