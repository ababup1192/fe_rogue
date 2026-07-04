// GameGallery — ゲーム全体のスクリーンショットとプレイ GIF をヘッドレスに焼き込
// み、ギャラリーダッシュボードを生成する；flix test がすべてを再生成する。
//
//   gallery/screen_title.png   — タイトルページ（すべて Spec）
//   gallery/screen_level1.png  — レベル1、静止状態、0手目
//   gallery/screen_push.png    — スライド中(t = 0.5)で凍結された押し
//   gallery/screen_clear.png   — CLEAR パネル、Moves: 7
//   gallery/solve_level1.gif   — ゲーム全体: タイトル、Enter、7手、CLEAR
//   gallery/rewind_demo.gif    — 3手、その後 Z を押し続ける: 映像が逆再生される
//                                間、時計は反時計回りに回る
//   gallery/index.html         — 上記すべてを見せる SnapshotSite ダッシュボード
//
// どの画像も同じ生地から裁断される: Trace（Replay）が純粋な tick を駆動し、各フ
// レームはランチャーが使うのと同じ frame + projectUi + renderUi によって、ウィ
// ンドウの代わりに Harness の下で投影される。
mod GameGallery {
    import java.io.File
    import java.awt.image.BufferedImage

    def ttfPath(): String = "assets/Xolonium-Regular.ttf"
    def design(): Vec2.Vec2 = {x = 320.0, y = 240.0}

    /// 2倍のピクセル: Retina でくっきり、ファイルはそれでも小さい。
    def scale(): Int32 = 2

    def gifFrameDelayMs(): Int32 = 30

    /// GIF はシミュレーションフレームの2つおきを残す: 64Hz のシミュレーション
    /// を画面上は約33msの1フレームにする —— ほぼリアルタイムに近い。
    def gifSampleStride(): Int32 = 2

    def fresh(w: Board.World): Worldline[Board.World] =
        Worldline.make(w, Sokoban.historyCap())

    // ── 1フレーム、ランチャーが組み立てるのとまったく同じように ──

    /// ある瞬間の完全な絵: ボードの投影 + UI ページ、合成済み。純粋 —— UI ページ
    /// はボックスとテキストしか持たないので、`renderUiWith` は焼き込み済みの
    /// atlas 以外何も必要としない（テクスチャサイズを尋ねることは決してない）。
    def scene(atlas: FontAtlas, ui: UiStore.UiWorld, line: Worldline[Board.World]):
            {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]} =
        let w = Worldline.current(line);
        let (ds, ps) = View.frame(atlas, w);
        let ui1 = GameUi.projectUi(Worldline.pastLength(line), w, ui);
        let out = UiRender.renderUiWith(_ -> atlas, _ -> None, ui1, design());
        { drawables = List.append(ds, out#drawables),
          polygons = List.append(ps, out#polygons) }

    def rasterReq(atlas: FontAtlas,
                  sc: {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]},
                  path: String): SoftRaster.RasterReq =
        { drawables = sc#drawables, polygons = sc#polygons,
          design = design(), scale = scale(), background = Palette.clearColor(),
          texturePath = Map.empty(), fontTtf = ttfPath(), fontAtlas = atlas,
          outPath = path }

    def shot(atlas: FontAtlas, ui: UiStore.UiWorld, line: Worldline[Board.World],
             path: String): Unit \ IO =
        SoftRaster.render(rasterReq(atlas, scene(atlas, ui, line), path))

    // ── 4枚の画面 ──

    /// 半分の位置で凍結された押し: 下のクレートの後ろに回るための2手、それから
    /// 押す手を1+4フレーム押し続ける —— スライドは t = 0.5 に位置する。
    def midPush(): Worldline[Board.World] =
        let cues = List.flatten(
            Trace.walk(Dir4.Left) ::
            Trace.walk(Dir4.Up) ::
            (Trace.hold({ right = true | Trace.idle() }, 1) ::
             Trace.hold(Trace.idle(), 4) :: Nil) :: Nil);
        Replay.play(Sokoban.tick, Trace.dt(), cues, fresh(Board.playingWorld(1)))

    /// 解決済みのボード、パーティ開始1秒後、紙吹雪が空中に舞っている。
    def clearedAndRaining(): Worldline[Board.World] =
        let cues = List.append(Trace.solveLevelOne(),
                               Trace.hold(Trace.idle(), 64) :: Nil);
        Replay.play(Sokoban.tick, Trace.dt(), cues, fresh(Board.playingWorld(1)))

    def bakeScreens(atlas: FontAtlas, ui: UiStore.UiWorld): Unit \ IO =
        shot(atlas, ui, fresh(Board.titleWorld()), "gallery/screen_title.png");
        shot(atlas, ui, fresh(Board.playingWorld(1)), "gallery/screen_level1.png");
        shot(atlas, ui, midPush(), "gallery/screen_push.png");
        shot(atlas, ui, clearedAndRaining(), "gallery/screen_clear.png")

    // ── 2本のフィルム ──

    /// stride 個おきのフレームだけを残す（フィルムは 64Hz で撮影され、GIF は
    /// 約32Hz で見せる）。
    def every(stride: Int32, i: Int32, xs: List[a]): List[a] = match xs {
        case Nil     => Nil
        case x :: rest =>
            if (Int32.modulo(i, stride) == 0) x :: every(stride, i + 1, rest)
            else every(stride, i + 1, rest)
    }

    def bakeGif(atlas: FontAtlas, ui: UiStore.UiWorld, cues: List[Replay.Cue[Board.Input]],
                start: Worldline[Board.World], path: String): Unit \ IO =
        let film = Replay.timeline(Sokoban.tick, Trace.dt(), cues, start);
        let frames = List.map(l -> SoftRaster.renderToImage(rasterReq(atlas, scene(atlas, ui, l), path)),
                              every(gifSampleStride(), 0, film));
        GifEncoder.encode(frames, gifFrameDelayMs(), path)

    /// オープニング: タイトルが待ち、Enter がレベル1を開き、7手がそれを解き、
    /// CLEAR パネルがそれを数える。
    def solveCues(): List[Replay.Cue[Board.Input]] =
        List.flatten(
            (Trace.hold(Trace.idle(), 12) ::
             Trace.hold({ enter = true | Trace.idle() }, 1) ::
             Trace.hold(Trace.idle(), 8) :: Nil) ::
            Trace.solveLevelOne() ::
            (Trace.hold(Trace.idle(), 40) :: Nil) :: Nil)

    /// ゲームの1周まるごと: タイトル、Enter、レベル1解決、CLEAR、Enter、レベル
    /// 2をその迂回込みで解決、CLEAR —— そして最後の Enter がタイトルへ戻す。
    /// フィルムにして約6秒。
    def fullClearCues(): List[Replay.Cue[Board.Input]] =
        List.flatten(
            (Trace.hold(Trace.idle(), 12) ::
             Trace.hold({ enter = true | Trace.idle() }, 1) ::
             Trace.hold(Trace.idle(), 8) :: Nil) ::
            Trace.solveLevelOne() ::
            (Trace.hold(Trace.idle(), 30) ::
             Trace.hold({ enter = true | Trace.idle() }, 1) ::
             Trace.hold(Trace.idle(), 8) :: Nil) ::
            Trace.solveLevelTwo() ::
            (Trace.hold(Trace.idle(), 30) ::
             Trace.hold({ enter = true | Trace.idle() }, 1) ::
             Trace.hold(Trace.idle(), 36) :: Nil) :: Nil)

    /// 象徴的な動き: 3手進み（3手目でクレートをゴールへ押し込む）、それから Z
    /// を押し続ける —— アラーム時計が浮かび上がり反時計回りに回りながら、ロボッ
    /// トとクレートが家路を滑って戻り、その後しばらく留まってフェードする。
    def rewindCues(): List[Replay.Cue[Board.Input]] =
        List.flatten(
            (Trace.hold(Trace.idle(), 8) :: Nil) ::
            Trace.walk(Dir4.Left) ::
            Trace.walk(Dir4.Up) ::
            Trace.walk(Dir4.Right) ::
            (Trace.hold(Trace.idle(), 14) ::
             Trace.rewind(54) ::
             Trace.hold(Trace.idle(), 32) :: Nil) :: Nil)

    // ── ダッシュボード ──

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

    /// 1つのテストがすべてを、必ずこの順序で焼き込む: まずスクリーンショットと
    /// フィルム、最後にサイト —— こうすることで単発の `flix test` は常に完全な
    /// ダッシュボードを残し、プレースホルダーのページを残すことは決してない。
    /// （ロボットの画像は RobotGallery が焼き込み、git にもチェックインされてい
    /// るので、これが走るときには必ず存在する。）
    @Test
    def testBakeGalleryAndSite(): Unit \ {Assert, IO} =
        let atlas = Harness.atlas();
        discard (new File("gallery")).mkdirs();
        match Harness.ui() {
            case None     => Assert.assertEq(expected = "spawned", "the ui specs failed to spawn")
            case Some(ui) =>
                bakeScreens(atlas, ui);
                bakeGif(atlas, ui, solveCues(), fresh(Board.titleWorld()), "gallery/solve_level1.gif");
                bakeGif(atlas, ui, fullClearCues(), fresh(Board.titleWorld()), "gallery/full_clear.gif");
                bakeGif(atlas, ui, rewindCues(), fresh(Board.playingWorld(1)), "gallery/rewind_demo.gif");
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
