// Crate — the pushable box, drawn procedurally: a stack of boxes plus convex
// polygons for the diagonal brace. Every part is placed relative to the crate's
// center and sized relative to the requested tile size, so the same functions
// draw a 96px showcase crate and a 24px board tile.

mod Crate {

    // Thickness of the outer frame rails, relative to the tile.
    def railW(t: Float64): Float64 = t * 0.12

    // Drawing order (zIndex): base plank -> vertical seams -> diagonal brace ->
    // frame rails -> frame joints and outer outline. The rails draw after the
    // brace, so the brace's extended ends tuck underneath them.
    def zPlank(): Int32 = 0
    def zSeam(): Int32 = 1
    def zBraceEdge(): Int32 = 2
    def zBrace(): Int32 = 3
    def zRail(): Int32 = 4
    def zJoint(): Int32 = 5

    def topLeftOf(center: Vec2.Vec2, t: Float64): Vec2.Vec2 =
        {x = center#x - t / 2.0, y = center#y - t / 2.0}

    /// Box parts: 1 base plank + 5 vertical seams + 4 frame rails + 4 frame joints + 4 outline edges.
    pub def boxes(center: Vec2.Vec2, t: Float64): List[(Vec2.Vec2, Render.RenderItem)] =
        let tl = topLeftOf(center, t);
        plank(tl, t) :: List.flatten(seams(tl, t) :: rails(tl, t) :: frameJoints(tl, t) :: outline(tl, t) :: Nil)

    /// Base plank: fill the whole tile with plank brown.
    def plank(tl: Vec2.Vec2, t: Float64): (Vec2.Vec2, Render.RenderItem) =
        boxAt(tl#x, tl#y, t, t, Palette.cratePlank(), zPlank())

    /// Vertical seams: 5 evenly spaced thin lines that make the interior read as 6 boards.
    def seams(tl: Vec2.Vec2, t: Float64): List[(Vec2.Vec2, Render.RenderItem)] =
        let w = t * 0.04;
        List.map(i ->
            let x = tl#x + t * Int32.toFloat64(i) / 6.0 - w / 2.0;
            boxAt(x, tl#y, w, t, Palette.crateSeam(), zSeam()),
            1 :: 2 :: 3 :: 4 :: 5 :: Nil)

    /// Outer frame: 2 full-width horizontal boards (top, bottom) and 2 vertical boards
    /// sandwiched between them (left, right).
    def rails(tl: Vec2.Vec2, t: Float64): List[(Vec2.Vec2, Render.RenderItem)] =
        let f = railW(t);
        let x0 = tl#x;
        let y0 = tl#y;
        boxAt(x0, y0, t, f, Palette.crateFrame(), zRail()) ::
        boxAt(x0, y0 + t - f, t, f, Palette.crateFrame(), zRail()) ::
        boxAt(x0, y0 + f, f, t - 2.0 * f, Palette.crateFrame(), zRail()) ::
        boxAt(x0 + t - f, y0 + f, f, t - 2.0 * f, Palette.crateFrame(), zRail()) :: Nil

    /// Frame joints: the border lines between the frame and the interior. The 2 full-width
    /// horizontal lines double as the butt joints at the four corners at their ends;
    /// the 2 vertical lines run only between them.
    def frameJoints(tl: Vec2.Vec2, t: Float64): List[(Vec2.Vec2, Render.RenderItem)] =
        let f = railW(t);
        let w = t * 0.02;
        let x0 = tl#x;
        let y0 = tl#y;
        boxAt(x0, y0 + f - w / 2.0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0 + t - f - w / 2.0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + f - w / 2.0, y0 + f, w, t - 2.0 * f, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + t - f - w / 2.0, y0 + f, w, t - 2.0 * f, Palette.crateSeam(), zJoint()) :: Nil

    /// Outer outline: a dark 1px (design resolution) line around the whole crate.
    def outline(tl: Vec2.Vec2, t: Float64): List[(Vec2.Vec2, Render.RenderItem)] =
        let w = 1.0;
        let x0 = tl#x;
        let y0 = tl#y;
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
    pub def polys(center: Vec2.Vec2, t: Float64): List[GameEngine.PolygonRenderCmd] =
        let tl = topLeftOf(center, t);
        let half = t * 0.09;    // half-width of the central band (0.18T thick)
        let edge = t * 0.03;    // thickness of one edge line
        braceStrip(tl, t, -half - edge, -half, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(tl, t, half, half + edge, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(tl, t, -half, half, Palette.crateBrace(), zBrace()) :: Nil

    /// A parallelogram (convex quad) covering normal offsets o1..o2 from the band's
    /// centerline. The centerline runs inner bottom-left corner -> inner top-right corner,
    /// extended by ext at both ends. The extended ends tuck under the frame rails drawn
    /// later, so the strip ends need no shaping.
    def braceStrip(tl: Vec2.Vec2, t: Float64, o1: Float64, o2: Float64,
                   c: Color, z: Int32): GameEngine.PolygonRenderCmd =
        let f = railW(t);
        let ext = t * 0.04;
        let bl = {x = tl#x + f, y = tl#y + t - f};
        let tr = {x = tl#x + t - f, y = tl#y + f};
        let d = Vec2.mul(Vec2.sub(tr, bl), 1.0 / Vec2.length(Vec2.sub(tr, bl)));
        let n = {x = -d#y, y = d#x};
        let p0 = Vec2.sub(bl, Vec2.mul(d, ext));
        let p1 = Vec2.add(tr, Vec2.mul(d, ext));
        { vertices = Vec2.add(p0, Vec2.mul(n, o1)) :: Vec2.add(p1, Vec2.mul(n, o1)) ::
                     Vec2.add(p1, Vec2.mul(n, o2)) :: Vec2.add(p0, Vec2.mul(n, o2)) :: Nil,
          color = c, alpha = 1.0f32, zIndex = z }
}
