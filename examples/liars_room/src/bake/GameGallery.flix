// GameGallery — ゲーム画面のスクリーンショット・プレイ GIF・ダッシュボードをヘッドレスに
// 焼き込む。make bake が再生成する。どの画像も同じ生地から裁断される: 入力の台本が純粋な
// tick を駆動し、各フレームはランチャーと同じ projectUi + View.compose で投影される。
//
//   gallery/screen_*.png   — 7 つの画面（タイトル / 部屋 / 会話 / 確認 / メモ / 不正解 / 正解）
//   gallery/talk_demo.gif    — 歩いて話しかけて発言を読む
//   gallery/correct_demo.gif — 正直者を信じて「せいかい！」→ 次のへやへ
//   gallery/wrong_demo.gif   — 嘘つきを信じて「はずれ…」（シェイク）→ やり直し
//   gallery/memo_demo.gif    — すいりメモに 3 人ぶんのしるしを付ける
//   gallery/index.html       — 上記すべてを見せる SnapshotSite ダッシュボード
mod GameGallery {
    import java.io.File

    def ttfPath(): String = "assets/PixelMplus10-Regular.ttf"
    def design(): Vec2.Vec2 = {x = 320.0, y = 240.0}

    /// 2 倍のピクセル: Retina でくっきり、ファイルはそれでも小さい。
    def scale(): Int32 = 2

    def gifFrameDelayMs(): Int32 = 30

    /// GIF はシミュレーションフレームの 2 つおき（64Hz → 約 33ms/コマ）。
    def gifSampleStride(): Int32 = 2

    /// GIF の 1 コマ実ピクセル寸法（design 320×240 × scale 2）とコマ送りの fps。
    def gifFrameW(): Int32 = 640
    def gifFrameH(): Int32 = 480
    def gifFps(): Int32 = 33

    // ── 1 フレーム、ランチャーが組み立てるのとまったく同じように ──

    def scene(atlas: FontAtlas, ui: UiStore.UiWorld, w: Room.World):
            {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]} =
        let ui1 = GameUi.projectUi(w, ui);
        let (drawables, polygons) = Render.draw(View.compose(atlas, { ui = ui1, world = w }));
        { drawables = drawables, polygons = polygons }

    def rasterReq(atlas: FontAtlas,
                  sc: {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]},
                  path: String): SoftRaster.RasterReq =
        { drawables = sc#drawables, polygons = sc#polygons,
          design = design(), scale = scale(), background = Palette.clearColor(),
          texturePath = Map.empty(), fontTtf = ttfPath(), fontAtlas = atlas,
          outPath = path }

    def shot(atlas: FontAtlas, ui: UiStore.UiWorld, w: Room.World, path: String): Unit \ IO =
        SoftRaster.render(rasterReq(atlas, scene(atlas, ui, w), path))

    // ── 見せたい瞬間の World たち（TestViewGuards と同じ作り方）──

    /// 撮影の舞台はシード 1 に固定する（タイトル経由の entropy くじ引きだと絵が揺れる）。
    def stage1(): Room.World =
        Room.stageWorld(1, Map.empty(), 1i64)

    /// NPC1 の発言を全文まで送った状態。
    def talking(): Room.World =
        stage1()
            |> Trace.facingNpcBelow(1)
            |> Trace.step(Trace.talkTap())
            |> Trace.step(Trace.talkTap())

    /// メモが全員ぶん正解で埋まって開いている状態（提出プロンプトが点灯した回答画面）。
    def answerShot(): Room.World =
        let Room.World.World(s) = stage1();
        Room.World.World(Room.debugFillMemo({ memoOpen = true | s }))

    /// 全員「うそ」の間違った回答を提出した直後（はずれパネル）。
    def wrongShot(): Room.World =
        stage1()
            |> Trace.step(Trace.memoTap())
            |> Trace.step(Trace.talkTap())
            |> Trace.step(Trace.downOnce()) |> Trace.step(Trace.talkTap())
            |> Trace.step(Trace.downOnce()) |> Trace.step(Trace.talkTap())
            |> Trace.step(Trace.enterTap())

    /// 正解を提出した直後（せいかいパネル）。
    def clearedShot(): Room.World =
        answerShot() |> Trace.step(Trace.enterTap())

    /// M でヒントを使った直後（メモが開き、確定した嘘つきにカーソルと「うそ」が付く）。
    def hintShot(): Room.World =
        stage1() |> Trace.step(Trace.hintTap())

    def bakeScreens(atlas: FontAtlas, ui: UiStore.UiWorld): Unit \ IO =
        shot(atlas, ui, Room.titleWorld(), "gallery/screen_title.png");
        shot(atlas, ui, stage1(), "gallery/screen_room.png");
        shot(atlas, ui, talking(), "gallery/screen_talk.png");
        shot(atlas, ui, stage1() |> Trace.step(Trace.memoTap()) |> Trace.step(Trace.talkTap()),
             "gallery/screen_memo.png");
        shot(atlas, ui, hintShot(), "gallery/screen_hint.png");
        shot(atlas, ui, answerShot(), "gallery/screen_answer.png");
        shot(atlas, ui, wrongShot(), "gallery/screen_wrong.png");
        shot(atlas, ui, clearedShot(), "gallery/screen_clear.png")

    // ── 入力の台本 ──

    def hold(input: Room.Input, n: Int32): List[Room.Input] =
        List.range(0, n) |> List.map(_ -> input)

    def tap(input: Room.Input): List[Room.Input] = hold(input, 1)

    def upHold(n: Int32): List[Room.Input] = hold({ up = true | Room.noKeys() }, n)

    /// 歩いて NPC1 の前へ行き、話しかけて発言を読む（読み終わりの余韻まで）。
    def talkScript(): List[Room.Input] =
        List.flatten(
            hold(Trace.rightHold(), 24) ::
            upHold(16) ::
            tap(Trace.talkTap()) ::
            hold(Room.noKeys(), 70) ::
            tap(Trace.talkTap()) ::
            hold(Room.noKeys(), 30) :: Nil)

    /// メモを開いてカーソルを送りながらマークを打つ共通部品（tap の間に見せ場の間を挟む）。
    def markTap(taps: Int32): List[Room.Input] =
        List.flatten(List.range(0, taps) |> List.map(_ ->
            List.flatten(tap(Trace.talkTap()) :: hold(Room.noKeys(), 10) :: Nil)))

    def nextRow(): List[Room.Input] =
        List.flatten(tap(Trace.downOnce()) :: hold(Room.noKeys(), 8) :: Nil)

    /// 正解デモ: メモを開き、あお=ほんと・みどり=うそ・あか=ほんと と書いて Enter で提出
    /// →「せいかい！」→ Enter で次のへやへ。
    def correctScript(): List[Room.Input] =
        List.flatten(
            hold(Room.noKeys(), 12) ::
            tap(Trace.memoTap()) ::
            hold(Room.noKeys(), 20) ::
            markTap(2) :: nextRow() ::
            markTap(1) :: nextRow() ::
            markTap(2) ::
            hold(Room.noKeys(), 20) ::
            tap(Trace.enterTap()) ::
            hold(Room.noKeys(), 60) ::
            tap(Trace.enterTap()) ::
            hold(Room.noKeys(), 40) :: Nil)

    /// 不正解デモ: 全員「うそ」の回答を提出 →「はずれ…」（シェイク）→ やり直し。
    def wrongScript(): List[Room.Input] =
        List.flatten(
            hold(Room.noKeys(), 12) ::
            tap(Trace.memoTap()) ::
            hold(Room.noKeys(), 20) ::
            markTap(1) :: nextRow() ::
            markTap(1) :: nextRow() ::
            markTap(1) ::
            hold(Room.noKeys(), 20) ::
            tap(Trace.enterTap()) ::
            hold(Room.noKeys(), 60) ::
            tap(Trace.enterTap()) ::
            hold(Room.noKeys(), 40) :: Nil)

    /// ヒントデモ: M でヒント → メモが開いて嘘つき 1 人に「うそ」が付く → 閉じると
    /// 頭上に赤い×が残る。
    def hintScript(): List[Room.Input] =
        List.flatten(
            hold(Room.noKeys(), 12) ::
            tap(Trace.hintTap()) ::
            hold(Room.noKeys(), 70) ::
            tap(Trace.memoTap()) ::
            hold(Room.noKeys(), 45) :: Nil)

    /// メモデモ: すいりメモを開き、3 人にしるしを付けて閉じる（頭上に印が残る）。
    def memoScript(): List[Room.Input] =
        List.flatten(
            hold(Room.noKeys(), 10) ::
            tap(Trace.memoTap()) ::
            hold(Room.noKeys(), 20) ::
            tap(Trace.talkTap()) ::            // あお: うそ
            hold(Room.noKeys(), 20) ::
            tap(Trace.downOnce()) ::
            hold(Room.noKeys(), 12) ::
            tap(Trace.talkTap()) ::
            tap(Trace.talkTap()) ::            // みどり: ほんと
            hold(Room.noKeys(), 20) ::
            tap(Trace.downOnce()) ::
            hold(Room.noKeys(), 12) ::
            tap(Trace.talkTap()) ::            // あか: うそ
            hold(Room.noKeys(), 24) ::
            tap(Trace.memoTap()) ::
            hold(Room.noKeys(), 40) :: Nil)

    /// 台本を tick に流して各フレームの World を集める（先頭は開始時点）。
    def worldsOf(inputs: List[Room.Input], start: Room.World): List[Room.World] =
        let (frames, _) = inputs |> List.foldLeft((acc, input) -> {
            let (collected, w) = acc;
            let next = Trace.step(input, w);
            (next :: collected, next)
        }, (start :: Nil, start));
        List.reverse(frames)

    def everyNth(n: Int32, xs: List[a]): List[a] =
        xs |> List.zipWithIndex |> List.filterMap(pair -> {
            let (i, x) = pair;
            if (Int32.modulo(i, n) == 0) Some(x) else None
        })

    /// GIF 1 本とコマ送りビューア用のコマ別 PNG を焼き、ビューアのメタデータを返す。
    def bakeGif(atlas: FontAtlas, ui: UiStore.UiWorld, script: List[Room.Input],
                name: String): (String, SnapshotSite.Filmstrip) \ IO =
        let path = "gallery/${name}.gif";
        let frames = worldsOf(script, stage1())
            |> everyNth(gifSampleStride())
            |> List.map(w -> SoftRaster.renderToImage(rasterReq(atlas, scene(atlas, ui, w), path)));
        GifEncoder.encode(frames, gifFrameDelayMs(), path);
        discard Filmstrip.bakeFrames(frames, "gallery/frames/${name}");
        (name, { strip = "frames/${name}/", frameCount = List.length(frames),
                 frameW = gifFrameW(), frameH = gifFrameH(), fps = gifFps() })

    // ── ダッシュボード ──

    def item(name: String, desc: String, scenario: String, ext: String,
             pxWidth: Int32): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = ext,
          pxWidth = pxWidth, generateHint = Some("run `make bake` to generate"),
          lint = SnapshotSite.noLint(), filmstrip = SnapshotSite.noFilmstrip() }

    def catalog(): List[SnapshotSite.Item] =
        item("screen_title", "タイトル — すべて ui.json の Spec", "Screens", "png", 640) ::
        item("screen_room", "ステージ 1 の部屋（探索中）", "Screens", "png", 640) ::
        item("screen_talk", "発言ウィンドウ（全文表示）", "Screens", "png", 640) ::
        item("screen_answer", "回答用紙が埋まり「こたえあわせ」が点灯した瞬間", "Screens", "png", 640) ::
        item("screen_memo", "すいりメモ（しるし 1 つ + 頭上の印）", "Screens", "png", 640) ::
        item("screen_hint", "ヒント（M）で嘘つき 1 人が確定した瞬間", "Screens", "png", 640) ::
        item("screen_wrong", "はずれ… のパネル", "Screens", "png", 640) ::
        item("screen_clear", "せいかい！ のパネル", "Screens", "png", 640) ::
        item("talk_demo", "歩いて話しかけて発言を読む", "Play", "gif", 640) ::
        item("correct_demo", "メモに正解を書いて提出 → せいかい！ → 次のへやへ", "Play", "gif", 640) ::
        item("wrong_demo", "全員「うそ」で提出 → ブブー（シェイク）→ やり直し", "Play", "gif", 640) ::
        item("memo_demo", "すいりメモに 3 人ぶんのしるしを付ける", "Play", "gif", 640) ::
        item("hint_demo", "M のヒントで嘘つきが 1 人確定 → 頭上に赤い×が残る", "Play", "gif", 640) ::
        item("people", "NPC 7 色 + プレイヤー × 4 方向（静止ポーズ）", "People", "png", 1152) ::
        item("people_walk", "歩行サイクル、全員そろって行進", "People", "gif", 1152) :: Nil

    /// lint バッジとフィルムストリップ情報を名前で差し込んだカタログ。
    def decorate(lintByName: Map[String, SnapshotSite.LintBadge],
                 fsByName: Map[String, SnapshotSite.Filmstrip]): List[SnapshotSite.Item] =
        catalog() |> List.map(entry ->
            { lint = Option.getWithDefault(SnapshotSite.noLint(), Map.get(entry#name, lintByName)),
              filmstrip = Map.get(entry#name, fsByName) | entry })

    /// 撮影と同じ projectUi でページをめくった UiWorld を lint の検査入力へ射影する
    /// （バッジ表示用。違反で fail させる検査は test/TestViewGuards の仕事）。
    def lintInput(name: String, atlas: FontAtlas, ui: UiStore.UiWorld,
                  w: Room.World): RenderLint.Input =
        LiarsLint.buildInput(
            { sceneName = name, allow = Nil, screen = design(), atlas = atlas },
            GameUi.projectUi(w, ui))

    /// すべてを、必ずこの順序で焼き込む: まずスクリーンショットとフィルム、最後にサイト
    /// —— 単発の `make bake` が常に完全なダッシュボードを残すため。
    pub def bakeAll(): Unit \ IO =
        let atlas = Harness.atlas();
        let ui = Harness.ui();
        discard (new File("gallery")).mkdirs();
        bakeScreens(atlas, ui);
        let fs1 = bakeGif(atlas, ui, talkScript(), "talk_demo");
        let fs2 = bakeGif(atlas, ui, correctScript(), "correct_demo");
        let fs3 = bakeGif(atlas, ui, wrongScript(), "wrong_demo");
        let fs4 = bakeGif(atlas, ui, memoScript(), "memo_demo");
        let fs5 = bakeGif(atlas, ui, hintScript(), "hint_demo");
        let titleFindings = RenderLint.check(lintInput("screen_title", atlas, ui, Room.titleWorld()));
        let talkFindings = RenderLint.check(lintInput("screen_talk", atlas, ui, talking()));
        let clearFindings = RenderLint.check(lintInput("screen_clear", atlas, ui, clearedShot()));
        run {
            SnapshotSite.generate(
                { outDir = "gallery", title = "Liars' Room Gallery", cssScale = 2 },
                decorate(
                    Map#{
                        "screen_title" => LiarsLint.badgeOf(titleFindings),
                        "screen_talk" => LiarsLint.badgeOf(talkFindings),
                        "screen_clear" => LiarsLint.badgeOf(clearFindings)
                    },
                    List.toMap(fs1 :: fs2 :: fs3 :: fs4 :: fs5 :: Nil)))
        } with Fs.FileWrite.runWithIO
}
