// SceneRender — ゲーム画面を画面なしで PNG に生成する（スナップショット比較・目視批評用）。
// 実行: flix run --entrypoint SceneRender.all → gallery/s1_start.png .. s4_over.png
// すべて決定的な場面（時計 t は場面ごとに固定値を入れる）。World を直接組み（RNG を回さず固定し）、
// 実機と同じ描画経路（View.frame → Render.draw → HeadlessRender.renderPng）で生成する。
mod SceneRender {
    import java.io.File

    def design(): Vec2.Vec2 = { x = 256.0, y = 352.0 }

    def ttf(): String = "assets/Xolonium-Regular.ttf"

    def cfgOf(outDir: String, atlas: FontAtlas, bg: Color): HeadlessRender.RenderConfig =
        { design = design(), scale = 2, background = bg,
          texturePath = Map.empty(), fontTtf = ttf(), fontAtlas = atlas,
          outDir = outDir, frameW = 512, frameH = 704, gifDelayMs = 66, gifFps = 15 }

    def loadWorld(): World.World \ IO =
        run { World.initial(Controls.loadDocs()) } with Fs.FileRead.runWithIO

    pub def all(): Unit \ IO =
        discard allShots()

    /// SceneRender.all の中身。生成した PNG のパス列を返す — 走行中のゲームへの POST /render も呼ぶ。
    pub def allShots(): List[String] \ IO =
        discard (new File("gallery")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let w0 = loadWorld();
        let cfg = cfgOf("gallery", atlas, w0#theme#bg);
        let ctx = App.viewCtxOf(atlas, design());
        // title: ジャンルカードの顔（彩り豊かな中盤の一枚）。Studio が reference/title.png を
        // /genesis/title で読み、「パズル」のジャンルカードのサムネイルにする（各 starter 共通の規約）。
        let t = shoot(cfg, ctx, stackScene(w0), "title");
        // s1: 初期盤（空）+ 涌いたばかりの current + NEXT + score 0。
        let s1 = shoot(cfg, ctx, { t = 0.4 | w0 }, "s1_start");
        // s2: 積み上がった中盤 + 落下中のミノ + ゴースト。
        let s2 = shoot(cfg, ctx, stackScene(w0), "s2_stack");
        // s3: ライン消しの演出中（下 2 行が満杯・演出の途中で固定）。
        let s3 = shoot(cfg, ctx, clearScene(w0), "s3_clear");
        // s4: GAME OVER の幕。
        let s4 = shoot(cfg, ctx, overScene(w0), "s4_over");
        t :: s1 :: s2 :: s3 :: s4 :: Nil

    // ── 決定的な場面の脚本（RNG を回さず board を直接組む） ──

    /// 下のほうに凸凹の山を積み、落下中の T ミノを中空に置いた中盤。ゴーストも出る。
    def stackScene(w0: World.World): World.World =
        // 各列の「山の高さ」（下から何段積むか）。決定的な凸凹。
        let heights = 4 :: 6 :: 5 :: 3 :: 2 :: 4 :: 5 :: 6 :: 3 :: 1 :: Nil;
        let board = heights |> List.zipWithIndex |> List.foldLeft((b, entry) -> {
            let (c, h) = entry;
            List.range(0, h) |> List.foldLeft((b2, k) -> {
                let r = World.rows() - 1 - k;
                Map.insert((c, r), stackKind(c + k), b2)   // 色は決定的にばらす
            }, b)
        }, Map.empty());
        { board = board,
          current = { kind = World.Kind.T, rot = 0, col = 4, row = 3 },
          nextKind = World.Kind.L, phase = World.Phase.Playing, t = 1.1 | w0 }

    /// ライン消しの演出中。下 2 行を満杯にして固定し、演出を途中（40%）で止める。
    def clearScene(w0: World.World): World.World =
        let bottom = World.rows() - 1;
        let full = (bottom :: (bottom - 1) :: Nil) |> List.foldLeft((b, r) ->
            List.range(0, World.cols()) |> List.foldLeft((b2, c) ->
                Map.insert((c, r), clearKind(c), b2), b), Map.empty());
        // その上に少し土台を残す（消える行の上に積みがある状態を見せる）。
        let withTower = List.range(0, 4) |> List.foldLeft((b, c) ->
            Map.insert((c, bottom - 2), World.Kind.J, b), full);
        { board = withTower, phase = World.Phase.Clearing,
          clearRows = bottom :: (bottom - 1) :: Nil,
          clearTimer = w0#doc#clearDuration * 0.4, t = 2.6 | w0 }

    /// GAME OVER の幕。盤を上まで積んで overlay を写す。
    def overScene(w0: World.World): World.World =
        let board = List.range(0, World.rows()) |> List.foldLeft((b, r) ->
            List.range(0, World.cols()) |> List.foldLeft((b2, c) ->
                // まばらに空けて「積み上がった山」らしく（全面ベタ塗りにしない）。
                if (Int32.modulo(c + r, 5) == 0) b2 else Map.insert((c, r), overKind(c, r), b2), b),
            Map.empty());
        { board = board, phase = World.Phase.GameOver, score = 4200, lines = 24, t = 5.0 | w0 }

    // ── セルの色を決定的にばらす小物（種類 = 色。7 種を順に舐める） ──
    def kindAt(i: Int32): World.Kind =
        List.drop(Int32.modulo(Int32.abs(i), 7), Pieces.all()) |> List.head
            |> Option.getWithDefault(World.Kind.I)
    def stackKind(i: Int32): World.Kind = kindAt(i)
    def clearKind(i: Int32): World.Kind = kindAt(i + 2)
    def overKind(c: Int32, r: Int32): World.Kind = kindAt(c * 3 + r)

    /// 1 場面を PNG に生成し、生成したファイルパスを返す。hud の合流は実機と同じ
    /// App.composeScene を通す（カメラ無しなので center = None・等倍）。
    def shoot(cfg: HeadlessRender.RenderConfig, ctx: App.ViewCtx, w: World.World, name: String): String \ IO =
        let items = App.composeScene(None, 1.0, cfg#design,
            { world = View.frame(ctx, w), hud = View.hud(ctx, w) });
        let (drawables, polygons) = Render.draw(items);
        HeadlessRender.renderPng(cfg, drawables, polygons, name);
        let path = "${cfg#outDir}/${name}.png";
        println("rendered: ${path}");
        path
}
