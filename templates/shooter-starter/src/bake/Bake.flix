// Bake — ゲーム画面を画面なしで PNG に焼く（golden 比較・目視批評用）。
// 実行: flix run --entrypoint Bake.all → gallery/title.png .. gallery/s4_over.png
// すべて t（実時間）に依存しない決定的な場面。World を直接組み（乱数を回さず固定し）、
// 実機と同じ描画経路（View.frame → Render.draw → Bakery.renderPng）で焼く。
mod Bake {
    import java.io.File

    def design(): Vec2.Vec2 = { x = 240.0, y = 360.0 }

    def ttf(): String = "assets/Xolonium-Regular.ttf"

    def cfgOf(outDir: String, atlas: FontAtlas, bg: Color): Bakery.BakeConfig =
        { design = design(), scale = 2, background = bg,
          texturePath = Map.empty(), fontTtf = ttf(), fontAtlas = atlas,
          outDir = outDir, frameW = 480, frameH = 720, gifDelayMs = 66, gifFps = 15 }

    def loadWorld(): World.World \ IO =
        run { World.initial(Controls.loadDocs()) } with Fs.FileRead.runWithIO

    pub def all(): Unit \ IO =
        discard allShots()

    /// Bake.all の中身。焼けた PNG のパス列を返す — 走行中のゲームへの POST /bake も呼ぶ。
    pub def allShots(): List[String] \ IO =
        discard (new File("gallery")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let w0 = loadWorld();
        let cfg = cfgOf("gallery", atlas, w0#theme#space);
        let ctx = { atlas = atlas, visible = { position = Vec2.zero(), size = design() } };
        // title: ジャンルカードの顔（Title 画面）。Studio が golden/title.png を /genesis/title で
        // 読み、「シューティング」の札のサムネにする（各 starter 共通の規約）。
        let t = shoot(cfg, ctx, w0, "title");
        // s1: 遊びの中盤（波が降り・弾が飛び・撃破の爆発が出ている）。
        let s1 = shoot(cfg, ctx, playScene(w0), "s1_play");
        // s2: CLEAR の幕。
        let s2 = shoot(cfg, ctx, clearScene(w0), "s2_clear");
        // s3: GAME OVER の幕。
        let s3 = shoot(cfg, ctx, overScene(w0), "s3_over");
        t :: s1 :: s2 :: s3 :: Nil

    // ── 決定的な場面の脚本（乱数を回さず World を直接組む） ──

    /// 遊びの中盤: 3 番目の波（くさび形）を少し降ろし、弾を数発飛ばし、1 体を撃破中にする。
    def playScene(w0: World.World): World.World =
        let started = World.startGame({ waveIndex = 2 | w0 });   // くさび形の波を涌かせる
        // 波を少し降ろす（各敵の y に +40px）。決定的なので t に依存しない。
        let descended = started#enemies |> List.map(e ->
            { pos = { y = e#pos#y + 40.0 | e#pos } | e });
        // 先頭の 1 体を「撃破中（爆発が半分残っている）」にして演出を見せる。
        let withBoom = match descended {
            case top :: rest => { alive = false, boomTimer = 0.09 | top } :: rest
            case Nil         => Nil
        };
        { phase = World.Phase.Playing, waveIndex = 2, score = 1300,
          playerX = 140.0, enemies = withBoom,
          bullets = { x = 120.0, y = 240.0 } :: { x = 150.0, y = 180.0 }
              :: { x = 96.0, y = 300.0 } :: Nil | started }

    /// CLEAR の幕。全波を全滅させて勝った画面。
    def clearScene(w0: World.World): World.World =
        { phase = World.Phase.Clear, score = 4200, enemies = Nil, bullets = Nil | w0 }

    /// GAME OVER の幕。敵が自機まで降りてきて負けた画面。
    def overScene(w0: World.World): World.World =
        let started = World.startGame({ waveIndex = 1 | w0 });
        { phase = World.Phase.GameOver, score = 900,
          playerX = World.designW() / 2.0 | started }

    /// 1 場面を PNG に焼き、焼けたファイルパスを返す。
    def shoot(cfg: Bakery.BakeConfig, ctx: App.ViewCtx, w: World.World, name: String): String \ IO =
        let items = View.frame(ctx, w);
        let (drawables, polygons) = Render.draw(items);
        Bakery.renderPng(cfg, drawables, polygons, name);
        let path = "${cfg#outDir}/${name}.png";
        println("baked: ${path}");
        path
}
