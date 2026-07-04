// Game — start と自前 gameLoop（Phase 5: プレイ＋ECS固有 payoff）
//
// scene-tree のパイプラインは使わず、不変 World を System で回す。1 フレーム:
//   入力(start/pause/rewind) → System 連結（pause 中はスキップ）→ phase 立ち上がりで音 → 描画。
// 不変 World ゆえの payoff:
//   - 巻き戻し: World の軌跡を Worldline（engine_world の zipper）に保持し、Z で過去へ遡るだけ
//     （可変状態のノード版には不可能）。past は永続 List の tail 共有ゆえ丸コピーにならない。
//   - 決定論ヘッドレス: runHeadless が seeded Random＋mock Game＋固定 dt で全ループを値として回す。
//   - pause: sim System を呼ばないだけ。
//
// 操作: WASD/矢印=移動、Enter/Space または Start クリック=開始/再開、X=pause、Z=巻き戻し、Esc=終了。

mod Game {

    def rewindFrames(): Int32 = 30
    def maxHistory(): Int32 = 180

    // ── 起動 ──

    pub def start(atlas: FontAtlas): Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random} =
        gameLoop(atlas, GamePhase.Menu, Worldline.make(buildMenuWorld(), maxHistory()))

    /// Menu の初期 World: 標準 HUD entity のみ。player/mob は無し。
    pub def buildMenuWorld(): World =
        let World.World(w) = World.empty();
        World.World({ huds = World.standardHuds() | w })

    // ── メインループ ──

    def gameLoop(atlas: FontAtlas, prevPhase: GamePhase, line: Worldline[World]):
            Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random} =
        if (closing()) ()
        else {
            let curKeys = readControlKeys();
            let World.World(w) = Worldline.current(line);
            if (pressedEdge(GameEngine.Key.Z, curKeys, w#prevKeys) and Worldline.canUndo(line))
                doRewind(atlas, curKeys, line)
            else
                doFrame(atlas, prevPhase, curKeys, line)
        }

    def closing(): Bool \ GameEngine.Game =
        GameEngine.Game.shouldClose() or GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)

    /// Z: 世界線を rewindFrames 段遡る（payoff: 不変ゆえタダ）。履歴が浅ければ最古で止まる。
    def doRewind(atlas: FontAtlas, curKeys: Set[GameEngine.Key], line: Worldline[World]):
            Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random} =
        let line2 = Worldline.undoBy(rewindFrames(), line);
        let target2 = setPrevKeys(curKeys, Worldline.current(line2));
        GameEngine.Game.renderCommands(RenderWorld.renderWorld(target2, atlas), Nil, Nil);
        gameLoop(atlas, World.phaseOf(target2), Worldline.replaceCurrent(target2, line2))

    /// 通常フレーム: 入力 → System → 音 → 描画 → 世界線へ record。
    def doFrame(atlas: FontAtlas, prevPhase: GamePhase, curKeys: Set[GameEngine.Key],
                line: Worldline[World]):
            Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random} =
        let dt = Duration.toSeconds(GameEngine.Game.getDeltaTime());
        let mouseDown = GameEngine.Game.isMouseButtonPressed(GameEngine.MouseButton.Left);
        let mousePos = GameEngine.Game.getMousePosition();
        let controlled = applyControl(curKeys, mouseDown, mousePos, Worldline.current(line));
        let stepped = if (World.isPaused(controlled)) controlled else stepSystems(dt, controlled);
        playPhaseAudio(prevPhase, World.phaseOf(stepped));
        GameEngine.Game.renderCommands(RenderWorld.renderWorld(stepped, atlas), Nil, Nil);
        gameLoop(atlas, World.phaseOf(stepped), Worldline.record(stepped, line))

    /// 純粋＋少数 effect の System を連結する（pause 時は呼ばれない）。
    pub def stepSystems(dt: Float64, world: World): World \ {GameEngine.Game, Math.Random} =
        world
            |> PlayerSystem.playerInputSystem            // 入力 → velocity[player]
            |> MobSystem.spawnSystem(dt)
            |> MobSystem.moveSystem(dt)                  // position を velocity で一律積分
            |> PlayerSystem.clampPlayerSystem            // player の position だけ画面内へ
            |> AnimSystem.animSystem(dt)
            |> MobSystem.despawnOffscreenSystem
            |> CollisionSystem.collisionSystem
            |> PhaseSystem.phaseSystem(dt)

    /// 決定論ヘッドレス実行: render/audio 抜きで System を frames 回す。
    /// seeded Random＋mock Game＋固定 dt を注入すれば「ゲーム全体を値として」再現・検証できる。
    pub def runHeadless(dt: Float64, frames: Int32, world: World): World \ {GameEngine.Game, Math.Random} =
        if (frames <= 0) world
        else runHeadless(dt, frames - 1, stepSystems(dt, world))

    // ── 入力（pure: 読み取りは loop 側、ここはエッジ計算と状態遷移）──

    def applyControl(curKeys: Set[GameEngine.Key], mouseDown: Bool,
                     mousePos: Vec2.Vec2, world: World): World =
        let World.World(w) = world;
        let startKey = pressedEdge(GameEngine.Key.Enter, curKeys, w#prevKeys) or
                       pressedEdge(GameEngine.Key.Space, curKeys, w#prevKeys);
        let clickStart = (mouseDown and not w#prevMouseDown) and buttonHit(mousePos, world);
        let pauseEdge = pressedEdge(GameEngine.Key.X, curKeys, w#prevKeys);
        let afterStart = if ((startKey or clickStart) and canStart(world)) startGame(world) else world;
        let afterPause = togglePause(pauseEdge, afterStart);
        storePrev(curKeys, mouseDown, afterPause)

    def readControlKeys(): Set[GameEngine.Key] \ GameEngine.Game =
        let ks = GameEngine.Key.Enter :: GameEngine.Key.Space ::
                 GameEngine.Key.X :: GameEngine.Key.Z :: Nil;
        List.foldLeft((acc, k) ->
            if (GameEngine.Game.isKeyPressed(k)) Set.insert(k, acc) else acc,
            Set.empty(), ks)

    def pressedEdge(k: GameEngine.Key, cur: Set[GameEngine.Key], prev: Set[GameEngine.Key]): Bool =
        Set.memberOf(k, cur) and not Set.memberOf(k, prev)

    def storePrev(curKeys: Set[GameEngine.Key], mouseDown: Bool, world: World): World =
        let World.World(w) = world;
        World.World({prevKeys = curKeys, prevMouseDown = mouseDown | w})

    def setPrevKeys(curKeys: Set[GameEngine.Key], world: World): World =
        let World.World(w) = world;
        World.World({prevKeys = curKeys | w})

    def togglePause(edge: Bool, world: World): World =
        if (not edge) world
        else {
            let World.World(w) = world;
            World.World({paused = not w#paused | w})
        }

    // ── start 判定とリセット ──

    def canStart(world: World): Bool =
        let World.World(w) = world;
        match w#phase {
            case GamePhase.Menu     => true
            case GamePhase.Playing  => false
            case GamePhase.GameOver => w#timers#gameOverMsg <= 0.0   // メッセージ後（ボタン表示中）
        }

    def startGame(world: World): World =
        let cleared = clearMobs(world);
        let World.World(w) = cleared;
        let base = World.World({
            phase  = GamePhase.Playing, score = 0, player = None, paused = false,
            timers = {mobSpawn = 0.0, score = 0.0, startDelay = 2.0, gameOverMsg = 0.0, title = 0.0}
            | w});
        World.spawnPlayer(PlayerSystem.startPosition(), PlayerSystem.playerRadiusOf(), base)

    def clearMobs(world: World): World =
        let World.World(w) = world;
        Set.toList(w#mobs) |> List.foldLeft((acc, id) -> World.removeEntity(id, acc), world)

    // ── ボタン hit-test（単層 HUD ゆえ手書き）──
    // 注意: 1 要素だから手書きで足りる。ネスト/重なり UI になると最前面優先・親子の可視
    // 伝播・フォーカス scope・入力 bubbling を全部手書きする羽目になり、それは scene-tree が
    // 無料で提供するもの（→ 複雑 UI は二層が正解。fe_rogue の ItemMenuScene/TradeMenuScene 参照）。

    def buttonHit(mp: Vec2.Vec2, world: World): Bool =
        let World.World(w) = world;
        Map.foldLeftWithKey((acc, _id, h) ->
            acc or (h#kind == HudKind.StartButton and h#visible and inRect(mp, h#pos, h#size)),
            false, w#huds)

    def inRect(p: Vec2.Vec2, pos: Vec2.Vec2, size: Vec2.Vec2): Bool =
        p#x >= pos#x and p#x <= (pos#x + size#x) and
        p#y >= pos#y and p#y <= (pos#y + size#y)

    // ── 音（phase の立ち上がりで鳴らす）──

    def playPhaseAudio(prev: GamePhase, cur: GamePhase): Unit \ GameEngine.Audio =
        if (prev != GamePhase.Playing and cur == GamePhase.Playing)
            AudioStreamPlayer.play("music")
        else if (prev != GamePhase.GameOver and cur == GamePhase.GameOver)
            playDeath()
        else ()

    def playDeath(): Unit \ GameEngine.Audio =
        AudioStreamPlayer.stop("music");
        AudioStreamPlayer.play("death")
}
