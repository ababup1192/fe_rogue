// Sokoban — a function that returns the list of things to draw (frame), and a launcher
// that draws it every frame (start).
//
// frame is a stateless pure function: given the font, it returns "what to draw this frame"
// (a list of rectangles and text, plus a list of polygons) — nothing more.
// start keeps feeding the result of frame to the engine until the window closes.
// The crate uses no image: it is a stack of boxes plus convex polygons for the diagonal brace.

mod Sokoban {

    // Colors come only from Palette (DB32) role names. No color literals in drawing code.

    // Center of the 320x240 design resolution.
    def centerX(): Float64 = 160.0
    def centerY(): Float64 = 120.0

    // The crate is one 16px grid tile shown at 6x magnification: 96px square.
    def crateSize(): Float64 = 96.0
    def crateLeft(): Float64 = centerX() - crateSize() / 2.0
    def crateTop(): Float64 = centerY() - crateSize() / 2.0

    // Thickness of the outer frame rails.
    def railW(): Float64 = crateSize() * 0.12

    // Drawing order (zIndex): base plank -> vertical seams -> diagonal brace -> frame rails
    // -> frame joints and outer outline. The rails draw after the brace, so the brace's
    // extended ends tuck underneath them.
    def zPlank(): Int32 = 0
    def zSeam(): Int32 = 1
    def zBraceEdge(): Int32 = 2
    def zBrace(): Int32 = 3
    def zRail(): Int32 = 4
    def zJoint(): Int32 = 5
    def zTitle(): Int32 = 100

    // ── The function that returns the list of things to draw ──
    pub def frame(atlas: FontAtlas): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let boxes = List.append(crateBoxes(), titlePlacement(atlas) :: Nil);
        (Render.draw(boxes), cratePolys())

    // ── The crate: a composition of boxes plus convex polygon strips ──

    /// Box parts: 1 base plank + 5 vertical seams + 4 frame rails + 4 frame joints + 4 outline edges.
    def crateBoxes(): List[(Vec2.Vec2, Render.RenderItem)] =
        plank() :: List.flatten(seams() :: rails() :: frameJoints() :: outline() :: Nil)

    /// Base plank: fill the whole tile with plank brown.
    def plank(): (Vec2.Vec2, Render.RenderItem) =
        boxAt(crateLeft(), crateTop(), crateSize(), crateSize(), Palette.cratePlank(), zPlank())

    /// Vertical seams: 5 evenly spaced thin lines that make the interior read as 6 boards.
    def seams(): List[(Vec2.Vec2, Render.RenderItem)] =
        let t = crateSize();
        let w = t * 0.04;
        List.map(i ->
            let x = crateLeft() + t * Int32.toFloat64(i) / 6.0 - w / 2.0;
            boxAt(x, crateTop(), w, t, Palette.crateSeam(), zSeam()),
            1 :: 2 :: 3 :: 4 :: 5 :: Nil)

    /// Outer frame: 2 full-width horizontal boards (top, bottom) and 2 vertical boards
    /// sandwiched between them (left, right).
    def rails(): List[(Vec2.Vec2, Render.RenderItem)] =
        let t = crateSize();
        let f = railW();
        let x0 = crateLeft();
        let y0 = crateTop();
        boxAt(x0, y0, t, f, Palette.crateFrame(), zRail()) ::
        boxAt(x0, y0 + t - f, t, f, Palette.crateFrame(), zRail()) ::
        boxAt(x0, y0 + f, f, t - 2.0 * f, Palette.crateFrame(), zRail()) ::
        boxAt(x0 + t - f, y0 + f, f, t - 2.0 * f, Palette.crateFrame(), zRail()) :: Nil

    /// Frame joints: the border lines between the frame and the interior. The 2 full-width
    /// horizontal lines double as the butt joints at the four corners at their ends;
    /// the 2 vertical lines run only between them.
    def frameJoints(): List[(Vec2.Vec2, Render.RenderItem)] =
        let t = crateSize();
        let f = railW();
        let w = t * 0.02;
        let x0 = crateLeft();
        let y0 = crateTop();
        boxAt(x0, y0 + f - w / 2.0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0 + t - f - w / 2.0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + f - w / 2.0, y0 + f, w, t - 2.0 * f, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + t - f - w / 2.0, y0 + f, w, t - 2.0 * f, Palette.crateSeam(), zJoint()) :: Nil

    /// Outer outline: a dark 1px (design resolution) line around the whole crate.
    def outline(): List[(Vec2.Vec2, Render.RenderItem)] =
        let t = crateSize();
        let w = 1.0;
        let x0 = crateLeft();
        let y0 = crateTop();
        boxAt(x0, y0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0 + t - w, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0, w, t, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + t - w, y0, w, t, Palette.crateSeam(), zJoint()) :: Nil

    def boxAt(x: Float64, y: Float64, w: Float64, h: Float64,
              c: Color, z: Int32): (Vec2.Vec2, Render.RenderItem) =
        ({x = x, y = y}, Render.solidBox({x = w, y = h}, c, z))

    /// Diagonal brace: one thick band from the inner bottom-left to the inner top-right,
    /// plus 2 dark edge lines. All 3 strips share the same centerline and direction vector;
    /// only their normal-offset ranges differ (building the edges along the normal keeps
    /// their thickness constant everywhere).
    def cratePolys(): List[GameEngine.PolygonRenderCmd] =
        let half = crateSize() * 0.09;    // half-width of the central band (0.18T thick)
        let edge = crateSize() * 0.03;    // thickness of one edge line
        braceStrip(-half - edge, -half, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(half, half + edge, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(-half, half, Palette.crateBrace(), zBrace()) :: Nil

    /// A parallelogram (convex quad) covering normal offsets o1..o2 from the band's
    /// centerline. The centerline runs inner bottom-left corner -> inner top-right corner,
    /// extended by ext at both ends. The extended ends tuck under the frame rails drawn
    /// later, so the strip ends need no shaping.
    def braceStrip(o1: Float64, o2: Float64, c: Color, z: Int32): GameEngine.PolygonRenderCmd =
        let t = crateSize();
        let f = railW();
        let ext = t * 0.04;
        let bl = {x = crateLeft() + f, y = crateTop() + t - f};
        let tr = {x = crateLeft() + t - f, y = crateTop() + f};
        let d = Vec2.mul(Vec2.sub(tr, bl), 1.0 / Vec2.length(Vec2.sub(tr, bl)));
        let n = {x = -d#y, y = d#x};
        let p0 = Vec2.sub(bl, Vec2.mul(d, ext));
        let p1 = Vec2.add(tr, Vec2.mul(d, ext));
        { vertices = Vec2.add(p0, Vec2.mul(n, o1)) :: Vec2.add(p1, Vec2.mul(n, o1)) ::
                     Vec2.add(p1, Vec2.mul(n, o2)) :: Vec2.add(p0, Vec2.mul(n, o2)) :: Nil,
          color = c, alpha = 1.0f32, zIndex = z }

    /// Title text horizontally centered near the top of the screen.
    def titlePlacement(atlas: FontAtlas): (Vec2.Vec2, Render.RenderItem) =
        let size = 28.0;
        let width = Label2D.measure(Label2D.make("Sokoban", atlas, size))#x;
        let pos = {x = centerX() - width / 2.0, y = 24.0};
        (pos, Render.textTinted("Sokoban", atlas, size, Palette.titleText(), zTitle()))

    // ── Launcher: keep drawing frame until the window closes ──
    pub def start(atlas: FontAtlas): Unit \ GameEngine.Game =
        if (GameEngine.Game.shouldClose() or GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let (drawables, polys) = frame(atlas);
            GameEngine.Game.renderCommands(drawables, Nil, polys);
            start(atlas)
        }
}
