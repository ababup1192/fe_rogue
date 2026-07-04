// GameGallery — bakes full-game screenshots and play GIFs, headlessly, and
// generates the gallery dashboard; flix test regenerates everything.
//
//   gallery/screen_title.png   — the title page (all Spec)
//   gallery/screen_level1.png  — level 1 at rest, move zero
//   gallery/screen_push.png    — a push frozen mid-slide (t = 0.5)
//   gallery/screen_clear.png   — the CLEAR panel, Moves: 7
//   gallery/solve_level1.gif   — the whole game: title, Enter, seven moves, CLEAR
//   gallery/rewind_demo.gif    — three moves, then Z held: the clock turns
//                                counterclockwise while the film runs backwards
//   gallery/index.html         — SnapshotSite dashboard over all of the above
//
// Every picture is cut from the same cloth: a Trace (Replay) drives the pure
// tick, and each frame is projected by the same frame + projectUi + renderUi
// the launcher uses — under Harness instead of a window.
mod GameGallery {
    import java.io.File
    import java.awt.image.BufferedImage

    def ttfPath(): String = "assets/Xolonium-Regular.ttf"
    def design(): Vec2.Vec2 = {x = 320.0, y = 240.0}

    /// 2x pixels: crisp on Retina, still small files.
    def scale(): Int32 = 2

    def gifFrameDelayMs(): Int32 = 30

    /// The GIFs keep every 2nd simulated frame: 64 Hz simulation, ~33 ms a
    /// frame on screen — close to real time.
    def gifSampleStride(): Int32 = 2

    def fresh(w: Sokoban.World): Worldline[Sokoban.World] =
        Worldline.make(w, Sokoban.historyCap())

    // ── One frame, exactly as the launcher composes it ──

    /// The full picture of one moment: board projection + UI pages, merged.
    /// Pure — the mock Game handler answers only the font atlas.
    def scene(atlas: FontAtlas, ui: UiStore.UiWorld, line: Worldline[Sokoban.World]):
            {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]} =
        let w = Worldline.current(line);
        let (ds, ps) = Sokoban.frame(atlas, w);
        let ui1 = Sokoban.projectUi(Worldline.pastLength(line), w, ui);
        let out = Harness.withMockGame(atlas, _ -> UiRender.renderUi(ui1, design()));
        { drawables = List.append(ds, out#drawables),
          polygons = List.append(ps, out#polygons) }

    def rasterReq(atlas: FontAtlas,
                  sc: {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]},
                  path: String): SoftRaster.RasterReq =
        { drawables = sc#drawables, polygons = sc#polygons,
          design = design(), scale = scale(), background = Palette.clearColor(),
          texturePath = Map.empty(), fontTtf = ttfPath(), fontAtlas = atlas,
          outPath = path }

    def shot(atlas: FontAtlas, ui: UiStore.UiWorld, line: Worldline[Sokoban.World],
             path: String): Unit \ IO =
        SoftRaster.render(rasterReq(atlas, scene(atlas, ui, line), path))

    // ── The four screens ──

    /// A push frozen halfway: two moves to get behind the lower crate, then
    /// the pushing move held for 1 + 4 frames — the slide sits at t = 0.5.
    def midPush(): Worldline[Sokoban.World] =
        let cues = List.flatten(
            Replay.walk(Robot.Direction.Left) ::
            Replay.walk(Robot.Direction.Up) ::
            (Replay.hold({ right = true | Replay.idle() }, 1) ::
             Replay.hold(Replay.idle(), 4) :: Nil) :: Nil);
        Replay.play(cues, fresh(Sokoban.playingWorld(1)))

    /// The solved board one second into the party, confetti mid-air.
    def clearedAndRaining(): Worldline[Sokoban.World] =
        let cues = List.append(Replay.solveLevelOne(),
                               Replay.hold(Replay.idle(), 64) :: Nil);
        Replay.play(cues, fresh(Sokoban.playingWorld(1)))

    def bakeScreens(atlas: FontAtlas, ui: UiStore.UiWorld): Unit \ IO =
        shot(atlas, ui, fresh(Sokoban.titleWorld()), "gallery/screen_title.png");
        shot(atlas, ui, fresh(Sokoban.playingWorld(1)), "gallery/screen_level1.png");
        shot(atlas, ui, midPush(), "gallery/screen_push.png");
        shot(atlas, ui, clearedAndRaining(), "gallery/screen_clear.png")

    // ── The two films ──

    /// Keep every stride-th frame (the film is shot at 64 Hz; the GIF shows ~32).
    def every(stride: Int32, i: Int32, xs: List[a]): List[a] = match xs {
        case Nil     => Nil
        case x :: rest =>
            if (Int32.modulo(i, stride) == 0) x :: every(stride, i + 1, rest)
            else every(stride, i + 1, rest)
    }

    def bakeGif(atlas: FontAtlas, ui: UiStore.UiWorld, cues: List[Replay.Cue],
                start: Worldline[Sokoban.World], path: String): Unit \ IO =
        let film = Replay.timeline(cues, start);
        let frames = List.map(l -> SoftRaster.renderToImage(rasterReq(atlas, scene(atlas, ui, l), path)),
                              every(gifSampleStride(), 0, film));
        GifEncoder.encode(frames, gifFrameDelayMs(), path)

    /// The opening act: the title waits, Enter opens level 1, seven moves
    /// solve it, the CLEAR panel counts them.
    def solveCues(): List[Replay.Cue] =
        List.flatten(
            (Replay.hold(Replay.idle(), 12) ::
             Replay.hold({ enter = true | Replay.idle() }, 1) ::
             Replay.hold(Replay.idle(), 8) :: Nil) ::
            Replay.solveLevelOne() ::
            (Replay.hold(Replay.idle(), 40) :: Nil) :: Nil)

    /// One full lap of the game: title, Enter, level 1 solved, CLEAR, Enter,
    /// level 2 solved through its detours, CLEAR — and the last Enter brings
    /// the title back. About six seconds of film.
    def fullClearCues(): List[Replay.Cue] =
        List.flatten(
            (Replay.hold(Replay.idle(), 12) ::
             Replay.hold({ enter = true | Replay.idle() }, 1) ::
             Replay.hold(Replay.idle(), 8) :: Nil) ::
            Replay.solveLevelOne() ::
            (Replay.hold(Replay.idle(), 30) ::
             Replay.hold({ enter = true | Replay.idle() }, 1) ::
             Replay.hold(Replay.idle(), 8) :: Nil) ::
            Replay.solveLevelTwo() ::
            (Replay.hold(Replay.idle(), 30) ::
             Replay.hold({ enter = true | Replay.idle() }, 1) ::
             Replay.hold(Replay.idle(), 36) :: Nil) :: Nil)

    /// The signature move: three moves in (the third pushes a crate onto its
    /// goal), then Z held — the alarm clock rises and turns counterclockwise
    /// while robot and crate glide home, then lingers and fades.
    def rewindCues(): List[Replay.Cue] =
        List.flatten(
            (Replay.hold(Replay.idle(), 8) :: Nil) ::
            Replay.walk(Robot.Direction.Left) ::
            Replay.walk(Robot.Direction.Up) ::
            Replay.walk(Robot.Direction.Right) ::
            (Replay.hold(Replay.idle(), 14) ::
             Replay.rewind(54) ::
             Replay.hold(Replay.idle(), 32) :: Nil) :: Nil)

    // ── The dashboard ──

    def item(name: String, desc: String, scenario: String, ext: String,
             pxWidth: Int32): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = ext,
          pxWidth = pxWidth, generateHint = Some("run `flix test` to generate"),
          lint = SnapshotSite.noLint() }

    def catalog(): List[SnapshotSite.Item] =
        item("screen_title", "The title page — everything on it is Spec", "Screens", "png", 640) ::
        item("screen_level1", "Level 1 at rest, move zero", "Screens", "png", 640) ::
        item("screen_push", "A push frozen mid-slide (t = 0.5)", "Screens", "png", 640) ::
        item("screen_clear", "The CLEAR panel counting seven moves, confetti falling", "Screens", "png", 640) ::
        item("solve_level1", "The opening act: title, Enter, seven moves, CLEAR", "Play", "gif", 640) ::
        item("full_clear", "One full lap: both levels, both CLEARs, and back to the title", "Play", "gif", 640) ::
        item("rewind_demo", "Z held: the clock turns while the film runs backwards", "Play", "gif", 640) ::
        item("robots", "The six robot candidates", "Robot", "png", 864) ::
        item("robot2_directions", "The chosen cyclops, four facings", "Robot", "png", 576) ::
        item("robot2_walk", "The walk cycle, all facings in step", "Robot", "gif", 576) :: Nil

    /// One test bakes everything, strictly in this order: screenshots and
    /// films first, the site last — so a single `flix test` always leaves a
    /// complete dashboard, never a page of placeholders. (The Robot images
    /// are baked by RobotGallery and also checked into git, so they exist
    /// whenever this runs.)
    @Test
    def testBakeGalleryAndSite(): Unit \ {Assert, IO} =
        let atlas = Harness.atlas();
        discard (new File("gallery")).mkdirs();
        match Harness.ui() {
            case None     => Assert.assertEq(expected = "spawned", "the ui specs failed to spawn")
            case Some(ui) =>
                bakeScreens(atlas, ui);
                bakeGif(atlas, ui, solveCues(), fresh(Sokoban.titleWorld()), "gallery/solve_level1.gif");
                bakeGif(atlas, ui, fullClearCues(), fresh(Sokoban.titleWorld()), "gallery/full_clear.gif");
                bakeGif(atlas, ui, rewindCues(), fresh(Sokoban.playingWorld(1)), "gallery/rewind_demo.gif");
                run {
                    SnapshotSite.generate(
                        { outDir = "gallery", title = "Sokoban Gallery", cssScale = 2 },
                        catalog())
                } with Fs.FileWrite.runWithIO;
                Assert.assertEq(
                    expected = (true, true, true, true, true, true, true, true),
                    ((new File("gallery/screen_title.png")).exists(),
                     (new File("gallery/screen_level1.png")).exists(),
                     (new File("gallery/screen_push.png")).exists(),
                     (new File("gallery/screen_clear.png")).exists(),
                     (new File("gallery/solve_level1.gif")).exists(),
                     (new File("gallery/full_clear.gif")).exists(),
                     (new File("gallery/rewind_demo.gif")).exists(),
                     (new File("gallery/index.html")).exists()))
        }
}
