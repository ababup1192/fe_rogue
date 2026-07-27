// Bake — ゲーム画面を画面なしで PNG に焼く（golden 比較・目視批評用）。
// 実行: flix run --entrypoint Bake.all → gallery/title.png .. gallery/s3_last.png
// すべて t（実時間）に依存しない決定的な場面。World を直接組み、実機と同じ描画経路
// （View.frame → Render.draw → Bakery.renderPng）で焼く。
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
        let cfg = cfgOf("gallery", atlas, w0#theme#grass);
        let ctx = App.viewCtxOf(atlas, design());
        // title: ジャンルカードの顔（Title 画面）。Studio が golden/title.png を /genesis/title で
        // 読み、「レース」の札のサムネにする（各 starter 共通の規約）。
        let t = shoot(cfg, ctx, w0, "title");
        // s1: 走行中盤（コースが流れ・ライバルが前方に見え・抜いた瞬間の閃光が出ている）。
        let s1 = shoot(cfg, ctx, raceScene(w0), "s1_race");
        // s2: FINISH（WIN）の幕。
        let s2 = shoot(cfg, ctx, finishScene(w0), "s2_finish");
        // s3: 最後尾で走っている場面（負けかけ = ライバル全員が前）。
        let s3 = shoot(cfg, ctx, lastScene(w0), "s3_last");
        t :: s1 :: s2 :: s3 :: Nil

    // ── 決定的な場面の脚本（乱数を回さず World を直接組む） ──

    /// 走行中盤: コースを 2 段ぶん進め、ライバル 1 台を抜いた直後（閃光あり・rank 2）にする。
    def raceScene(w0: World.World): World.World =
        let started = World.startGame(w0);
        // 距離を 2.4 段ぶん進める（行内の端数でコースが少しずれて流れて見える）。
        let dist = World.rowPitch() * 2.4;
        // ライバル A は後ろ（抜いた・passed）、B は前方に残す。
        let rivals = started#rivals |> List.zipWithIndex |> List.map(entry -> {
            let (i, r) = entry;
            if (i == 0) { progress = dist - 30.0, passed = true | r }   // 抜いた（後ろ）
            else        { progress = dist + 60.0 | r }                  // まだ前方
        });
        { phase = World.Phase.Racing, distance = dist, playerX = 130.0,
          rivals = rivals, rank = 2, score = 300, passFlash = World.flashDuration() | started }

    /// FINISH（WIN）の幕。totalLaps 周を走り切って 1 位でゴール。
    def finishScene(w0: World.World): World.World =
        let started = World.startGame(w0);
        { phase = World.Phase.Finish, lap = w0#rules#totalLaps, rank = 1,
          score = 2 * w0#rules#scorePerPass + w0#rules#finishBonus,
          rivals = Nil | started }

    /// 最後尾で走っている場面（負けかけ）。ライバル 2 台が前方、rank は最後尾。
    def lastScene(w0: World.World): World.World =
        let started = World.startGame(w0);
        let dist = World.rowPitch() * 1.0;
        let rivals = started#rivals |> List.map(r -> { progress = dist + 120.0 | r });
        { phase = World.Phase.Racing, distance = dist, playerX = 96.0,
          rivals = rivals, rank = 3, score = 0 | started }

    /// 1 場面を PNG に焼き、焼けたファイルパスを返す。
    def shoot(cfg: Bakery.BakeConfig, ctx: App.ViewCtx, w: World.World, name: String): String \ IO =
        let items = View.frame(ctx, w);
        let (drawables, polygons) = Render.draw(items);
        Bakery.renderPng(cfg, drawables, polygons, name);
        let path = "${cfg#outDir}/${name}.png";
        println("baked: ${path}");
        path
}
