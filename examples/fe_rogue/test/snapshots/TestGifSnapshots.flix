// TestGifSnapshots — 操作リプレイ GIF を生成する。
//
// 入力スクリプト（ReplayScript.Step 列）を SnapshotHarness + 本物の入力処理 / frameStep で
// 1 フレームずつ実行し、各フレームを SoftRaster で BufferedImage に焼いて GifEncoder で
// アニメ GIF にまとめ、build/snapshots/*.gif へ出力する。ゲームを起動せずに「操作の流れ」を
// 動画で確認できる。
//
// 生成は環境変数 FE_ROGUE_SNAPSHOT_GIF が空でない時だけ（通常の flix test では走らない —
// テスト時間を守る）。golden 比較はしない（人間の目視用）。最終フレームの Drawable 数だけ軽く
// sanity assert する。GIF は build/snapshots/index.html の「操作フロー（GIF）」に並ぶ。
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

    /// GIF の一覧（名前 + 1 行説明）。writeIndex の GIF セクションと生成対象の正。
    pub def gifCatalog(): List[(String, String)] =
        ("topbar_wipe",       "上部バー・陣営ワイプ（自軍確定→敵ターン点火→赤ワイプが左から流れて確定）") ::
        ("flow_action_menu",  "コマンドメニューの選択移動（↓↓↓→↑・ハイライト箱が動く）") ::
        ("flow_item_scroll",  "持ち物・満載で窓スクロール（↓×10・窓が選択に追従）") ::
        ("flow_game_over",    "ゲームオーバーのモーダル選択移動（↓↓↑）") ::
        ("flow_open_item",    "コマンド→アイテム確定で持ち物窓が開く（↓で選び Z で開き→↓↓→X で戻る・phase 遷移）") ::
        ("flow_attack_weapon","攻撃確定で武器窓が右に開く（Z で開き→↓で武器切替・ActionSelect→WeaponSelect 遷移）") :: Nil

    def gifPath(name: String): String = "build/snapshots/${name}.gif"

    /// FE_ROGUE_SNAPSHOT_GIF が空でなければ GIF を生成する。
    def gifEnabled(): Bool \ IO =
        let v = JSystem.getenv("FE_ROGUE_SNAPSHOT_GIF");
        not Object.isNull(v) and not String.isEmpty(v)

    // ════════════════════════════════════════════════════════
    // オーケストレータ
    // ════════════════════════════════════════════════════════

    /// 4 本の GIF を生成し、各最終フレームの Drawable 数を sanity assert する。
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
            // この一発の実行でも index に GIF が並ぶよう、生成後に index を焼き直す。
            SnapshotSupport.writeIndex(
                List.map(fx -> (fx#name, fx#desc), TestUiSnapshots.fixtureList()),
                TestUiSnapshots.outWidthPx(), gifCatalog(), gifWidthPx());
            // sanity: どの最終フレームも空でない（描画が成立している）。
            Assert.assertEq(expected = true,
                c1 > 5 and c2 > 5 and c3 > 5 and c4 > 5 and c5 > 5 and c6 > 5)
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
               BoardQuery, ItemPickupPopupScene.State, ItemMenuState.State, TradeMenuState.State,
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
}
