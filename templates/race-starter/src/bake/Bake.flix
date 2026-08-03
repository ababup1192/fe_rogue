// Bake — ゲーム画面を画面なしで PNG に焼く（golden 比較・目視批評用）。
// 実行: flix run --entrypoint Bake.all → gallery/title.png .. gallery/s3_crash.png
// すべて決定的な場面（時計 t は場面ごとに固定値を入れる — 実時間も乱数も見ない）。
// World を直接組み、実機と同じ描画経路（View.frame → Render.draw → Bakery.renderPng）で焼く。
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
    /// 効果音も同じ入口で焼く（絵と音を別の手順にしない）。返すのは目で見る物だけなので
    /// WAV はパス列に載せない。
    pub def allShots(): List[String] \ IO =
        discard (new File("gallery")).mkdirs();
        run { SfxBake.bakeAll() } with Fs.FileRead.runWithIO;
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let w0 = loadWorld();
        let cfg = cfgOf("gallery", atlas, w0#theme#grass);
        let ctx = App.viewCtxOf(atlas, design());
        // title: ジャンルカードの顔（Title 画面）。Studio が golden/title.png を /genesis/title で
        // 読み、「レース」の札のサムネにする（各 starter 共通の規約）。
        let t = shoot(cfg, ctx, { t = 2.2 | w0 }, "title");
        // s1: S 字をドリフト中（タイヤ痕・白煙・ゲージ半分）。この絵が遊びの顔。
        let s1 = shoot(cfg, ctx, driftScene(w0), "s1_drift");
        // s2: 直線でニトロ発動中（炎とスピード感・前方にライバル 1 台）。
        let s2 = shoot(cfg, ctx, nitroScene(w0), "s2_nitro");
        // s3: 障害物に当たった直後（スピン中・閃光と火花）。
        let s3 = shoot(cfg, ctx, crashScene(w0), "s3_crash");
        // s4: 左の U 字の入口（道が巻き込んで画面の外へ消える所）。急カーブの絵の顔。
        let s4 = shoot(cfg, ctx, uturnScene(w0), "s4_uturn");
        // s5: 登りの頂上ぎわで土管ゲートへ差し掛かる所（坂とゲートの絵の顔）。
        let s5 = shoot(cfg, ctx, gateScene(w0), "s5_gate");
        // s6: 左 U 字の外側のガードレールに擦り付けて曲がっている所（火花が散る）。
        let s6 = shoot(cfg, ctx, railScene(w0), "s6_rail");
        // s7: 長い直線の振り子バーが左へ振れきる手前（残った右の隙間を抜けに行く所）。
        let s7 = shoot(cfg, ctx, barScene(w0), "s7_bar");
        t :: s1 :: s2 :: s3 :: s4 :: s5 :: s6 :: s7 :: Nil

    // ── 決定的な場面の脚本（乱数を回さず World を直接組む） ──
    // 立ち位置は「道の中心からの横ずれ（px）」で書く。区間表を差し替えても、
    // 車は道の上の同じ所に乗ったままになる。

    /// 右への切り込み（通し段 22〜24）をドリフト中: 道の中心より外側で車が傾き、
    /// 後ろへタイヤ痕が伸び、白煙が続けて膨らんでいる。ゲージは半分強（貯まっていく途中の絵）。
    def driftScene(w0: World.World): World.World =
        let started = World.startGame(w0);
        let dist = World.rowPitch() * 22.5;
        let pd = dist + World.playerAheadPx();
        let off = 0.0 - 16.0;
        // ライバル 2 台を前方 60px / 130px の道の中心に。残りは後方（抜いた扱い）。
        let rivals = started#rivals |> List.zipWithIndex |> List.map(entry -> {
            let (i, r) = entry;
            if (i == 0)      { progress = pd + 60.0, off = 6.0 | r }
            else if (i == 1) { progress = pd + 130.0, off = 0.0 - 8.0 | r }
            else             { progress = pd - 70.0, off = 0.0, passed = true | r }
        });
        // タイヤ痕: 4px 刻みで後ろへ、外側へ少しずつ流れた跡。
        let skids = List.range(0, 8) |> List.map(i -> {
            let k = Int32.toFloat64(i);
            ({ dist = pd - 4.0 * k, off = off - 1.2 * k, turn = 0.06 }: World.Skid)
        });
        // 白煙: World と同じ 0.09 秒間隔で焚かれた続き物。数を実機の湧き方に合わせないと、
        // ギャラリーの絵だけ煙が薄い（滑っている絵に見えない）。
        let sceneT = 1.7;
        let bursts = List.range(0, 9) |> List.map(i -> {
            let k = Int32.toFloat64(i);
            Fx.burst(w0#fx#smoke, i + 1, { x = off - 5.0 - 1.1 * k, y = pd - 12.0 - 6.0 * k },
                     sceneT - 0.09 * k)
        });
        { phase = World.Phase.Racing, t = sceneT, distance = dist, playerOff = off,
          speed = w0#rules#forwardSpeed, drifting = true, steerDir = 1.0,
          nitro = 0.55, rank = 2, score = 300,
          rivals = rivals, skids = skids, bursts = bursts, fxSeq = 10 | started }

    /// 長い直線（区間 17・通し段 31〜34）でニトロ発動中: 発動から 0.05 秒（衝撃が車から
    /// 離れきる前の一番濃い瞬間）。前方にライバル 1 台。
    /// 炎（loop の fx）は View が nitroLeft を見て毎フレーム描くので bursts には積まない。
    def nitroScene(w0: World.World): World.World =
        let started = World.startGame(w0);
        let dist = World.rowPitch() * 33.4;
        let pd = dist + World.playerAheadPx();
        let rivals = started#rivals |> List.zipWithIndex |> List.map(entry -> {
            let (i, r) = entry;
            if (i == 0) { progress = pd + 70.0, off = 14.0 | r }
            else        { progress = pd - 60.0 - 30.0 * Int32.toFloat64(i), off = 0.0,
                          passed = true | r }
        });
        { phase = World.Phase.Racing, t = 3.4, distance = dist, playerOff = 0.0,
          speed = w0#rules#forwardSpeed * w0#rules#nitroBoost,
          nitroLeft = w0#rules#nitroDuration - 0.05, nitro = 0.0, rank = 2, score = 600,
          rivals = rivals | started }

    /// U 字の手前（通し段 9）でコーンに当たった直後: スピンの残り 0.55 秒。
    /// 閃光と火花が散り、その先には U 字の巻き込みが見えている
    /// （「イン側を攻めて失敗した」が 1 枚で読める場所を選ぶ）。
    def crashScene(w0: World.World): World.World =
        let started = World.startGame(w0);
        let dist = World.rowPitch() * 8.6;
        let pd = dist + World.playerAheadPx();
        let off = 0.0 - 20.0;
        let rivals = started#rivals |> List.zipWithIndex |> List.map(entry -> {
            let (i, r) = entry;
            if (i == 0) { progress = pd - 50.0, off = 0.0, passed = true | r }
            else        { progress = pd + 40.0 + 50.0 * Int32.toFloat64(i), off = 0.0 | r }
        });
        let sceneT = 0.9;
        let bursts =
               Fx.burst(w0#fx#crash, 7, { x = off, y = pd }, sceneT - 0.12)
            :: Fx.burst(w0#fx#spark, 8, { x = off - 6.0, y = pd - 6.0 }, sceneT - 0.10)
            :: Nil;
        { phase = World.Phase.Racing, t = sceneT, distance = dist, playerOff = off,
          speed = w0#rules#forwardSpeed * w0#rules#spinSlow,
          spinLeft = 0.55, rank = 3, score = 300,
          rivals = rivals, bursts = bursts, fxSeq = 9 | started }

    /// 左の U 字（区間 6・通し段 11〜15）へ入っていく所: 幅の絞られた入口を
    /// イン側（左）に付けてドリフト中。道は 2 段先から巻き込んで画面の外へ消える。
    def uturnScene(w0: World.World): World.World =
        let started = World.startGame(w0);
        let dist = World.rowPitch() * 9.4;
        let pd = dist + World.playerAheadPx();
        let off = 0.0 - 18.0;
        let rivals = started#rivals |> List.zipWithIndex |> List.map(entry -> {
            let (i, r) = entry;
            if (i == 0) { progress = pd + 55.0, off = 12.0 | r }
            else        { progress = pd - 40.0 - 40.0 * Int32.toFloat64(i), off = 0.0,
                          passed = true | r }
        });
        let sceneT = 2.6;
        let skids = List.range(0, 8) |> List.map(i -> {
            let k = Int32.toFloat64(i);
            ({ dist = pd - 4.0 * k, off = off + 1.4 * k, turn = 0.0 - 0.06 }: World.Skid)
        });
        let bursts = List.range(0, 9) |> List.map(i -> {
            let k = Int32.toFloat64(i);
            Fx.burst(w0#fx#smoke, i + 1, { x = off + 5.0 + 1.1 * k, y = pd - 12.0 - 6.0 * k },
                     sceneT - 0.09 * k)
        });
        { phase = World.Phase.Racing, t = sceneT, distance = dist, playerOff = off,
          speed = w0#rules#forwardSpeed, drifting = true, steerDir = 0.0 - 1.0,
          nitro = 0.8, rank = 2, score = 900,
          rivals = rivals, skids = skids, bursts = bursts, fxSeq = 20 | started }

    /// 登りの頂上ぎわ（通し段 7）から土管ゲート（通し段 8）へ差し掛かる所。
    /// 道が坂で持ち上がり、その先に隙間 3 レーンのゲートが立っている。
    def gateScene(w0: World.World): World.World =
        let started = World.startGame(w0);
        let dist = World.rowPitch() * 6.2;
        let pd = dist + World.playerAheadPx();
        let rivals = started#rivals |> List.zipWithIndex |> List.map(entry -> {
            let (i, r) = entry;
            if (i == 0) { progress = pd + 85.0, off = 18.0 | r }
            else        { progress = pd - 55.0 - 45.0 * Int32.toFloat64(i), off = 0.0,
                          passed = true | r }
        });
        { phase = World.Phase.Racing, t = 4.1, distance = dist, playerOff = 16.0,
          speed = w0#rules#forwardSpeed, nitro = 0.35, rank = 2, score = 300,
          rivals = rivals | started }

    /// 左 U 字（通し段 12）の外側のガードレールに擦り付けて曲がっている所。
    /// 壁に押し付けたまま曲がると遅いが確実 — その代わり火花が散り、ゲージが貯まる。
    def railScene(w0: World.World): World.World =
        let started = World.startGame(w0);
        let dist = World.rowPitch() * 11.6;
        let pd = dist + World.playerAheadPx();
        let row = World.playerRowOf(dist);
        let off = World.halfWidthAt(row, w0#course);
        let rivals = started#rivals |> List.zipWithIndex |> List.map(entry -> {
            let (i, r) = entry;
            if (i == 0) { progress = pd + 50.0, off = 0.0 - 10.0 | r }
            else        { progress = pd - 45.0 - 45.0 * Int32.toFloat64(i), off = 0.0,
                          passed = true | r }
        });
        let sceneT = 3.3;
        // 火花は World と同じ 0.07 秒間隔で焚かれた続き物（擦っている実感は数で出る）。
        let bursts = List.range(0, 6) |> List.map(i -> {
            let k = Int32.toFloat64(i);
            Fx.burst(w0#fx#spark, i + 30, { x = off, y = pd - 5.0 * k }, sceneT - 0.07 * k)
        });
        { phase = World.Phase.Racing, t = sceneT, distance = dist, playerOff = off,
          speed = w0#rules#forwardSpeed * w0#rules#railScrapeSlow,
          nitro = 0.62, rank = 2, score = 600,
          rivals = rivals, bursts = bursts, fxSeq = 40 | started }

    /// 長い直線（通し段 32）の振り子バーへ差し掛かる所: バーは道の左寄りへ振れていて、
    /// 右に隙間が残っている。自機はその右へ寄せている（避け先が絵で読めるかを見る場面）。
    def barScene(w0: World.World): World.World =
        let started = World.startGame(w0);
        let dist = World.rowPitch() * 30.6;
        let pd = dist + World.playerAheadPx();
        let rivals = started#rivals |> List.zipWithIndex |> List.map(entry -> {
            let (i, r) = entry;
            if (i == 0) { progress = pd + 95.0, off = 0.0 - 6.0 | r }
            else        { progress = pd - 50.0 - 40.0 * Int32.toFloat64(i), off = 0.0,
                          passed = true | r }
        });
        { phase = World.Phase.Racing, t = 2.63, distance = dist, playerOff = 24.0,
          speed = w0#rules#forwardSpeed, nitro = 0.42, rank = 2, score = 750,
          rivals = rivals | started }

    /// 1 場面を PNG に焼き、焼けたファイルパスを返す。
    def shoot(cfg: Bakery.BakeConfig, ctx: App.ViewCtx, w: World.World, name: String): String \ IO =
        let items = View.frame(ctx, w);
        let (drawables, polygons) = Render.draw(items);
        Bakery.renderPng(cfg, drawables, polygons, name);
        let path = "${cfg#outDir}/${name}.png";
        println("baked: ${path}");
        path
}
