// Bake — ゲーム画面を画面なしで PNG に焼く（golden 比較・目視批評用）。
// 実行: flix run --entrypoint Bake.all → gallery/title.png .. gallery/s3_result.png
// すべて t（実時間）に依存しない決定的な場面。World を直接組み（乱数を回さず固定し）、
// 実機と同じ描画経路（View.frame → Render.draw → Bakery.renderPng）で焼く。
mod Bake {
    import java.io.File

    def design(): Vec2.Vec2 = { x = 320.0, y = 360.0 }

    def ttf(): String = "assets/PixelMplus10-Regular.ttf"

    def cfgOf(outDir: String, atlas: FontAtlas, bg: Color): Bakery.BakeConfig =
        { design = design(), scale = 2, background = bg,
          texturePath = Map.empty(), fontTtf = ttf(), fontAtlas = atlas,
          outDir = outDir, frameW = 640, frameH = 720, gifDelayMs = 66, gifFps = 15 }

    def loadWorld(): World.World \ IO =
        run { World.initial(Controls.loadDocs()) } with Fs.FileRead.runWithIO

    pub def all(): Unit \ IO =
        discard allShots()

    /// Bake.all の中身。焼けた PNG のパス列を返す — 走行中のゲームへの POST /bake も呼ぶ。
    pub def allShots(): List[String] \ IO =
        discard (new File("gallery")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let w0 = loadWorld();
        let cfg = cfgOf("gallery", atlas, w0#theme#bg);
        let ctx = { atlas = atlas, visible = { position = Vec2.zero(), size = design() } };
        // title: ジャンルカードの顔（Title 画面）。Studio が golden/title.png を /genesis/title で
        // 読み、「育成」の札のサムネにする（各 starter 共通の規約）。
        let t = shoot(cfg, ctx, w0, "title");
        // s1: 今日の行動を選んでいる（メニューにカーソル・棒が少し育っている）。
        let s1 = shoot(cfg, ctx, dayScene(w0), "s1_day");
        // s2: 決めた直後の見せ物（伸び + イベント文 + きらめき）。
        let s2 = shoot(cfg, ctx, revealScene(w0), "s2_reveal");
        // s3: 発表会の結末。
        let s3 = shoot(cfg, ctx, resultScene(w0), "s3_result");
        t :: s1 :: s2 :: s3 :: Nil

    // ── 決定的な場面の脚本（乱数を回さず World を直接組む） ──

    /// 育ちの途中の値（3 日ぶんくらい伸びた想定）。棒に長さが出るように決め打ちする。
    def midStats(): PlanDoc.Stats = { power = 18, spirit = 22, skill = 30 }

    /// 今日のメニュー: 3 日目、2 番目の行動（きんとれ）にカーソルを当てた画面。
    def dayScene(w0: World.World): World.World =
        { phase = World.Phase.Day, day = 2, cursor = 1, stats = midStats() | w0 }

    /// 見せ物: れんしゅう（0 番）を決めた直後、ちょうし good イベントが起きた画面。
    /// lastGain は行動の伸び、lastEvent は plan の 0 番のイベント。
    def revealScene(w0: World.World): World.World =
        let action = PlanDoc.actionAt(0, w0#plan);
        let event = List.head(w0#plan#events);
        { phase = World.Phase.Reveal, day = 2, stats = midStats(),
          lastGain = action#gain, lastEvent = event | w0 }

    /// 発表会: しっかり育った合計値（一番上の結末に届く想定）で結果を出す画面。
    def resultScene(w0: World.World): World.World =
        { phase = World.Phase.Result, day = w0#rules#dayCount,
          stats = { power = 55, spirit = 48, skill = 60 } | w0 }

    /// 1 場面を PNG に焼き、焼けたファイルパスを返す。
    def shoot(cfg: Bakery.BakeConfig, ctx: App.ViewCtx, w: World.World, name: String): String \ IO =
        let items = View.frame(ctx, w);
        let (drawables, polygons) = Render.draw(items);
        Bakery.renderPng(cfg, drawables, polygons, name);
        let path = "${cfg#outDir}/${name}.png";
        println("baked: ${path}");
        path
}
