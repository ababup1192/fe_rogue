// RobotGallery — bakes robot design galleries for approval by eye, headlessly
// (engine_tools' SoftRaster + GifEncoder, no GL); flix test generates the files.
//
//   gallery/robots.png            — the original 6 candidates (kept for reference)
//   gallery/robot2_directions.png — the chosen robot (candidate 2, round-eyed) x 4 facings
//   gallery/robot2_walk.gif       — the 4 facings marching in place (walk cycle check)
//
// Same procedural approach as the crate: stacks of boxes (plus a convex quad where
// noted) on a 16-unit tile grid, drawn at 8x for easy viewing. The chosen robot
// lives in src/Robot.flix (with Palette roles); the 6 candidates keep local colors.

mod RobotGallery {
    import java.io.File

    // ── Canvas layout ──
    // 6 cells of 18 units; each robot occupies a 16-unit tile with a 1-unit margin.
    def u(): Float64 = 8.0                       // 1 pixel-art unit = 8 design px (8x view)
    def cellW(): Float64 = 18.0 * u()            // 144 px per cell
    def robotTop(): Float64 = 12.0
    def labelY(): Float64 = robotTop() + 16.0 * u() + 6.0
    def designSize(): Vec2.Vec2 = {x = 6.0 * cellW(), y = 184.0}

    // ── DB32 colors for the candidates ──
    def body(): Color   = {r = 0.356863f32, g = 0.431373f32, b = 0.882353f32}  // #5b6ee1
    def light(): Color  = {r = 0.388235f32, g = 0.607843f32, b = 1.000000f32}  // #639bff
    def pale(): Color   = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}  // #cbdbfc
    def accent(): Color = {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}  // #fbf236
    def dark(): Color   = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}  // #222034
    def backdrop(): Color = {r = 0.270588f32, g = 0.156863f32, b = 0.235294f32}  // #45283c

    def ttfPath(): String = "assets/Xolonium-Regular.ttf"
    def outPath(): String = "gallery/robots.png"

    // ── Part helpers (coordinates in tile units, relative to the robot's cell origin) ──

    def box(o: Vec2.Vec2, x: Float64, y: Float64, w: Float64, h: Float64,
            c: Color): (Vec2.Vec2, Render.RenderItem) =
        ({x = o#x + x * u(), y = o#y + y * u()},
         Render.solidBox({x = w * u(), y = h * u()}, c, 0))

    /// Rounded box (cornerRadius in tile units). Used by candidate 4 and the wheels of 6.
    def rbox(o: Vec2.Vec2, x: Float64, y: Float64, w: Float64, h: Float64,
             r: Float64, c: Color): (Vec2.Vec2, Render.RenderItem) =
        let style = { cornerRadius = r * u(), borderWidth = 0.0, borderColor = c,
                      borderAlpha = 0.0f32, stripeColor = c, stripeAlpha = 0.0f32,
                      stripeWidth = 0.0, stripePeriod = 0.0 };
        ({x = o#x + x * u(), y = o#y + y * u()},
         Render.RenderItem.Box({ size = {x = w * u(), y = h * u()}, color = c,
                                 alpha = 1.0f32, style = Some(style), zIndex = 1 }))

    /// Convex quad in tile units (candidate 5's trapezoid torso). z -1 keeps it under the
    /// boxes, so arms and chest details drawn at z 0 stay visible on top of the torso.
    def quad(o: Vec2.Vec2, ps: List[(Float64, Float64)], c: Color): GameEngine.PolygonRenderCmd =
        { vertices = List.map(p -> let (x, y) = p; {x = o#x + x * u(), y = o#y + y * u()}, ps),
          color = c, alpha = 1.0f32, zIndex = -1 }

    // ── The 6 candidates ──

    /// 1. The classic: squat square body, two eyes, one antenna. A safe crowd-pleaser.
    def robot1(o: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        box(o, 7.6, 1.6, 0.8, 2.6, light()) ::          // antenna stem
        box(o, 6.8, 0.2, 2.4, 2.0, accent()) ::         // antenna tip
        box(o, 3.0, 4.0, 10.0, 9.0, body()) ::          // body
        box(o, 3.0, 4.0, 10.0, 1.2, light()) ::         // top highlight
        box(o, 5.2, 6.6, 1.8, 1.8, accent()) ::         // left eye
        box(o, 9.0, 6.6, 1.8, 1.8, accent()) ::         // right eye
        box(o, 6.0, 10.2, 4.0, 0.8, dark()) ::          // mouth grille
        box(o, 1.5, 6.0, 1.4, 4.0, light()) ::          // left arm
        box(o, 13.1, 6.0, 1.4, 4.0, light()) ::         // right arm
        box(o, 4.0, 13.0, 3.0, 1.6, light()) ::         // left foot
        box(o, 9.0, 13.0, 3.0, 1.6, light()) :: Nil     // right foot

    /// 2. The cyclops: tall slab body with one big eye. Reads well even at 16px.
    def robot2(o: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        box(o, 4.5, 2.0, 7.0, 12.0, body()) ::          // tall body
        box(o, 4.5, 2.0, 7.0, 1.0, light()) ::          // top highlight
        box(o, 6.0, 4.0, 4.0, 4.0, pale()) ::           // eye ring
        box(o, 7.2, 5.2, 1.6, 1.6, dark()) ::           // pupil
        box(o, 6.0, 9.6, 4.0, 0.7, dark()) ::           // chest line
        box(o, 5.4, 11.0, 1.2, 0.6, light()) ::         // vent 1
        box(o, 5.4, 12.0, 1.2, 0.6, light()) ::         // vent 2
        box(o, 3.0, 5.0, 1.5, 5.0, light()) ::          // left arm
        box(o, 11.5, 5.0, 1.5, 5.0, light()) ::         // right arm
        box(o, 5.0, 14.0, 2.5, 1.5, light()) ::         // left foot
        box(o, 8.5, 14.0, 2.5, 1.5, light()) :: Nil     // right foot

    /// 3. The two-piece: separate head and torso with stubby legs. The most "pusher" build.
    def robot3(o: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        box(o, 4.5, 1.5, 7.0, 4.5, body()) ::           // head
        box(o, 6.0, 3.0, 1.5, 1.5, accent()) ::         // left eye
        box(o, 8.5, 3.0, 1.5, 1.5, accent()) ::         // right eye
        box(o, 7.0, 6.0, 2.0, 1.0, dark()) ::           // neck
        box(o, 3.5, 7.0, 9.0, 6.0, body()) ::           // torso
        box(o, 5.5, 8.5, 5.0, 3.0, light()) ::          // belly panel
        box(o, 7.3, 9.8, 1.4, 0.6, dark()) ::           // panel slit
        box(o, 5.0, 13.0, 2.0, 2.0, light()) ::         // left leg
        box(o, 9.0, 13.0, 2.0, 2.0, light()) ::         // right leg
        box(o, 4.6, 14.6, 2.8, 0.9, dark()) ::          // left foot pad
        box(o, 8.6, 14.6, 2.8, 0.9, dark()) :: Nil      // right foot pad

    /// 4. The rounded one: soft cornerRadius body with a single visor eye.
    def robot4(o: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        rbox(o, 3.5, 3.0, 9.0, 11.0, 2.5, body()) ::    // rounded body
        rbox(o, 4.5, 5.2, 7.0, 2.8, 1.4, dark()) ::     // visor housing
        rbox(o, 5.0, 5.8, 6.0, 1.6, 0.8, accent()) ::   // visor (the eye itself)
        box(o, 2.6, 6.0, 1.0, 2.0, light()) ::          // left ear bolt
        box(o, 12.4, 6.0, 1.0, 2.0, light()) ::         // right ear bolt
        rbox(o, 6.0, 10.0, 4.0, 2.2, 1.0, light()) ::   // belly light
        rbox(o, 4.8, 13.6, 2.6, 1.4, 0.7, light()) ::   // left foot
        rbox(o, 8.6, 13.6, 2.6, 1.4, 0.7, light()) :: Nil  // right foot

    /// 5. The heavy: small head over a trapezoid torso (convex quad) — wide, stable stance.
    def robot5Boxes(o: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        box(o, 5.5, 1.5, 5.0, 3.5, body()) ::           // head
        box(o, 6.5, 2.6, 1.2, 1.2, accent()) ::         // left eye
        box(o, 8.3, 2.6, 1.2, 1.2, accent()) ::         // right eye
        box(o, 7.2, 5.0, 1.6, 0.9, dark()) ::           // neck
        box(o, 6.5, 8.0, 3.0, 1.0, light()) ::          // chest stripe
        box(o, 3.4, 7.0, 1.4, 4.2, light()) ::          // left arm
        box(o, 11.2, 7.0, 1.4, 4.2, light()) ::         // right arm
        box(o, 5.0, 13.5, 2.2, 1.4, light()) ::         // left foot
        box(o, 8.8, 13.5, 2.2, 1.4, light()) :: Nil     // right foot

    def robot5Polys(o: Vec2.Vec2): List[GameEngine.PolygonRenderCmd] =
        quad(o, (5.5, 6.0) :: (10.5, 6.0) :: (12.5, 13.5) :: (3.5, 13.5) :: Nil, body()) :: Nil

    /// 6. The CRT: a monitor face with dot eyes on the screen, riding a wheeled base.
    def robot6(o: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        box(o, 3.0, 2.5, 10.0, 8.0, body()) ::          // monitor shell
        box(o, 4.2, 3.7, 7.6, 5.6, pale()) ::           // screen
        box(o, 6.2, 5.6, 1.2, 1.2, dark()) ::           // left dot eye
        box(o, 8.6, 5.6, 1.2, 1.2, dark()) ::           // right dot eye
        box(o, 6.8, 7.6, 2.4, 0.6, dark()) ::           // smile line
        box(o, 6.0, 10.5, 4.0, 1.5, light()) ::         // neck
        box(o, 4.0, 12.0, 8.0, 2.0, body()) ::          // chassis
        rbox(o, 4.6, 13.6, 2.0, 1.6, 0.8, dark()) ::    // left wheel
        rbox(o, 9.4, 13.6, 2.0, 1.6, 0.8, dark()) :: Nil  // right wheel

    // ── Assembly ──

    def cellOrigin(i: Int32): Vec2.Vec2 =
        {x = Int32.toFloat64(i) * cellW() + 1.0 * u(), y = robotTop()}

    def label(atlas: FontAtlas, i: Int32): (Vec2.Vec2, Render.RenderItem) =
        let text = "${i + 1}";
        let size = 22.0;
        let w = Label2D.measure(Label2D.make(text, atlas, size))#x;
        let cx = Int32.toFloat64(i) * cellW() + cellW() / 2.0;
        ({x = cx - w / 2.0, y = labelY()}, Render.textTinted(text, atlas, size, pale(), 10))

    def galleryItems(atlas: FontAtlas):
            (List[(Vec2.Vec2, Render.RenderItem)], List[GameEngine.PolygonRenderCmd]) =
        let robots = robot1(cellOrigin(0)) :: robot2(cellOrigin(1)) :: robot3(cellOrigin(2)) ::
                     robot4(cellOrigin(3)) :: robot5Boxes(cellOrigin(4)) :: robot6(cellOrigin(5)) :: Nil;
        let labels = List.map(i -> label(atlas, i), 0 :: 1 :: 2 :: 3 :: 4 :: 5 :: Nil);
        (List.append(List.flatten(robots), labels), robot5Polys(cellOrigin(4)))

    // ── Test entry: bake the PNG and sanity-check it ──

    @Test
    def testRobotGalleryPng(): Unit \ {Assert, IO} =
        HeadlessFont.ensureHeadless();
        let atlas = HeadlessFont.buildUiAtlas(ttfPath(), "assets/joyo.txt");
        let (items, polys) = galleryItems(atlas);
        discard (new File("gallery")).mkdirs();
        SoftRaster.render({
            drawables = Render.draw(items), polygons = polys,
            design = designSize(), scale = 1, background = backdrop(),
            texturePath = Map.empty(), fontTtf = ttfPath(), fontAtlas = atlas,
            outPath = outPath()
        });
        // Sanity: the file exists and every candidate contributed parts.
        Assert.assertEq(expected = true,
            (new File(outPath())).exists() and List.length(items) > 50 and List.length(polys) == 1)

    // ── Gallery v2: the chosen robot in all four facings, static and walking ──

    def dirDesign(): Vec2.Vec2 = {x = 4.0 * cellW(), y = 184.0}
    def dirOutPath(): String = "gallery/robot2_directions.png"
    def walkOutPath(): String = "gallery/robot2_walk.gif"
    def walkFrameDelayMs(): Int32 = 150

    def robotCenter(i: Int32): Vec2.Vec2 =
        {x = Int32.toFloat64(i) * cellW() + cellW() / 2.0, y = robotTop() + 8.0 * u()}

    def labelAt(atlas: FontAtlas, i: Int32, text: String): (Vec2.Vec2, Render.RenderItem) =
        let size = 22.0;
        let w = Label2D.measure(Label2D.make(text, atlas, size))#x;
        let cx = Int32.toFloat64(i) * cellW() + cellW() / 2.0;
        ({x = cx - w / 2.0, y = labelY()}, Render.textTinted(text, atlas, size, pale(), 10))

    /// One frame of the 4-facing row at walk phase `phase` (0.0 = the static poses).
    def directionItems(atlas: FontAtlas, phase: Float64): List[(Vec2.Vec2, Render.RenderItem)] =
        let one = i -> dir -> name ->
            List.append(Robot.parts(robotCenter(i), 16.0 * u(), dir, phase),
                        labelAt(atlas, i, name) :: Nil);
        List.flatten(
            one(0)(Dir4.Down)("Down") ::
            one(1)(Dir4.Left)("Left") ::
            one(2)(Dir4.Right)("Right") ::
            one(3)(Dir4.Up)("Up") :: Nil)

    def directionsReq(atlas: FontAtlas, phase: Float64, path: String): SoftRaster.RasterReq =
        { drawables = Render.draw(directionItems(atlas, phase)), polygons = Nil,
          design = dirDesign(), scale = 1, background = backdrop(),
          texturePath = Map.empty(), fontTtf = ttfPath(), fontAtlas = atlas,
          outPath = path }

    @Test
    def testRobotDirectionsPng(): Unit \ {Assert, IO} =
        HeadlessFont.ensureHeadless();
        let atlas = HeadlessFont.buildUiAtlas(ttfPath(), "assets/joyo.txt");
        discard (new File("gallery")).mkdirs();
        SoftRaster.render(directionsReq(atlas, 0.0, dirOutPath()));
        Assert.assertEq(expected = true,
            (new File(dirOutPath())).exists() and
            List.length(directionItems(atlas, 0.0)) > 30)

    /// The walk cycle: 4 beats (rest, step, rest, step), all facings in step — foot
    /// lifts on Down/Up, stride open/close plus arm swing on Left/Right.
    @Test
    def testRobotWalkGif(): Unit \ {Assert, IO} =
        HeadlessFont.ensureHeadless();
        let atlas = HeadlessFont.buildUiAtlas(ttfPath(), "assets/joyo.txt");
        discard (new File("gallery")).mkdirs();
        let frames = List.map(p -> SoftRaster.renderToImage(directionsReq(atlas, p, walkOutPath())),
                              0.0 :: 0.25 :: 0.5 :: 0.75 :: Nil);
        GifEncoder.encode(frames, walkFrameDelayMs(), walkOutPath());
        Assert.assertEq(expected = true, (new File(walkOutPath())).exists())
}
