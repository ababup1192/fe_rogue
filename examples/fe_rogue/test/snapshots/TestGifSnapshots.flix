// TestGifSnapshots — 操作リプレイ GIF を生成する。
//
// 入力スクリプト（ReplayScript.Step 列）を SnapshotHarness + 本物の入力処理 / frameStep で
// 1 フレームずつ実行し、各フレームを SoftRaster で BufferedImage に焼いて GifEncoder で
// アニメ GIF にまとめ、test/snapshots/gifs/*.gif（コミット対象・golden と同じ「保存する生成資産」）
// へ出力する。ゲームを起動せずに「操作の流れ」を動画で確認できる。
//
// 生成は環境変数 FE_ROGUE_SNAPSHOT_GIF が空でない時だけ（通常の flix test では走らない —
// テスト時間を守る）。golden 比較はしない（人間の目視用）。最終フレームの Drawable 数だけ軽く
// sanity assert する。閲覧用の build/snapshots/*.gif は SnapshotSupport.syncGifs が
// test/snapshots/gifs/ からコピーして作る（素の flix test でも毎回コピーするので、既存 GIF は
// クリーンビルドしても消えない）。ページの束ねは各機能の scenario（目録・種別は SnapshotCatalog、
// ページ生成は SnapshotSite）。
//
// 入力→API の対応は Game.flix の dispatch を写す:
//   ActionMenu: ↑↓ = ActionMenuUi.moveSelection(∓1)
//   ItemMenu  : ↑↓ = ItemMenuUi.moveSelection(∓1)
//   GameOver  : ↑↓ = GameOverMenuUi.moveSelection(∓1)
//   TopBar    : キー駆動でなくフェイズ観測（advance/applyFrame）でワイプを進める。
mod TestGifSnapshots {
    import java.lang.{System => JSystem}
    import java.awt.image.BufferedImage

    // ── 定数（PNG スナップショットと同じ素材・GIF は ×4 解像度）──
    def ttfPath(): String = AssetPath.resolve("assets/fonts/MPLUSU-Medium.ttf")
    def joyoPath(): String = AssetPath.resolve("assets/fonts/joyo_kanji.txt")
    def atlasDim(): Float64 = 2048.0
    def clearColor(): Color = {r = 0.098f32, g = 0.125f32, b = 0.102f32}
    def designW(): Int32 = 240i32
    def designH(): Int32 = 128i32
    def designSize(): Vec2.Vec2 = {x = Int32.toFloat64(designW()), y = Int32.toFloat64(designH())}
    /// GIF の出力解像度倍率（PNG の ×8 とは別に ×4）。
    def outScale(): Int32 = 4i32
    /// index.html の GIF 図の基準幅（実ピクセル幅。writeIndex が半分にして CSS 幅にする）。
    pub def gifWidthPx(): Int32 = designW() * outScale()
    /// 各 GIF フレームの表示時間（ms）。
    def frameDelayMs(): Int32 = 60i32
    /// 1 入力の後に挟むフィラーフレーム数（選択の間を見せる）。
    def betweenFrames(): Int32 = 3i32

    /// GIF は build/snapshots/（揮発）でなく test/snapshots/gifs/（コミット対象）へ焼く。
    /// クリーンビルドや素の flix test でも消えない「保存する生成資産」として golden と同じ扱いにする
    /// （build/snapshots への表示は SnapshotSupport.syncGifs が担う）。
    def gifPath(name: String): String = "${SnapshotSupport.gifSourceDir()}/${name}.gif"

    /// FE_ROGUE_SNAPSHOT_GIF が空でなければ GIF を生成する。
    def gifEnabled(): Bool \ IO =
        let v = JSystem.getenv("FE_ROGUE_SNAPSHOT_GIF");
        not Object.isNull(v) and not String.isEmpty(v)

    // ════════════════════════════════════════════════════════
    // オーケストレータ
    // ════════════════════════════════════════════════════════

    /// 全 GIF を生成し、各 sanity 用フレームの Drawable 数を assert する。
    /// 環境変数が無ければ即 no-op（通常の flix test は GIF なしで素通り）。
    @Test
    def testGifSnapshots(): Unit \ {Assert, Fs.FileRead, Fs.FileWrite, IO} = region rc {
        if (not gifEnabled())
            ()
        else {
            let atlas = HeadlessFont.buildUiAtlas(ttfPath(), joyoPath());
            let texPaths = SnapshotSupport.buildTexturePaths();
            let texInfo = SnapshotSupport.buildTextureInfo(texPaths, atlasDim());
            let ctx: SnapshotSupport.Ctx = {
                atlas = atlas, atlasDim = atlasDim(), ttfPath = ttfPath(), texInfo = texInfo, texPaths = texPaths,
                background = clearColor(), scale = outScale(), design = designSize()
            };
            let c1 = genTopbarWipe(rc, ctx);
            let c2 = genActionMenu(rc, ctx);
            let c3 = genItemScroll(rc, ctx);
            let c4 = genGameOver(rc, ctx);
            let c5 = genFlowOpenItem(rc, ctx);
            let c6 = genFlowAttackWeapon(rc, ctx);
            let c7 = genFlowTurnEndHold(rc, ctx);
            let c8 = genFlowLevelUp(rc, ctx);
            let c9 = genFlowLog(rc, ctx);
            let c10 = genCharacterSelect(rc, ctx);
            // この一発の実行でも GIF が各ページに載るよう、test/snapshots/gifs/ から build/snapshots/
            // へコピーしてからサイトを焼き直す（存在チェックで生成済み GIF は img に、未生成は案内に切り替わる）。
            SnapshotSupport.syncGifs(SnapshotCatalog.gifEntries() |> List.map(entry -> entry#name));
            SnapshotSite.generate(TestUiSnapshots.siteConfig(), TestUiSnapshots.catalogItems());
            // sanity: どの最終フレームも空でない（描画が成立している）。
            Assert.assertEq(expected = true,
                c1 > 5 and c2 > 5 and c3 > 5 and c4 > 5 and c5 > 5 and c6 > 5 and c7 > 5 and c8 > 5
                    and c9 > 5 and c10 > 5)
        }
    }

    // ════════════════════════════════════════════════════════
    // フレーム収録（renderUi → BufferedImage → framesRef へ prepend）
    // ════════════════════════════════════════════════════════

    /// 現在の UiWorld を描画し、BufferedImage を framesRef の先頭に積む（あとで reverse）。
    def captureFrame(ctx: SnapshotSupport.Ctx, framesRef: Ref[List[BufferedImage], r]):
            Unit \ {IO + GameEngine.Game + UiWorldState.State + r} =
        let rendered = UiRender.renderUi();
        let img = SoftRaster.renderToImage({
            drawables = rendered#drawables, polygons = rendered#polygons,
            design = ctx#design, scale = ctx#scale, background = ctx#background,
            texturePath = ctx#texPaths, fontTtf = ctx#ttfPath, fontAtlas = ctx#atlas,
            outPath = ""
        });
        Ref.put(img :: Ref.get(framesRef), framesRef)

    /// framesRef を時系列（収録順）に取り出す。
    def collectFrames(framesRef: Ref[List[BufferedImage], r]): List[BufferedImage] \ r =
        List.reverse(Ref.get(framesRef))

    /// 現在の UiWorld の Drawable 数（最終フレームの sanity 用）。
    def drawableCount(): Int32 \ {GameEngine.Game + UiWorldState.State} =
        List.length(UiRender.renderUi()#drawables)

    // ════════════════════════════════════════════════════════
    // topbar_wipe（フェイズ観測でワイプを進める・キー駆動でない）
    // ════════════════════════════════════════════════════════

    /// 未確定の初期 TopBarState（起動直後・shown=None・ワイプなし）。
    def topBarState(floorLabel: String, floorName: String): TopBarState.Data =
        {shown = None, animTarget = None, anim = Duration.zero(), hold = Duration.zero(),
         floorLabel = floorLabel, floorName = floorName}

    /// count フレーム、phase を advance し applyFrame で UiWorld へ塗って収録する。持ち越し Data を返す。
    def topbarFrames(ctx: SnapshotSupport.Ctx, framesRef: Ref[List[BufferedImage], r],
                     count: Int32, phase: TurnPhase.Phase, data: TopBarState.Data):
            TopBarState.Data \ {IO + GameEngine.Game + UiWorldState.State + r} =
        if (count <= 0) data
        else {
            let frame = TopBarUi.advance(TestUiSnapshots.dt(), phase, data);
            let ui = UiStore.setVisible("TopBar", true, UiWorldState.State.get());
            UiWorldState.State.put(TopBarUi.applyFrame(frame, false, ui));
            captureFrame(ctx, framesRef);
            topbarFrames(ctx, framesRef, count - 1, phase, frame#data)
        }

    /// 自軍確定（青ベース）→ 敵ターン点火 → 赤ワイプが左から流れて確定、を 1/60 ずつ進めて撮る。
    def genTopbarWipe(rc: Region[r], ctx: SnapshotSupport.Ctx): Int32 \ {IO + Fs.FileRead + r} =
        let framesRef = Ref.fresh(rc, (Nil: List[BufferedImage]));
        let count = SnapshotSupport.withMockGame(ctx#atlas, ctx#texInfo, () ->
            UiWorldState.withState(rc, () -> {
                TestUiSnapshots.spawnUi(TopBarUi.specPath());
                // 起動直後 advance は自軍を即確定（shown=Some(false)）。
                let confirmed = TopBarUi.advance(TestUiSnapshots.dt(),
                                                 TurnPhase.Phase.PlayerCursor, topBarState("B1", "はじまりの洞窟"));
                // 青ベースで数フレーム保持 → 敵ターンでワイプ点火・進行・赤確定。
                let steady = topbarFrames(ctx, framesRef, 6, TurnPhase.Phase.PlayerCursor, confirmed#data);
                discard topbarFrames(ctx, framesRef, 44, TurnPhase.Phase.EnemyTurn, steady);
                drawableCount()
            }));
        GifEncoder.encode(collectFrames(framesRef), frameDelayMs(), gifPath("topbar_wipe"));
        count

    // ════════════════════════════════════════════════════════
    // flow_turn_end_hold（Shift 長押し → 充填リングが満ちる → 発動）
    // ════════════════════════════════════════════════════════

    /// count フレーム、held=true・active=true で純粋 step を進め、applyRing で UiWorld へ塗って収録する。
    /// ログ帯を背景として毎フレーム可視にする。持ち越し GaugeData を返す。
    def turnEndHoldFrames(ctx: SnapshotSupport.Ctx, framesRef: Ref[List[BufferedImage], r],
                          count: Int32, data: TurnEndHoldState.GaugeData):
            TurnEndHoldState.GaugeData \ {IO + GameEngine.Game + UiWorldState.State + r} =
        if (count <= 0) data
        else {
            let result = TurnEndHoldUi.step(data, true, true, TestUiSnapshots.dt());
            let ui = UiStore.setVisible(LogUi.rootPath(), true, UiWorldState.State.get());
            UiWorldState.State.put(TurnEndHoldUi.applyRing(result#ratio, result#visible, ui));
            captureFrame(ctx, framesRef);
            turnEndHoldFrames(ctx, framesRef, count - 1, result#data)
        }

    /// Shift 長押しで充填リングが 0→満タン→発動する様子を 1/60 ずつ進めて撮る（キー駆動でなく純粋 step 観測）。
    def genFlowTurnEndHold(rc: Region[r], ctx: SnapshotSupport.Ctx): Int32 \ {IO + Fs.FileRead + r} =
        let framesRef = Ref.fresh(rc, (Nil: List[BufferedImage]));
        let count = SnapshotSupport.withMockGame(ctx#atlas, ctx#texInfo, () ->
            UiWorldState.withState(rc, () -> {
                TestUiSnapshots.spawnUi(LogUi.specPath());
                TestUiSnapshots.spawnUi(TurnEndHoldUi.specPath());
                // 初期状態から held=true で 48 フレーム（≒0.77 秒）進める。0.64 秒で満タン→発動し以後満タン維持。
                discard turnEndHoldFrames(ctx, framesRef, 48, TurnEndHoldState.initial());
                drawableCount()
            }));
        GifEncoder.encode(collectFrames(framesRef), frameDelayMs(), gifPath("flow_turn_end_hold"));
        count

    // ════════════════════════════════════════════════════════
    // flow_level_up（出現 → 各ステータス増分 → 確定で閉じる）
    // ════════════════════════════════════════════════════════

    /// レベルアップ演出の時間発展は遅い（bonus ≈ 2.0 秒 / 各 status_up ≈ 0.8 秒）ので、GIF では 1 フレーム
    /// あたりの delta を大きめ（120ms）にして実 frameStep のまま早送りする（演出の因果は保つ）。
    def levelUpDt(): Duration.Duration = Duration.millis(120)

    /// count フレーム、実 frameStep を levelUpDt() ずつ進めて収録する（bonus → 各ステータス増分）。
    def levelUpFrames(ctx: SnapshotSupport.Ctx, framesRef: Ref[List[BufferedImage], r],
                      count: Int32, scene: Scene[NodeTag]):
            Unit \ {IO + GameEngine.Game + UiWorldState.State + GameEngine.Audio
                     + TurnPhase.State + LevelUpPanelState.State + r} =
        if (count <= 0) ()
        else {
            discard LevelUpPanelUi.frameStep(levelUpDt(), scene);
            captureFrame(ctx, framesRef);
            levelUpFrames(ctx, framesRef, count - 1, scene)
        }

    /// パネルが出現 → ステータス増分が順に出る演出（実 frameStep の時間発展）→ 確定で閉じる を撮る。
    /// パネル状態（保留レベルアップ結果）は scene へ直接注入し、確定の phase 遷移は withFullMocks の
    /// 可変 Ref が持続させる（2 回目の確定で LevelUpView を抜け、次フレームで panel が消える）。
    /// sanity 用の Drawable 数は「全行を出し切った（閉じる前の）」フレームで採る（閉じると空になるため）。
    def genFlowLevelUp(rc: Region[r], ctx: SnapshotSupport.Ctx): Int32 \ {IO + Fs.FileRead + r} =
        let framesRef = Ref.fresh(rc, (Nil: List[BufferedImage]));
        let count = SnapshotSupport.withMockGame(ctx#atlas, ctx#texInfo, () ->
            UiWorldState.withState(rc, () -> {
                TestUiSnapshots.spawnUi(LevelUpPanelUi.specPath());
                let lord = {pendingLevelUp = Some(TestUiSnapshots.levelUpFixtureResult())
                            | TestUiSnapshots.mkPlayer(TestUiSnapshots.basePlayer(0, "knight", {x = 1, y = 1}))};
                let scene = TestUiSnapshots.worldScene() |> TestUiSnapshots.addPlayer(lord);
                let cfg = {phase = TurnPhase.Phase.LevelUpView, selectedId = Some(0)
                           | SnapshotHarness.config(scene)};
                LevelUpPanelState.withState(rc, () ->
                  SnapshotHarness.withFullMocks(cfg, () -> {
                      // 出現 → bonus → 各ステータス増分が順に出る（実 frameStep の時間発展）。
                      levelUpFrames(ctx, framesRef, 34, scene);
                      // 1 回目の確定: まだ出し切っていなければ残りを一気に出す（閉じない）。
                      discard LevelUpPanelUi.confirm(scene);
                      levelUpFrames(ctx, framesRef, 4, scene);
                      let full = drawableCount();  // 全行が出た（閉じる前の）Drawable 数
                      // 2 回目の確定: 閉じる → 次フレームで panel が消える（phase 復帰が可変 Ref で持続）。
                      discard LevelUpPanelUi.confirm(scene);
                      levelUpFrames(ctx, framesRef, 6, scene);
                      full
                  }))
            }));
        GifEncoder.encode(collectFrames(framesRef), frameDelayMs(), gifPath("flow_level_up"));
        count

    // ════════════════════════════════════════════════════════
    // flow_log（ログ帯: 白=プレイヤー / 赤=敵 を時間差で注入 → 行が押し上がる → アイドルで帯ごと消える）
    // ════════════════════════════════════════════════════════

    /// ログ帯の見やすい早送り dt（実 step のまま時間を進める。1 フレーム 200ms）。
    /// アイドル寿命は LogUi.holdSeconds()=5 秒なので、この dt なら数十フレームで帯が消える。
    def logDt(): Duration.Duration = Duration.millis(200)

    /// count フレーム、新着なしで実 LogUi.step を logDt() ずつ進めて収録する
    /// （呼ぶ前に emit された新着はこの中の最初の step が drain する。以後はアイドルとして寿命が進む）。
    def logFrames(ctx: SnapshotSupport.Ctx, framesRef: Ref[List[BufferedImage], r],
                  count: Int32, scene: Scene[NodeTag]):
            Unit \ {IO + GameEngine.Game + UiWorldState.State
                     + GameLogger.GameLogger + LogState.State + r} =
        if (count <= 0) ()
        else {
            discard LogUi.step(logDt(), scene);
            captureFrame(ctx, framesRef);
            logFrames(ctx, framesRef, count - 1, scene)
        }

    /// プレイヤー行動ログ（白）→ 敵ログ（赤）を時間差で GameLogger へ注入し、行が下から押し上がる様子と、
    /// 最後の新着から holdSeconds() 秒のアイドルで帯ごと消えるまでを撮る。GameLogger は本物の handler
    /// （withLogger）で回すので、drain / キュー詰め替え / 寿命判定はすべて実ロジック。
    /// sanity 用の Drawable 数は「帯が満ちた（アイドルで消える前の）」フレームで採る（消えると空になるため）。
    def genFlowLog(rc: Region[r], ctx: SnapshotSupport.Ctx): Int32 \ {IO + Fs.FileRead + r} =
        let framesRef = Ref.fresh(rc, (Nil: List[BufferedImage]));
        let count = SnapshotSupport.withMockGame(ctx#atlas, ctx#texInfo, () ->
            UiWorldState.withState(rc, () ->
                LogState.withState(rc, () ->
                    GameLogger.withLogger(rc, () -> {
                        TestUiSnapshots.spawnUi(LogUi.specPath());
                        let scene = TestUiSnapshots.worldScene();
                        // 白（プレイヤー）→ 赤（敵）を数行、行の押し上げが見える間隔で注入する。
                        GameLogger.playerLog("剣士 の こうげき");
                        logFrames(ctx, framesRef, 3, scene);
                        GameLogger.playerLog("ゴブリン に 6 のダメージ");
                        logFrames(ctx, framesRef, 3, scene);
                        GameLogger.enemyLog("ゴブリン の はんげき");
                        logFrames(ctx, framesRef, 3, scene);
                        GameLogger.playerLog("僧侶 の いやし");
                        logFrames(ctx, framesRef, 3, scene);
                        GameLogger.enemyLog("ゴブリン の こうげき");
                        logFrames(ctx, framesRef, 3, scene);
                        // 6 行目でいちばん古い行が押し出される（窓は maxQueue()=5 行）。
                        GameLogger.playerLog("剣士 の とどめ");
                        logFrames(ctx, framesRef, 4, scene);
                        let full = drawableCount();  // 帯が満ちた（消える前の）Drawable 数
                        // 以後は無入力アイドル。holdSeconds()=5 秒 ≒ 25 フレームで帯ごと消えるまで回す。
                        logFrames(ctx, framesRef, 30, scene);
                        full
                    }))));
        GifEncoder.encode(collectFrames(framesRef), frameDelayMs(), gifPath("flow_log"));
        count

    // ════════════════════════════════════════════════════════
    // flow_action_menu（ActionMenu の選択移動）
    // ════════════════════════════════════════════════════════

    /// 攻撃 / アイテム / 交換 / 待機 の 4 項目が成立する盤面（味方＋隣接味方＋射程内の敵）。
    def actionMenuConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = TestUiSnapshots.mkPlayer(
            {weaponIds = "iron_sword" :: Nil | TestUiSnapshots.basePlayer(0, "knight", {x = 1, y = 1})});
        let ally = TestUiSnapshots.mkPlayer(TestUiSnapshots.basePlayer(1, "paladin", {x = 2, y = 1}));
        let enemy = TestUiSnapshots.mkEnemy(9, "fighter_t1", {x = 1, y = 2}, 12, Some("iron_sword"));
        let scene = TestUiSnapshots.worldScene()
            |> TestUiSnapshots.addPlayer(lord)
            |> TestUiSnapshots.addPlayer(ally)
            |> TestUiSnapshots.addEnemy(enemy, true);
        {phase = TurnPhase.Phase.ActionSelect, selectedId = Some(0) | SnapshotHarness.config(scene)}

    def actionScript(): List[ReplayScript.Step] =
        ReplayScript.Step.KeyPress(ReplayScript.Key.Down) ::
        ReplayScript.Step.KeyPress(ReplayScript.Key.Down) ::
        ReplayScript.Step.KeyPress(ReplayScript.Key.Down) ::
        ReplayScript.Step.KeyPress(ReplayScript.Key.Up) :: Nil

    def genActionMenu(rc: Region[r], ctx: SnapshotSupport.Ctx): Int32 \ {IO + Fs.FileRead + r} =
        let framesRef = Ref.fresh(rc, (Nil: List[BufferedImage]));
        let cfg = actionMenuConfig();
        let count = SnapshotSupport.withMockGame(ctx#atlas, ctx#texInfo, () ->
            UiWorldState.withState(rc, () -> {
                TestUiSnapshots.spawnUi(ActionMenuUi.specPath());
                let applyKey = k -> {
                    let delta = match k {
                        case ReplayScript.Key.Up   => -1
                        case ReplayScript.Key.Down => 1
                        case _                     => 0
                    };
                    discard SnapshotHarness.withMocks(cfg, () -> ActionMenuUi.moveSelection(delta, cfg#scene))
                };
                let tick = () -> {
                    discard SnapshotHarness.withMocks(cfg, () -> ActionMenuUi.frameStep(TestUiSnapshots.dt(), cfg#scene));
                    captureFrame(ctx, framesRef)
                };
                ReplayScript.execute(betweenFrames(), actionScript(), applyKey, tick);
                drawableCount()
            }));
        GifEncoder.encode(collectFrames(framesRef), frameDelayMs(), gifPath("flow_action_menu"));
        count

    // ════════════════════════════════════════════════════════
    // flow_item_scroll（16 個満載で窓スクロール）
    // ════════════════════════════════════════════════════════

    /// 武器 16 本を持つ味方（窓 3 行を溢れさせて ↓ でスクロールさせる）。
    def itemScrollConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let ids = "iron_sword" :: "steel_sword" :: "silver_sword" :: "killing_edge" :: "iron_lance"
                    :: "steel_lance" :: "silver_lance" :: "keen_lance" :: "iron_axe" :: "steel_axe"
                    :: "silver_axe" :: "demon_axe" :: "iron_bow" :: "steel_bow" :: "silver_bow"
                    :: "mithril_sword" :: Nil;
        let lord = TestUiSnapshots.mkPlayer(
            {hp = 22, weaponIds = ids | TestUiSnapshots.basePlayer(0, "knight", {x = 1, y = 1})});
        let scene = TestUiSnapshots.worldScene() |> TestUiSnapshots.addPlayer(lord);
        {phase = TurnPhase.Phase.ItemSelect, selectedId = Some(0), itemCategory = 0
         | SnapshotHarness.config(scene)}

    def itemScrollScript(): List[ReplayScript.Step] =
        List.repeat(10, ReplayScript.Step.KeyPress(ReplayScript.Key.Down))

    def genItemScroll(rc: Region[r], ctx: SnapshotSupport.Ctx): Int32 \ {IO + Fs.FileRead + r} =
        let framesRef = Ref.fresh(rc, (Nil: List[BufferedImage]));
        let cfg = itemScrollConfig();
        let count = SnapshotSupport.withMockGame(ctx#atlas, ctx#texInfo, () ->
            UiWorldState.withState(rc, () -> {
                TestUiSnapshots.spawnUi(ItemMenuUi.specPath());
                let applyKey = k -> {
                    let delta = match k {
                        case ReplayScript.Key.Up   => -1
                        case ReplayScript.Key.Down => 1
                        case _                     => 0
                    };
                    discard SnapshotHarness.withMocks(cfg, () -> ItemMenuUi.moveSelection(delta, cfg#scene))
                };
                let tick = () -> {
                    discard SnapshotHarness.withMocks(cfg, () -> ItemMenuUi.frameStep(TestUiSnapshots.dt(), cfg#scene));
                    captureFrame(ctx, framesRef)
                };
                ReplayScript.execute(betweenFrames(), itemScrollScript(), applyKey, tick);
                drawableCount()
            }));
        GifEncoder.encode(collectFrames(framesRef), frameDelayMs(), gifPath("flow_item_scroll"));
        count

    // ════════════════════════════════════════════════════════
    // flow_game_over（モーダル選択移動）
    // ════════════════════════════════════════════════════════

    def gameOverScript(): List[ReplayScript.Step] =
        ReplayScript.Step.KeyPress(ReplayScript.Key.Down) ::
        ReplayScript.Step.KeyPress(ReplayScript.Key.Down) ::
        ReplayScript.Step.KeyPress(ReplayScript.Key.Up) :: Nil

    def genGameOver(rc: Region[r], ctx: SnapshotSupport.Ctx): Int32 \ {IO + Fs.FileRead + r} =
        let framesRef = Ref.fresh(rc, (Nil: List[BufferedImage]));
        let cfg = {simPhase = SimPhase.GameOver | SnapshotHarness.config(TestUiSnapshots.worldScene())};
        let count = SnapshotSupport.withMockGame(ctx#atlas, ctx#texInfo, () ->
            UiWorldState.withState(rc, () -> {
                TestUiSnapshots.spawnUi(GameOverMenuUi.specPath());
                // モーダルを可視化する（frameStep は phase==GameOver で可視化するが、選択移動 API は
                // UiWorldState だけを触るので、事前に一度 frameStep で可視化しておく）。
                let applyKey = k -> match k {
                    case ReplayScript.Key.Up   => GameOverMenuUi.moveSelection(-1)
                    case ReplayScript.Key.Down => GameOverMenuUi.moveSelection(1)
                    case _                     => ()
                };
                let tick = () -> {
                    discard SnapshotHarness.withMocks(cfg, () -> GameOverMenuUi.frameStep(TestUiSnapshots.dt(), cfg#scene));
                    captureFrame(ctx, framesRef)
                };
                ReplayScript.execute(betweenFrames(), gameOverScript(), applyKey, tick);
                drawableCount()
            }));
        GifEncoder.encode(collectFrames(framesRef), frameDelayMs(), gifPath("flow_game_over"));
        count

    // ════════════════════════════════════════════════════════
    // 多段階フロー（確定でフェーズが変わる遷移）— phase-aware dispatch + 可変ハーネス
    // ════════════════════════════════════════════════════════

    /// 意味入力を現在フェーズに応じた Ui API へ束ねる（Game.flix の dispatch の写し）。
    /// 対応表（Game.flix の `dispatchMenuKey` / `*Direction` を写す。この 1 表が単一の真理点）:
    ///   ActionSelect      : ↑↓=ActionMenuUi.moveSelection(∓1) / Z=confirmCurrentSelection / X=onActionCancelled
    ///   ItemSelect        : ↑↓=ItemMenuUi.moveSelection(∓1) / ←→=categoryPrev/Next / Z=confirmCurrentSelection / X=onItemCancelled
    ///   ItemActionSelect  : ↑↓=ItemMenuUi.moveSelection(∓1) / Z=confirmCurrentSelection / X=onActionCancelled
    ///   WeaponSelect      : ↑↓=WeaponSelectUi.moveSelection(∓1) / Z=confirmCurrentSelection / X=onCancelled
    /// 単一 match（(phase, key) タプル）に束ねて arm 集合で効果を合流させる（checked_ecast 不要）。
    /// 確定（Z）のゲームロジックは本物を実行し、書かれた phase が可変ハーネスの Ref に残る。
    pub def applyFlowKey(key: ReplayScript.Key, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, GameLogger.GameLogger, EnemyTurn.Queue,
               TurnPhase.State, SelectedPlayer.State, CursorState.State, ArrowCursorState.State,
               GatherResume.State, PlayerData.PartyQuery, EnemyData.RosterQuery,
               CustomEffects.FloorAdvanceRequest, GameEngine.Audio, World.Command, World.WorldQuery,
               BoardQuery, ItemPickupPopupState.State, ItemMenuState.State, TradeMenuState.State,
               UiWorldState.State} =
        match (TurnPhase.State.get(), key) {
            // ActionSelect（コマンドメニュー）
            case (TurnPhase.Phase.ActionSelect, ReplayScript.Key.Up)      => ActionMenuUi.moveSelection(-1, scene)
            case (TurnPhase.Phase.ActionSelect, ReplayScript.Key.Down)    => ActionMenuUi.moveSelection(1, scene)
            case (TurnPhase.Phase.ActionSelect, ReplayScript.Key.Confirm) => ActionMenuUi.confirmCurrentSelection(scene)
            case (TurnPhase.Phase.ActionSelect, ReplayScript.Key.Cancel)  => ActionMenuUi.onActionCancelled(scene)
            // ItemSelect（持ち物・1 カテゴリ表示）
            case (TurnPhase.Phase.ItemSelect, ReplayScript.Key.Up)        => ItemMenuUi.moveSelection(-1, scene)
            case (TurnPhase.Phase.ItemSelect, ReplayScript.Key.Down)      => ItemMenuUi.moveSelection(1, scene)
            case (TurnPhase.Phase.ItemSelect, ReplayScript.Key.Left)      => ItemMenuUi.categoryPrev(scene)
            case (TurnPhase.Phase.ItemSelect, ReplayScript.Key.Right)     => ItemMenuUi.categoryNext(scene)
            case (TurnPhase.Phase.ItemSelect, ReplayScript.Key.Confirm)   => ItemMenuUi.confirmCurrentSelection(scene)
            case (TurnPhase.Phase.ItemSelect, ReplayScript.Key.Cancel)    => ItemMenuUi.onItemCancelled(scene)
            // ItemActionSelect（サブメニュー：そうび/なげる/すてる）
            case (TurnPhase.Phase.ItemActionSelect, ReplayScript.Key.Up)      => ItemMenuUi.moveSelection(-1, scene)
            case (TurnPhase.Phase.ItemActionSelect, ReplayScript.Key.Down)    => ItemMenuUi.moveSelection(1, scene)
            case (TurnPhase.Phase.ItemActionSelect, ReplayScript.Key.Confirm) => ItemMenuUi.confirmCurrentSelection(scene)
            case (TurnPhase.Phase.ItemActionSelect, ReplayScript.Key.Cancel)  => ItemMenuUi.onActionCancelled(scene)
            // WeaponSelect（武器窓）
            case (TurnPhase.Phase.WeaponSelect, ReplayScript.Key.Up)      => WeaponSelectUi.moveSelection(-1, scene)
            case (TurnPhase.Phase.WeaponSelect, ReplayScript.Key.Down)    => WeaponSelectUi.moveSelection(1, scene)
            case (TurnPhase.Phase.WeaponSelect, ReplayScript.Key.Confirm) => WeaponSelectUi.confirmCurrentSelection(scene)
            case (TurnPhase.Phase.WeaponSelect, ReplayScript.Key.Cancel)  => WeaponSelectUi.onCancelled(scene)
            // それ以外のフェーズ / キーは無反応（GIF ではこの表の範囲だけ入力する）。
            case _ => scene
        }

    /// 3 メニュー窓（コマンド / 武器 / 持ち物）の frameStep を毎フレーム回して収録する tick。
    /// gameLoop が全 UI の frameStep を毎フレーム呼ぶのと同じく、各 frameStep が phase で自己 gate し、
    /// 可視・内容・パネル追従を実ロジックで組む。scene は fixture（cfg#scene）を使い回す
    /// （可変状態は phase / 選択 / UiWorld などの resource 側に載るため、確定が返す scene は捨ててよい）。
    def flowTick(ctx: SnapshotSupport.Ctx, scene: Scene[NodeTag],
                 framesRef: Ref[List[BufferedImage], r]):
            Unit \ {IO + GameEngine.Game + UiWorldState.State + TurnPhase.State + SelectedPlayer.State
                     + CursorState.State + PlayerData.PartyQuery + EnemyData.RosterQuery
                     + World.WorldQuery + Tween.Scheduler + AnimationPlayer.Scheduler
                     + ItemMenuState.State + r} =
        discard ActionMenuUi.frameStep(TestUiSnapshots.dt(), scene);
        discard WeaponSelectUi.frameStep(TestUiSnapshots.dt(), scene);
        discard ItemMenuUi.frameStep(TestUiSnapshots.dt(), scene);
        captureFrame(ctx, framesRef)

    /// flow_open_item / flow_attack_weapon 共通の drive。3 窓を spawn し、execute 全体を 1 回だけ
    /// `withFullMocks` で包む（可変 phase が 1 スコープを貫通）。最終フレームの Drawable 数を返す。
    def genFlow(rc: Region[r], ctx: SnapshotSupport.Ctx, name: String,
                cfg: SnapshotHarness.Config, script: List[ReplayScript.Step]):
            Int32 \ {IO + Fs.FileRead + r} =
        let framesRef = Ref.fresh(rc, (Nil: List[BufferedImage]));
        let count = SnapshotSupport.withMockGame(ctx#atlas, ctx#texInfo, () ->
            UiWorldState.withState(rc, () -> {
                TestUiSnapshots.spawnUi(ActionMenuUi.specPath());
                TestUiSnapshots.spawnUi(WeaponSelectUi.specPath());
                TestUiSnapshots.spawnUi(ItemMenuUi.specPath());
                SnapshotHarness.withFullMocks(cfg, () -> {
                    let applyKey = k -> discard applyFlowKey(k, cfg#scene);
                    let tick = () -> flowTick(ctx, cfg#scene, framesRef);
                    ReplayScript.execute(betweenFrames(), script, applyKey, tick)
                });
                drawableCount()
            }));
        GifEncoder.encode(collectFrames(framesRef), frameDelayMs(), gifPath(name));
        count

    // ── flow_open_item（コマンド→アイテム確定で持ち物窓が開き、X で閉じる）──

    /// 主人公(id0)が武器 3 本を持ち、射程内に敵（攻撃成立）・隣接味方なし（交換は出ない）。
    /// 項目は「攻撃(0) / アイテム(1) / たいき(2)」。↓ で「アイテム」へ寄せて Z で開く。
    def flowOpenItemConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = TestUiSnapshots.mkPlayer(
            {weaponIds = "iron_sword" :: "steel_lance" :: "silver_sword" :: Nil
             | TestUiSnapshots.basePlayer(0, "knight", {x = 1, y = 1})});
        let enemy = TestUiSnapshots.mkEnemy(9, "fighter_t1", {x = 1, y = 2}, 12, Some("iron_sword"));
        let scene = TestUiSnapshots.worldScene()
            |> TestUiSnapshots.addPlayer(lord)
            |> TestUiSnapshots.addEnemy(enemy, true);
        {phase = TurnPhase.Phase.ActionSelect, selectedId = Some(0), cursor = {x = 1, y = 2}
         | SnapshotHarness.config(scene)}

    def flowOpenItemScript(): List[ReplayScript.Step] =
        ReplayScript.Step.KeyPress(ReplayScript.Key.Down) ::    // 攻撃 → アイテム
        ReplayScript.Step.KeyPress(ReplayScript.Key.Confirm) :: // アイテム確定 → ItemMenu が開く（ItemSelect）
        ReplayScript.Step.KeyPress(ReplayScript.Key.Down) ::    // 持ち物カーソル移動
        ReplayScript.Step.KeyPress(ReplayScript.Key.Down) ::
        ReplayScript.Step.KeyPress(ReplayScript.Key.Cancel) :: Nil // X → コマンドへ戻る（ActionSelect）

    def genFlowOpenItem(rc: Region[r], ctx: SnapshotSupport.Ctx): Int32 \ {IO + Fs.FileRead + r} =
        genFlow(rc, ctx, "flow_open_item", flowOpenItemConfig(), flowOpenItemScript())

    // ── flow_attack_weapon（攻撃確定で武器窓が右に開き、↓ で武器切替）──

    /// 主人公(id0)が武器 2 本を持ち、射程内に敵。項目「攻撃(0)」を Z で確定すると
    /// enterWeaponSelect が phase=WeaponSelect にし、武器窓が ActionMenu の右隣に開く（実遷移）。
    /// PlayerAttackHold まで進めず WeaponSelect で止め、↓ で武器カーソルを動かす。
    def flowAttackWeaponConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = TestUiSnapshots.mkPlayer(
            {weaponIds = "iron_sword" :: "steel_lance" :: Nil
             | TestUiSnapshots.basePlayer(0, "knight", {x = 1, y = 1})});
        let enemy = TestUiSnapshots.mkEnemy(9, "fighter_t1", {x = 1, y = 2}, 12, Some("iron_sword"));
        let scene = TestUiSnapshots.worldScene()
            |> TestUiSnapshots.addPlayer(lord)
            |> TestUiSnapshots.addEnemy(enemy, true);
        {phase = TurnPhase.Phase.ActionSelect, selectedId = Some(0), cursor = {x = 1, y = 2}
         | SnapshotHarness.config(scene)}

    def flowAttackWeaponScript(): List[ReplayScript.Step] =
        ReplayScript.Step.KeyPress(ReplayScript.Key.Confirm) :: // 攻撃確定 → 武器窓が開く（WeaponSelect）
        ReplayScript.Step.KeyPress(ReplayScript.Key.Down) ::    // 武器切替
        ReplayScript.Step.KeyPress(ReplayScript.Key.Down) :: Nil

    def genFlowAttackWeapon(rc: Region[r], ctx: SnapshotSupport.Ctx): Int32 \ {IO + Fs.FileRead + r} =
        genFlow(rc, ctx, "flow_attack_weapon", flowAttackWeaponConfig(), flowAttackWeaponScript())

    // ════════════════════════════════════════════════════════
    // flow_character_select（注目カードを右へ送る → カルーセルが寄る → Z で 3 人選ぶ）
    // ════════════════════════════════════════════════════════

    /// count フレーム、実 frameStep を進めて収録する（カルーセルが目標へ滑らかに寄る時間発展を撮る）。
    /// 入力音（Audio）を避けるため、注目移動 / 選択は `CharacterSelectUi` の純関数を直接適用し
    /// （`onKeyPressed` を通さない）、見た目更新は本物の `frameStep` に任せる。
    def charSelectFrames(ctx: SnapshotSupport.Ctx, framesRef: Ref[List[BufferedImage], r], count: Int32):
            Unit \ {IO + GameEngine.Game + UiWorldState.State + CharacterSelectState.State + r} =
        if (count <= 0) ()
        else {
            discard CharacterSelectUi.frameStep(TestUiSnapshots.dt(), TestUiSnapshots.worldScene());
            captureFrame(ctx, framesRef);
            charSelectFrames(ctx, framesRef, count - 1)
        }

    /// 出撃メンバー選択のカルーセルを撮る。実カタログの players プール（8 人）で候補を組み、注目を
    /// 右へ 3 回送りながら 3 人を選ぶ様子を、実 frameStep の時間発展（lerp で寄るカルーセル）で見せる。
    def genCharacterSelect(rc: Region[r], ctx: SnapshotSupport.Ctx): Int32 \ {IO + Fs.FileRead + r} =
        let framesRef = Ref.fresh(rc, (Nil: List[BufferedImage]));
        let count = SnapshotSupport.withMockGame(ctx#atlas, ctx#texInfo, () ->
            UiWorldState.withState(rc, () ->
                CharacterSelectState.withState(rc, () -> {
                    TestUiSnapshots.spawnUi(CharacterSelectUi.specPath());
                    let catalog = UnitCatalog.load(AssetPath.resolve("resources/units.json"), WeaponCatalog.load());
                    let players = UnitCatalog.pool("players", catalog);
                    UiWorldState.State.put(UiStore.setVisible(CharacterSelectUi.rootPath(), true, UiWorldState.State.get()));
                    CharacterSelectState.State.put(CharacterSelectUi.initialState(players));
                    let apply = f -> CharacterSelectState.State.put(f(CharacterSelectState.State.get()));
                    // 注目カード 0 で落ち着かせる → 選ぶ → 右へ送りつつ計 3 人選ぶ（カルーセルが毎回寄る）。
                    charSelectFrames(ctx, framesRef, 8);
                    apply(CharacterSelectUi.toggleSelect);                     // card0 を選択
                    charSelectFrames(ctx, framesRef, 5);
                    apply(CharacterSelectUi.moveFocus(1));                     // → card1
                    charSelectFrames(ctx, framesRef, 9);
                    apply(CharacterSelectUi.toggleSelect);                     // card1 を選択
                    charSelectFrames(ctx, framesRef, 5);
                    apply(CharacterSelectUi.moveFocus(1));                     // → card2
                    charSelectFrames(ctx, framesRef, 9);
                    apply(CharacterSelectUi.moveFocus(1));                     // → card3
                    charSelectFrames(ctx, framesRef, 9);
                    apply(CharacterSelectUi.toggleSelect);                     // card3 を選択（計 3 人 → 出撃有効）
                    charSelectFrames(ctx, framesRef, 10);
                    drawableCount()
                })));
        GifEncoder.encode(collectFrames(framesRef), frameDelayMs(), gifPath("flow_character_select"));
        count
}
