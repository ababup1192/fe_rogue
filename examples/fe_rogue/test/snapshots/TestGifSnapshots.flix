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
}
