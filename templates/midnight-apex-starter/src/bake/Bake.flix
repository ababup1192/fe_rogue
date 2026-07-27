// Bake — 実機と同じ View.frame を使い、主要場面を決定的な PNG へ焼く。
mod Bake {
    import java.io.File

    /// ゲームと同じ設計解像度。
    def design(): Vec2.Vec2 =
        { x = World.designWidth(), y = World.designHeight() }

    /// UI に使うフォント。
    def fontPath(): String = "assets/Xolonium-Regular.ttf"

    /// 出力先だけを変えられる焼成設定。
    def config(outDir: String, atlas: FontAtlas, background: Color): Bakery.BakeConfig =
        { design = design(),
          scale = 3,
          background = background,
          texturePath = Map.empty(),
          fontTtf = fontPath(),
          fontAtlas = atlas,
          outDir = outDir,
          frameW = 960,
          frameH = 720,
          gifDelayMs = 66,
          gifFps = 15 }

    /// 実行時と同じ Doc 一式から表紙を作る。
    def loadWorld(): World.World \ IO =
        run { World.initial(Controls.loadDocs()) } with Fs.FileRead.runWithIO

    /// コマンドライン用の入口。
    pub def all(): Unit \ IO =
        SfxBake.bakeAll();
        discard allShots()

    /// Studio の POST /bake からも呼べるよう、焼いたパスを順番どおり返す。
    pub def allShots(): List[String] \ IO =
        discard (new File("gallery")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(fontPath(), fontPath());
        let initial = loadWorld();
        let bakeConfig = config("gallery", atlas, initial#theme#night);
        let context = App.viewCtxOf(atlas, design());
        shoot(bakeConfig, context, initial, "title")
            :: shoot(bakeConfig, context, countdownScene(initial), "countdown")
            :: shoot(bakeConfig, context, roadScene(initial), "race_boost")
            :: shoot(bakeConfig, context, panoramaLeftScene(initial), "panorama_left")
            :: shoot(bakeConfig, context, panoramaRightScene(initial), "panorama_right")
            :: shoot(bakeConfig, context, offRoadScene(initial), "race_offroad")
            :: shoot(bakeConfig, context, checkpointScene(initial), "checkpoint")
            :: shoot(bakeConfig, context, skyBridgeScene(initial), "sky_bridge")
            :: shoot(bakeConfig, context, jumpScene(initial), "race_jump")
            :: shoot(bakeConfig, context, wallBounceScene(initial), "wall_bounce")
            :: shoot(bakeConfig, context, crashScene(initial), "crash")
            :: shoot(bakeConfig, context, gameOverScene(initial), "game_over")
            :: shoot(bakeConfig, context, finishScene(initial), "finish")
            :: Nil

    /// 開始直前の大数字とスタートグリッド。
    def countdownScene(initial: World.World): World.World =
        let countdown = World.step(
            { deltaTime = 0.0, input = { confirm = true | World.noInput() } }, initial);
        World.step({ deltaTime = 0.7, input = World.noInput() }, countdown)

    /// 幅広い区間でブーストし、ライバル2台を追う場面。
    def roadScene(initial: World.World): World.World =
        let progress = Course.rowDistance() * 1.4;
        let road = Course.sample(
            { totalProgress = progress, screenWidth = World.designWidth() }, initial#course);
        let rivals =
            { totalProgress = progress + 92.0, laneOffset = -0.24,
              cruiseSpeed = initial#tuning#rivalSpeedA, passed = false }
            :: { totalProgress = progress + 155.0, laneOffset = 0.24,
                 cruiseSpeed = initial#tuning#rivalSpeedB, passed = false }
            :: Nil;
        { phase = World.Phase.Racing,
          playerX = road#centerX,
          speed = initial#tuning#boostMaxSpeed * 0.92,
          totalProgress = progress,
          elapsedTime = 8.4,
          rank = 3,
          rivals = rivals,
          energy = World.maxEnergy() * 0.64,
          boosting = true,
          onRoad = true | initial }

    /// 同じ場所で左へ寄った時の、循環する夜景と層ごとの移動差を残す。
    def panoramaLeftScene(initial: World.World): World.World =
        { playerX = 86.0, steering = -1.0 | roadScene(initial) }

    /// 左向き場面と同じ進行距離で右へ寄り、背景が反対へ流れることを残す。
    def panoramaRightScene(initial: World.World): World.World =
        { playerX = 234.0, steering = 1.0 | roadScene(initial) }

    /// 細いS字で路肩を越え、減速警告が出ている場面。
    def offRoadScene(initial: World.World): World.World =
        let progress = Course.rowDistance() * 14.6;
        let road = Course.sample(
            { totalProgress = progress, screenWidth = World.designWidth() }, initial#course);
        { phase = World.Phase.Racing,
          playerX = road#centerX + road#width / 2.0 + World.carWidth(),
          speed = initial#tuning#offRoadMaxSpeed,
          totalProgress = progress,
          elapsedTime = 16.2,
          rank = 2,
          rivals = initial#rivals,
          boosting = false,
          onRoad = false | initial }

    /// ネオンゲートを通過した直後の光と区間表示。
    def checkpointScene(initial: World.World): World.World =
        let progress = Course.lapLength(initial#course) * 0.57;
        let road = Course.sample(
            { totalProgress = progress, screenWidth = World.designWidth() }, initial#course);
        { phase = World.Phase.Racing,
          playerX = road#centerX,
          speed = initial#tuning#maxSpeed * 0.72,
          totalProgress = progress,
          elapsedTime = 25.7,
          rank = 2,
          sector = Course.sectorIndex(progress, initial#course),
          gateFlash = 0.48,
          boosting = false,
          onRoad = true | initial }

    /// 都市影が消え、細い空中橋と路肩ビーコンだけになる区間。
    def skyBridgeScene(initial: World.World): World.World =
        let progress = Course.rowDistance() * 44.8;
        let road = Course.sample(
            { totalProgress = progress, screenWidth = World.designWidth() }, initial#course);
        { phase = World.Phase.Racing,
          playerX = road#centerX,
          speed = initial#tuning#maxSpeed * 0.78,
          totalProgress = progress,
          elapsedTime = 35.6,
          rank = 2,
          sector = Course.sectorIndex(progress, initial#course),
          energy = World.maxEnergy() * 0.38,
          boosting = false,
          onRoad = true | initial }

    /// ジャンプの最高点で、影と機体の距離、傾き、バーナーを同時に見せる。
    def jumpScene(initial: World.World): World.World =
        let progress = Course.rowDistance() * 16.35;
        let road = Course.sample(
            { totalProgress = progress, screenWidth = World.designWidth() },
            initial#course);
        let jump = TimedHop.grounded()
            |> TimedHop.start(initial#tuning#jumpDuration)
            |> TimedHop.step(initial#tuning#jumpDuration / 2.0);
        { phase = World.Phase.Racing,
          playerX = road#centerX,
          speed = initial#tuning#maxSpeed * 0.94,
          totalProgress = progress,
          elapsedTime = 18.4,
          rank = 2,
          jump = jump,
          steering = 0.72,
          throttling = true,
          boosting = false,
          onRoad = true | initial }

    /// 電磁壁に弾かれ、機体が内側へ傾き、エネルギーが減った瞬間。
    def wallBounceScene(initial: World.World): World.World =
        let progress = Course.rowDistance() * 34.2;
        let road = Course.sample(
            { totalProgress = progress, screenWidth = World.designWidth() },
            initial#course);
        { phase = World.Phase.Racing,
          playerX = road#centerX - road#width / 2.0 + World.carWidth() / 2.0,
          speed = initial#tuning#maxSpeed * 0.66,
          totalProgress = progress,
          elapsedTime = 28.9,
          rank = 2,
          energy = World.maxEnergy() * 0.22,
          bounceVelocity = initial#tuning#wallBounceSpeed,
          wallCooldown = 0.48,
          impactFlash = 0.42,
          onRoad = true | initial }

    /// エネルギーが尽き、機体が消えて爆発だけが広がる途中。
    def crashScene(initial: World.World): World.World =
        let progress = Course.rowDistance() * 35.0;
        let road = Course.sample(
            { totalProgress = progress, screenWidth = World.designWidth() },
            initial#course);
        { phase = World.Phase.Crashed,
          playerX = road#centerX,
          speed = 0.0,
          totalProgress = progress,
          elapsedTime = 29.4,
          rank = 2,
          energy = 0.0,
          crashTime = 0.34,
          onRoad = true | initial }

    /// 爆発後に再挑戦を選べる最終状態。
    def gameOverScene(initial: World.World): World.World =
        { phase = World.Phase.GameOver,
          speed = 0.0,
          totalProgress = Course.rowDistance() * 35.0,
          elapsedTime = 29.4,
          rank = 2,
          energy = 0.0,
          crashTime = 0.85 | initial }

    /// 2周を走り切り、順位と時間が凍結した結果画面。
    def finishScene(initial: World.World): World.World =
        let progress = Course.lapLength(initial#course)
            * Int32.toFloat64(initial#tuning#totalLaps);
        let rivals =
            { totalProgress = progress - 80.0, laneOffset = -0.24,
              cruiseSpeed = initial#tuning#rivalSpeedA, passed = true }
            :: { totalProgress = progress - 140.0, laneOffset = 0.24,
                 cruiseSpeed = initial#tuning#rivalSpeedB, passed = true }
            :: Nil;
        { phase = World.Phase.Finish,
          lap = initial#tuning#totalLaps,
          elapsedTime = 47.3,
          rank = 1,
          score = initial#tuning#scorePerPass * 2 + initial#tuning#finishBonus,
          speed = 0.0,
          totalProgress = progress,
          rivals = rivals | initial }

    /// 1場面をPNGへ焼き、出力パスを返す。
    def shoot(bakeConfig: Bakery.BakeConfig, context: App.ViewCtx,
              world: World.World, name: String): String \ IO =
        let items = View.frame(context, world);
        let (drawables, polygons) = Render.draw(items);
        Bakery.renderPng(bakeConfig, drawables, polygons, name);
        let path = "${bakeConfig#outDir}/${name}.png";
        println("baked: ${path}");
        path
}
