// TestUiSnapshots — 各 UI（ActionMenu / WeaponSelect / ItemMenu / TradeMenu / GameOverMenu /
// SuspendConfirm / TopBar / UnitCard / EnemyCard）を代表的な状態で組み、renderUi の描画出力を
// golden と比較しつつ build/snapshots/ に PNG を焼く。
//
// 方針: フィクスチャは **データを宣言するだけ**で、UI の中身は本物のゲームコードが組む。各シーンは
//   1. UiSpec.spawnRoot で ui.json の骨組みだけ立て、
//   2. カタログ由来の実データ（味方/敵/在庫）で盤面 scene を作り、
//   3. `SnapshotHarness.withMocks(config, () -> XxxUi.frameStep(dt, scene))` で本物の frameStep に
//      可視・スロット流し込み・幅フィット・重量色・空きスロット・カード解決を組ませる。
// これで「敵フェイズが赤い」「満杯でないペインに空きスロットが出る」等が実ロジックの帰結になり、
// 手塗りの嘘が golden に混じらない。TopBar だけは frameStep でなく `advance → applyFrame`
// （同じ実経路）をフィクスチャから直接呼んで配色を作る。
//
// 複数 root を同じ UiWorld に spawn すれば renderUi が可視 root を全合成するので、組み合わせ
// シーン（HUD 全部乗せ）は各 root の frameStep を 1 つの UiWorld 上で順に走らせるだけで作る。
// アトラス焼き込みは重いので 1 つの @Test で 1 度だけ行い、全フィクスチャを回す。
//
// 更新: 新規/変更 golden を承認するときは `FE_ROGUE_SNAPSHOT_UPDATE=1 flix test`。
// 目視: build/snapshots/index.html を開くと全メニューを一覧できる。
mod TestUiSnapshots {

    // ── 定数 ──
    def ttfPath(): String = AssetPath.resolve("assets/fonts/MPLUSU-Medium.ttf")
    def joyoPath(): String = AssetPath.resolve("assets/fonts/joyo_kanji.txt")
    def atlasDim(): Float64 = 2048.0
    def clearColor(): Color = {r = 0.098f32, g = 0.125f32, b = 0.102f32}
    def designW(): Int32 = 240i32
    def designH(): Int32 = 128i32
    def designSize(): Vec2.Vec2 = {x = Int32.toFloat64(designW()), y = Int32.toFloat64(designH())}
    // 出力解像度 = design × outScale。実機 GPU 描画と同じくドット絵をカリカリ焼くため大きめに拡大する。
    def outScale(): Int32 = 8i32
    /// index.html の img CSS 幅（Retina 2x 前提で実ピクセル幅 ÷ 2。ブラウザ側の補間をゼロにする）。
    pub def outWidthPx(): Int32 = designW() * outScale() / 2i32

    /// 1 フレームぶんの経過（frameStep / advance の delta）。
    pub def dt(): Duration.Duration = Duration.millis(16)

    // ════════════════════════════════════════════════════════
    // オーケストレータ
    // ════════════════════════════════════════════════════════

    /// 全 UI スナップショットを 1 度のアトラス焼き込みで処理する。golden 不一致があれば
    /// そのリストを assert で提示して落ちる（更新モードでは golden を書き直して pass）。
    @Test
    def testUiSnapshots(): Unit \ {Assert, Fs.FileRead, Fs.FileWrite, IO} = region rc {
        let atlas = HeadlessFont.buildUiAtlas(ttfPath(), joyoPath());
        let texPaths = SnapshotSupport.buildTexturePaths();
        let texInfo = SnapshotSupport.buildTextureInfo(texPaths, atlasDim());
        let ctx: SnapshotSupport.Ctx = {
            atlas = atlas, atlasDim = atlasDim(), ttfPath = ttfPath(), texInfo = texInfo, texPaths = texPaths,
            background = clearColor(), scale = outScale(), design = designSize()
        };
        let fixtures = fixtureList();
        let failures = List.filterMap(fx ->
            SnapshotSupport.snapshot(ctx, fx#name,
                renderFixture(rc, ctx, fx#name)), fixtures);
        SnapshotSupport.writeIndex(List.map(fx -> (fx#name, fx#desc), fixtures), outWidthPx(),
                                   TestGifSnapshots.gifCatalog(), TestGifSnapshots.gifWidthPx());
        Assert.assertEq(expected = (Nil: List[String]), failures)
    }

    /// 1 フィクスチャの定義。`name` は golden / PNG のファイル名・drive の分岐キー、
    /// `desc` は index.html の 1 行説明。
    pub type alias Fixture = { name = String, desc = String }

    /// `name` の drive（root を spawn → 本物の frameStep で組む）を mock Game + UiWorldState 下で
    /// 走らせ、残った UiWorld を renderUi で描画する。drive を record 越しに持ち回すと Flix の
    /// 効果多相が効かない（closure 保存に subeffecting が無い）ので、名前で `driveByName` に分岐する
    /// （match の各腕は効果を合流できる）。
    def renderFixture(rc: Region[r], ctx: SnapshotSupport.Ctx, name: String):
            {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]} \ Fs.FileRead + r =
        SnapshotSupport.withMockGame(ctx#atlas, ctx#texInfo, () ->
            UiWorldState.withState(rc, () -> {
                driveByName(name);
                UiRender.renderUi()
            }))

    /// フィクスチャ名 → drive の副作用。各腕は個別の drive（効果は Fs / Game / State の部分集合）を
    /// 呼び、match が全体の効果を合流する。
    def driveByName(name: String): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) =
        match name {
            case "action_menu_7"        => driveActionMenu7()
            case "action_menu_3"        => driveActionMenu3()
            case "weapon_select"        => driveWeaponSelect()
            case "item_menu_select"     => driveItemMenuSelect()
            case "item_menu_action"     => driveItemMenuAction()
            case "trade_menu"           => driveTradeMenu2()
            case "game_over_menu"       => driveGameOverMenu()
            case "suspend_confirm"      => driveSuspendConfirm()
            case "top_bar_ally"         => applyTopBar(allyFrame(), false)
            case "top_bar_enemy"        => applyTopBar(enemyFrame(), false)
            case "top_bar_wipe"         => applyTopBar(wipeFrame(), false)
            case "top_bar_gather"       => applyTopBar(gatherFrame(), true)
            case "unit_card"            => driveUnitCard()
            case "enemy_card"           => driveEnemyCard()
            case "hud_player_phase"     => driveHudCard(allyFrame())
            case "hud_enemy_phase"      => driveHudCard(enemyFrame())
            case "hud_action_menu"      => driveHudActionMenu()
            case "hud_attack_flow"      => driveHudAttackFlow()
            case "hud_item_menu"        => driveHudItemMenu()
            case "hud_game_over"        => driveHudGameOver()
            case "item_menu_full_top"   => driveItemMenuFull(0)
            case "item_menu_full_bottom" => driveItemMenuFull(4)
            case "trade_menu_4panes"    => driveTradeMenu4()
            case _                       => bug!("unknown snapshot fixture: ${name}")
        }

    /// 全フィクスチャの一覧（name は golden / PNG ファイル名 + driveByName の分岐キー）。
    /// 単体シーン → 実ロジック TopBar → 組み合わせ HUD → 満載・境界、の順に並べる。
    pub def fixtureList(): List[Fixture] =
        {name = "action_menu_7", desc = "アクションメニュー・フル（味方が拾う/あける/階段/攻撃の全条件を満たす）"} ::
        {name = "action_menu_3", desc = "空マスメニュー 3 項目（集合/ターンエンド/中断）"} ::
        {name = "weapon_select", desc = "武器選択（威力/耐久/重さサブライン・苦手バッジ・射程外は淡色）"} ::
        {name = "item_menu_select", desc = "持ち物（本物は 1 カテゴリ表示・◀ 武器 ▶・重量ヘッダ）"} ::
        {name = "item_menu_action", desc = "持ち物サブメニュー（武器選択中＝そうび/なげる/すてる）"} ::
        {name = "trade_menu", desc = "交換メニュー 2 人ぶん（本物の syncPane が末尾に空きスロットを出す）"} ::
        {name = "game_over_menu", desc = "ゲームオーバーのモーダル選択（GameOver フェーズで可視）"} ::
        {name = "suspend_confirm", desc = "中断確認のモーダル（SuspendConfirm フェーズで可視）"} ::
        {name = "top_bar_ally", desc = "上部バー・自軍確定（青帯・青下線・青ドット・自軍フェイズ）"} ::
        {name = "top_bar_enemy", desc = "上部バー・敵軍確定（赤帯・赤下線・赤ドット・ENEMY PHASE）"} ::
        {name = "top_bar_wipe", desc = "上部バー・陣営ワイプ 50%（青ベースに赤 sweep が半分）"} ::
        {name = "top_bar_gather", desc = "上部バー・集合中（▶ + 集合中ラベル）"} ::
        {name = "unit_card", desc = "自軍ユニットカード（選択中味方・Lv/EXP/HP・武器/指輪アイコン）"} ::
        {name = "enemy_card", desc = "敵ユニットカード（WeaponSelect のカーソル上の敵・Lv/EXP 行なし・赤枠）"} ::
        {name = "hud_player_phase", desc = "自軍フェイズ HUD：TopBar(自軍) + ユニットカード"} ::
        {name = "hud_enemy_phase", desc = "敵フェイズ HUD：TopBar(敵軍・赤) + ユニットカード"} ::
        {name = "hud_action_menu", desc = "コマンド選択 HUD：TopBar + アクションメニュー(フル)"} ::
        {name = "hud_attack_flow", desc = "攻撃フロー最盛：TopBar + アクション + 武器選択 + 自軍/敵カード（窓の重なり・z 序列）"} ::
        {name = "hud_item_menu", desc = "アイテム HUD：TopBar + 持ち物メニュー"} ::
        {name = "hud_game_over", desc = "ゲームオーバー HUD：TopBar + モーダル"} ::
        {name = "item_menu_full_top", desc = "持ち物満載・窓の上端を選択（重い在庫の重量ヘッダ色は実ロジック）"} ::
        {name = "item_menu_full_bottom", desc = "持ち物満載・窓の下端を選択（スクロール offset も実ロジック）"} ::
        {name = "trade_menu_4panes", desc = "交換メニュー 4 ペイン満載（空きスロットの出方も実 syncPane 由来）"} :: Nil

    // ════════════════════════════════════════════════════════
    // カタログ由来の実データ（味方 / 敵 / 在庫）でシーンを組む
    // ════════════════════════════════════════════════════════

    /// 味方カタログ（units.json + weapons.json）をロードする。
    pub def unitCatalog(): UnitCatalog.UnitCatalog \ Fs.FileRead =
        UnitCatalog.load(AssetPath.resolve("resources/units.json"), WeaponCatalog.load())

    pub def weaponRes(id: String): UnitCatalog.WeaponResource \ Fs.FileRead =
        WeaponCatalog.lookup(id, WeaponCatalog.load())
    def consumableRes(id: String): Consumable.ConsumableResource \ Fs.FileRead =
        Consumable.lookup(id, Consumable.load())
    def ringRes(id: String): Ring.RingResource \ Fs.FileRead =
        Ring.lookup(id, Ring.load())

    /// 味方 1 体の宣言。id/クラス/位置と、実カタログ id で指定した在庫だけ書けばよい
    /// （`basePlayer` を `| ...` で上書きして使う）。
    pub type alias PlayerSpec = {
        id = Int32, classId = String, gridPos = {x = Int32, y = Int32},
        hp = Int32, waited = Bool, level = Int32, exp = Int32,
        weaponIds = List[String], consumableIds = List[String], ringIds = List[String],
        ringEquipped = Bool, selectedItem = Option[PlayerData.ItemKind]
    }

    /// 既定の味方宣言（在庫は空・Lv5・HP18）。フィクスチャは在庫や選択だけ上書きする。
    pub def basePlayer(id: Int32, classId: String, gridPos: {x = Int32, y = Int32}): PlayerSpec = {
        id = id, classId = classId, gridPos = gridPos, hp = 18, waited = false,
        level = 5, exp = 40, weaponIds = Nil, consumableIds = Nil, ringIds = Nil,
        ringEquipped = false, selectedItem = None
    }

    /// 味方宣言 → 実カタログ由来の `PlayerScene.Data`（本物の frameStep が読む在庫まで詰める）。
    pub def mkPlayer(s: PlayerSpec): PlayerScene.Data \ Fs.FileRead =
        let res = UnitCatalog.lookupUnit(s#classId, unitCatalog());
        ({id = s#id, classId = s#classId, gridPos = s#gridPos, moveTiles = res#moveTiles,
          hp = s#hp, waited = s#waited, attackTargetId = None, resource = res,
          weapons = List.map(weaponRes, s#weaponIds),
          staves = Nil,
          consumables = List.map(consumableRes, s#consumableIds),
          rings = List.map(ringRes, s#ringIds),
          ringEquipped = s#ringEquipped, selectedItem = s#selectedItem,
          moveStepsTaken = 0, facing = Staff.Direction.Down, hidden = false, usedStairs = false,
          level = s#level, exp = s#exp, pendingLevelUp = None, statuses = Nil,
          followUpUsed = false}: PlayerScene.Data)

    /// 敵 1 体を実カタログ由来の `EnemyScene.Data` に組む。`weaponId` は装備武器（None＝素手表示）。
    pub def mkEnemy(id: Int32, resourceId: String, gridPos: {x = Int32, y = Int32}, hp: Int32,
                weaponId: Option[String]): EnemyScene.Data \ Fs.FileRead =
        let res = match EnemyCatalog.get(resourceId, EnemyCatalog.load()) {
            case Some(e) => e
            case None    => bug!("snapshot: enemy '${resourceId}' not in catalog")
        };
        ({id = id, resourceId = resourceId, gridPos = gridPos, alerted = false, homeModuleIdx = 0,
          moveTiles = res#moveTiles, hp = hp, isDying = false, attackTargetId = None, resource = res,
          weapon = Option.map(weaponRes, weaponId), acted = false, prevPos = None, statuses = Nil,
          ring = None, followUpUsed = false, bottleUsed = false}: EnemyScene.Data)

    /// World ルートだけ持つ空シーン。
    pub def worldScene(): Scene[NodeTag] =
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.NoTag))

    /// 味方 1 体を World 配下に足す。
    pub def addPlayer(d: PlayerScene.Data, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(d#id),
            EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.Player(d)), scene)

    /// 敵 1 体を World 配下に足す。`visible` は marker の可視（フォグ判定＝カード/攻撃対象の可否）。
    pub def addEnemy(d: EnemyScene.Data, visible: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        let marker = Marker2D.make(Vec2.zero()) |> CanvasItem.setVisible(visible);
        Scene.addChildAt(MapScene.worldPath(), EnemyScene.enemyName(d#id),
            EngineNode.Marker2DWithState(marker, NodeTag.Enemy(d)), scene)

    /// 床アイテム 1 個を `cell` に貼る（World seed 経由で「拾う」判定が成立する）。
    def addGroundItem(cell: {x = Int32, y = Int32}, kind: ItemData.GroundItemKind,
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        let itemsPath = MapScene.worldName() :: "Items" :: Nil;
        let withParent = match Scene.getEngineNode(itemsPath, scene) {
            case Some(_) => scene
            case None    => Scene.addChildAt(MapScene.worldPath(), "Items",
                                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.NoTag), scene)
        };
        let sprite = Sprite2D.make(GroundItems.spriteOf(kind)#texture, Vec2.zero(), Vec2.one());
        let data: GroundItems.Data =
            {gridPos = cell, itemKey = "snap-ground", item = kind, elapsed = Duration.zero()};
        Scene.addChildAt(itemsPath, "Item_0",
            EngineNode.Sprite2DWithState(sprite, NodeTag.GroundItem(data)), withParent)

    /// 配置済み階段ノードを `cell` に置く（「階段」項目が成立する）。
    def addStairs(cell: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.addNode("Stairs",
            EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()),
                NodeTag.Stairs(({gridPos = cell, placed = true}: Stairs.Data))), scene)

    /// 宝箱は World store 権威（scene ノードを持たない）なので worldMods で `cell` に注入する。
    def chestAtWorld(cell: {x = Int32, y = Int32}, content: ItemData.GroundItemKind): World -> World =
        w -> World.applyCmd(World.Cmd.SpawnChest(
            ({gridPos = cell, chestKey = "wooden", contentId = "snap-chest", content = content}: Chests.Data)), w)

    // ════════════════════════════════════════════════════════
    // spawn / selection の小道具（UiWorldState を直接いじる）
    // ════════════════════════════════════════════════════════

    /// ui.json を読み root を UiWorldState の現 UiWorld へ spawn する（複数 root を同居させられる）。
    pub def spawnUi(path: String): Unit \ (Fs.FileRead + UiWorldState.State) =
        match UiSpec.load(path) {
            case Ok(spec) => let (_, ui2) = UiSpec.spawnRoot(spec, UiWorldState.State.get());
                             UiWorldState.State.put(ui2)
            case Err(_)   => bug!("snapshot: UI spec load failed: ${path}")
        }

    /// ui.json を読み **別 root 名**で spawn する（同じ spec を敵カードとして二枚立てる用途）。
    def spawnAs(path: String, rootName: String): Unit \ (Fs.FileRead + UiWorldState.State) =
        match UiSpec.spawnAssetAs(path, rootName, UiWorldState.State.get()) {
            case Ok((_, ui2)) => UiWorldState.State.put(ui2)
            case Err(_)       => bug!("snapshot: UI spec spawnAs failed: ${path}")
        }

    /// 選択カーソル index を名前パスの list へ書き込む（窓スクロールの下端選択を作る用途）。
    def putSel(listPath: String, idx: Int32): Unit \ UiWorldState.State =
        UiWorldState.State.put(UiStore.putSelection(listPath, idx, UiWorldState.State.get()))

    // ════════════════════════════════════════════════════════
    // 各フィクスチャの drive（データ宣言 → spawn → 本物の frameStep）
    // ════════════════════════════════════════════════════════

    // ── ActionMenu ──

    /// 味方が「拾う/あける/階段/攻撃/アイテム/交換/待機」の全条件を満たす盤面。
    /// 主人公(id0)は床アイテム+階段+宝箱の上に立ち、武器を持ち、隣に味方、射程内に敵。
    def actionFullConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = mkPlayer({weaponIds = "iron_sword" :: Nil | basePlayer(0, "knight", {x = 1, y = 1})});
        let ally = mkPlayer(basePlayer(1, "paladin", {x = 2, y = 1}));
        let enemy = mkEnemy(9, "fighter_t1", {x = 1, y = 2}, 12, Some("iron_sword"));
        let scene = worldScene()
            |> addPlayer(lord)
            |> addPlayer(ally)
            |> addEnemy(enemy, true)
            |> addGroundItem({x = 1, y = 1}, ItemData.GroundItemKind.WeaponItem(weaponRes("iron_sword")))
            |> addStairs({x = 1, y = 1});
        {phase = TurnPhase.Phase.ActionSelect, selectedId = Some(0),
         worldMods = chestAtWorld({x = 1, y = 1}, ItemData.GroundItemKind.WeaponItem(weaponRes("steel_lance")))
         | SnapshotHarness.config(scene)}

    def driveActionMenu7(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) =
        let cfg = actionFullConfig();
        spawnUi(ActionMenuUi.specPath());
        discard SnapshotHarness.withMocks(cfg, () -> ActionMenuUi.frameStep(dt(), cfg#scene))

    /// 空マス（未選択）メニュー: gather / turnEnd / suspend の 3 項目。
    def actionSpaceConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = mkPlayer(basePlayer(0, "knight", {x = 1, y = 1}));
        let ally = mkPlayer(basePlayer(1, "paladin", {x = 4, y = 4}));
        let scene = worldScene() |> addPlayer(lord) |> addPlayer(ally);
        {phase = TurnPhase.Phase.ActionSelect, selectedId = None | SnapshotHarness.config(scene)}

    def driveActionMenu3(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) =
        let cfg = actionSpaceConfig();
        spawnUi(ActionMenuUi.specPath());
        discard SnapshotHarness.withMocks(cfg, () -> ActionMenuUi.frameStep(dt(), cfg#scene))

    // ── WeaponSelect ──

    /// 武器 2 本の味方＋射程内の敵。カーソルを敵に乗せて「対象上」を作る。
    def weaponSelectConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = mkPlayer({weaponIds = "iron_sword" :: "steel_lance" :: Nil
                             | basePlayer(0, "knight", {x = 1, y = 1})});
        let enemy = mkEnemy(9, "fighter_t1", {x = 1, y = 2}, 12, Some("iron_sword"));
        let scene = worldScene() |> addPlayer(lord) |> addEnemy(enemy, true);
        {phase = TurnPhase.Phase.WeaponSelect, selectedId = Some(0), cursor = {x = 1, y = 2}
         | SnapshotHarness.config(scene)}

    def driveWeaponSelect(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = weaponSelectConfig();
        spawnUi(WeaponSelectUi.specPath());
        discard SnapshotHarness.withMocks(cfg, () -> WeaponSelectUi.frameStep(dt(), cfg#scene))

    // ── ItemMenu ──

    /// 武器 3 本＋消費＋指輪を持つ味方。本物の ItemMenu は 1 カテゴリ表示なので武器カテゴリが出る
    /// （◀ 武器 ▶ の切替ヒント・重量ヘッダは実ロジック）。
    def itemSelectConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = mkPlayer({weaponIds = "iron_sword" :: "steel_lance" :: "silver_sword" :: Nil,
                             consumableIds = "vulnerary" :: Nil, ringIds = "power_ring" :: Nil
                             | basePlayer(0, "knight", {x = 1, y = 1})});
        let scene = worldScene() |> addPlayer(lord);
        {phase = TurnPhase.Phase.ItemSelect, selectedId = Some(0), itemCategory = 0
         | SnapshotHarness.config(scene)}

    def driveItemMenuSelect(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = itemSelectConfig();
        spawnUi(ItemMenuUi.specPath());
        discard SnapshotHarness.withMocks(cfg, () -> ItemMenuUi.frameStep(dt(), cfg#scene))

    /// サブメニュー（武器を選んだ後）: そうび / なげる / すてる。
    def itemActionConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = mkPlayer({weaponIds = "iron_sword" :: Nil,
                             selectedItem = Some(PlayerData.ItemKind.Weapon(0))
                             | basePlayer(0, "knight", {x = 1, y = 1})});
        let scene = worldScene() |> addPlayer(lord);
        {phase = TurnPhase.Phase.ItemActionSelect, selectedId = Some(0) | SnapshotHarness.config(scene)}

    def driveItemMenuAction(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = itemActionConfig();
        spawnUi(ItemMenuUi.specPath());
        discard SnapshotHarness.withMocks(cfg, () -> ItemMenuUi.frameStep(dt(), cfg#scene))

    /// 満載シーン: 武器 5 本を持たせ、窓（3 行）をスクロールさせる。`sel` は選択 index。
    def itemFullConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = mkPlayer({hp = 22,
                             weaponIds = "silver_sword" :: "killing_edge" :: "iron_sword"
                                          :: "steel_axe" :: "iron_bow" :: Nil
                             | basePlayer(0, "knight", {x = 1, y = 1})});
        let scene = worldScene() |> addPlayer(lord);
        {phase = TurnPhase.Phase.ItemSelect, selectedId = Some(0), itemCategory = 0
         | SnapshotHarness.config(scene)}

    def driveItemMenuFull(sel: Int32): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = itemFullConfig();
        spawnUi(ItemMenuUi.specPath());
        // 選択 index を先に注入してから frameStep で窓 offset・ハイライトを実ロジックで決めさせる。
        putSel("ItemMenu/panel/menu", sel);
        discard SnapshotHarness.withMocks(cfg, () -> ItemMenuUi.frameStep(dt(), cfg#scene))

    // ── TradeMenu ──

    /// 2 人交換。各ペインは在庫＋（満杯でないので）末尾に空きスロット行が出る。
    def trade2Config(): SnapshotHarness.Config \ Fs.FileRead =
        let p0 = mkPlayer({weaponIds = "iron_sword" :: Nil, consumableIds = "vulnerary" :: Nil
                           | basePlayer(0, "knight", {x = 1, y = 1})});
        let p1 = mkPlayer({weaponIds = "steel_lance" :: Nil, consumableIds = "great_vulnerary" :: Nil
                           | basePlayer(1, "paladin", {x = 2, y = 1})});
        let scene = worldScene() |> addPlayer(p0) |> addPlayer(p1);
        let trade = {members = 0 :: 1 :: Nil, focus = 0 | TradeMenuUi.defaultPanelData()};
        {phase = TurnPhase.Phase.TradeInventory, trade = trade | SnapshotHarness.config(scene)}

    def driveTradeMenu2(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = trade2Config();
        spawnUi(TradeMenuUi.specPath());
        discard SnapshotHarness.withMocks(cfg, () -> TradeMenuUi.frameStep(dt(), cfg#scene))

    /// 4 人交換満載。各ペインの空きスロットの出方（在庫本数ぶんだけ 1 行余す）が実 syncPane 由来。
    def trade4Config(): SnapshotHarness.Config \ Fs.FileRead =
        let p0 = mkPlayer({weaponIds = "iron_sword" :: Nil, consumableIds = "vulnerary" :: Nil,
                           ringIds = "power_ring" :: Nil | basePlayer(0, "knight", {x = 1, y = 1})});
        let p1 = mkPlayer({weaponIds = "steel_lance" :: Nil, consumableIds = "great_vulnerary" :: Nil
                           | basePlayer(1, "paladin", {x = 2, y = 1})});
        let p2 = mkPlayer({weaponIds = "steel_axe" :: "iron_bow" :: Nil
                           | basePlayer(2, "knight", {x = 3, y = 1})});
        let p3 = mkPlayer({consumableIds = "elixir" :: "vulnerary" :: Nil
                           | basePlayer(3, "paladin", {x = 4, y = 1})});
        let scene = worldScene() |> addPlayer(p0) |> addPlayer(p1) |> addPlayer(p2) |> addPlayer(p3);
        let trade = {members = 0 :: 1 :: 2 :: 3 :: Nil, focus = 0 | TradeMenuUi.defaultPanelData()};
        {phase = TurnPhase.Phase.TradeInventory, trade = trade | SnapshotHarness.config(scene)}

    def driveTradeMenu4(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = trade4Config();
        spawnUi(TradeMenuUi.specPath());
        discard SnapshotHarness.withMocks(cfg, () -> TradeMenuUi.frameStep(dt(), cfg#scene))

    // ── GameOverMenu / SuspendConfirm（モーダル：可視トグル + ハイライトだけ実ロジック）──

    def driveGameOverMenu(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = {simPhase = SimPhase.GameOver | SnapshotHarness.config(worldScene())};
        spawnUi(GameOverMenuUi.specPath());
        discard SnapshotHarness.withMocks(cfg, () -> GameOverMenuUi.frameStep(dt(), cfg#scene))

    def driveSuspendConfirm(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = {phase = TurnPhase.Phase.SuspendConfirm | SnapshotHarness.config(worldScene())};
        spawnUi(SuspendConfirmUi.specPath());
        discard SnapshotHarness.withMocks(cfg, () -> SuspendConfirmUi.frameStep(dt(), cfg#scene))

    // ── UnitCard / EnemyCard（frameStep が対象を解決して両カードを描く）──

    /// 選択中味方のカードを解決させる config（ActionSelect＝カーソル依存でない経路）。
    def unitCardConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = mkPlayer({weaponIds = "iron_sword" :: Nil, ringIds = "power_ring" :: Nil,
                             ringEquipped = true | basePlayer(0, "knight", {x = 1, y = 1})});
        let scene = worldScene() |> addPlayer(lord);
        {phase = TurnPhase.Phase.ActionSelect, selectedId = Some(0) | SnapshotHarness.config(scene)}

    /// 両カード root を spawn する（frameStep は対象なし側を隠す）。
    def spawnCards(): Unit \ (Fs.FileRead + UiWorldState.State) =
        spawnUi(UnitCardUi.specPath());
        spawnAs(UnitCardUi.specPath(), UnitCardUi.enemyRootName())

    def driveUnitCard(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) =
        let cfg = unitCardConfig();
        spawnCards();
        discard SnapshotHarness.withMocks(cfg, () -> UnitCardUi.frameStep(dt(), cfg#scene))

    /// WeaponSelect のカーソル上の敵カードを解決させる config（味方カードは未選択で隠れる）。
    def enemyCardConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let enemy = mkEnemy(9, "fighter_t1", {x = 3, y = 3}, 12, Some("iron_sword"));
        let scene = worldScene() |> addEnemy(enemy, true);
        {phase = TurnPhase.Phase.WeaponSelect, selectedId = None, cursor = {x = 3, y = 3}
         | SnapshotHarness.config(scene)}

    def driveEnemyCard(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) =
        let cfg = enemyCardConfig();
        spawnCards();
        discard SnapshotHarness.withMocks(cfg, () -> UnitCardUi.frameStep(dt(), cfg#scene))

    // ════════════════════════════════════════════════════════
    // TopBar（実ロジック駆動：advance → applyFrame は step が毎フレーム通す実経路）
    // ════════════════════════════════════════════════════════

    /// フロア表示だけ入れた未確定の初期状態（起動直後・shown=None・ワイプなし）。
    def topBarState(floorLabel: String, floorName: String): TopBarState.Data =
        {shown = None, animTarget = None, anim = Duration.zero(), hold = Duration.zero(),
         floorLabel = floorLabel, floorName = floorName}

    /// 自軍確定 Frame。起動直後（shown=None）は advance が即確定するので 1 回で青ベースが出る。
    def allyFrame(): TopBarUi.Frame =
        TopBarUi.advance(dt(), TurnPhase.Phase.PlayerCursor, topBarState("B1", "はじまりの洞窟"))

    /// 敵軍確定 Frame。EnemyTurn を即確定 → 帯/下線/ドット/フェイズ和文がすべて赤ベースになる。
    def enemyFrame(): TopBarUi.Frame =
        TopBarUi.advance(dt(), TurnPhase.Phase.EnemyTurn, topBarState("B1", "はじまりの洞窟"))

    /// ワイプ 50% の Frame。自軍確定 → 敵ターン開始でワイプ点火 → 250ms 進めて中間（progress=0.5）。
    def wipeFrame(): TopBarUi.Frame =
        let confirmed = TopBarUi.advance(dt(), TurnPhase.Phase.PlayerCursor,
                                         topBarState("B2", "凍てつく回廊"));
        let ignited = TopBarUi.advance(dt(), TurnPhase.Phase.EnemyTurn, confirmed#data);
        TopBarUi.advance(Duration.millis(250), TurnPhase.Phase.EnemyTurn, ignited#data)

    /// 集合中の Frame。GatherMove は自軍扱いで即確定し、可視の集合中表示は applyFrame の gathering=true で出す。
    def gatherFrame(): TopBarUi.Frame =
        TopBarUi.advance(dt(), TurnPhase.Phase.GatherMove, topBarState("B2", "凍てつく回廊"))

    /// TopBar root を spawn し、Frame を実ロジック（applyFrame）で UiWorldState の UiWorld へ塗る。
    def applyTopBar(frame: TopBarUi.Frame, gathering: Bool): Unit \ (Fs.FileRead + UiWorldState.State) =
        spawnUi(TopBarUi.specPath());
        let ui = UiStore.setVisible("TopBar", true, UiWorldState.State.get());
        UiWorldState.State.put(TopBarUi.applyFrame(frame, gathering, ui))

    // ════════════════════════════════════════════════════════
    // 組み合わせ HUD（複数 root を 1 つの UiWorld に立て、各 frameStep を順に走らせる）
    // ════════════════════════════════════════════════════════

    /// TopBar + ユニットカード（選択中味方）。topbar の Frame で自軍/敵軍を切り替える。
    def driveHudCard(frame: TopBarUi.Frame): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) =
        let cfg = unitCardConfig();
        applyTopBar(frame, false);
        spawnCards();
        discard SnapshotHarness.withMocks(cfg, () -> UnitCardUi.frameStep(dt(), cfg#scene))

    /// TopBar + アクションメニュー（フル）。
    def driveHudActionMenu(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) =
        let cfg = actionFullConfig();
        applyTopBar(allyFrame(), false);
        spawnUi(ActionMenuUi.specPath());
        discard SnapshotHarness.withMocks(cfg, () -> ActionMenuUi.frameStep(dt(), cfg#scene))

    /// 攻撃フロー最盛：WeaponSelect フェーズで TopBar + アクション + 武器選択 + 自軍/敵カードが同居。
    /// ActionMenu は WeaponSelect フェーズでも可視（随伴ウィンドウ）なので同じ config で全部が生きる。
    def driveHudAttackFlow(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) =
        let lord = mkPlayer({weaponIds = "iron_sword" :: "steel_lance" :: Nil,
                             ringIds = "power_ring" :: Nil, ringEquipped = true
                             | basePlayer(0, "knight", {x = 1, y = 1})});
        let ally = mkPlayer(basePlayer(1, "paladin", {x = 2, y = 1}));
        let enemy = mkEnemy(9, "fighter_t1", {x = 1, y = 2}, 12, Some("iron_sword"));
        let scene = worldScene() |> addPlayer(lord) |> addPlayer(ally) |> addEnemy(enemy, true);
        let cfg = {phase = TurnPhase.Phase.WeaponSelect, selectedId = Some(0), cursor = {x = 1, y = 2}
                   | SnapshotHarness.config(scene)};
        applyTopBar(allyFrame(), false);
        spawnUi(ActionMenuUi.specPath());
        spawnUi(WeaponSelectUi.specPath());
        spawnCards();
        discard SnapshotHarness.withMocks(cfg, () -> {
            discard ActionMenuUi.frameStep(dt(), cfg#scene);
            discard WeaponSelectUi.frameStep(dt(), cfg#scene);
            UnitCardUi.frameStep(dt(), cfg#scene)
        })

    /// TopBar + 持ち物メニュー。
    def driveHudItemMenu(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = itemSelectConfig();
        applyTopBar(allyFrame(), false);
        spawnUi(ItemMenuUi.specPath());
        discard SnapshotHarness.withMocks(cfg, () -> ItemMenuUi.frameStep(dt(), cfg#scene))

    /// TopBar(敵軍) + ゲームオーバーモーダル。
    def driveHudGameOver(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = {simPhase = SimPhase.GameOver | SnapshotHarness.config(worldScene())};
        applyTopBar(enemyFrame(), false);
        spawnUi(GameOverMenuUi.specPath());
        discard SnapshotHarness.withMocks(cfg, () -> GameOverMenuUi.frameStep(dt(), cfg#scene))
}
