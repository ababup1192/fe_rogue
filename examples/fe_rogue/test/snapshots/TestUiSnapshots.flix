// TestUiSnapshots — 各 UI（ActionMenu / WeaponSelect / ItemMenu / TradeMenu / GameOverMenu /
// SuspendConfirm / TopBar / UnitCard / EnemyCard）を代表的な状態で組み、renderUi の描画出力を
// golden と比較しつつ build/snapshots/ に PNG を生成する。
//
// 方針: フィクスチャは **データを宣言するだけ**で、UI の中身は本物のゲームコードが組む。各シーンは
//   1. UiSpec.spawnRoot で ui.json の骨組みだけ立て、
//   2. カタログ由来の実データ（味方/敵/在庫）を World store へ seed し、
//   3. `SnapshotHarness.withMocks(config, () -> XxxUi.frameStep(dt()))` で本物の frameStep に
//      可視・スロット流し込み・幅フィット・重量色・空きスロット・カード解決を組ませる。
// これで「敵フェイズが赤い」「満杯でないペインに空きスロットが出る」等が実ロジックの帰結になり、
// 手塗りの嘘が golden に混じらない。TopBar だけは frameStep でなく `advance → applyFrame`
// （同じ実経路）をフィクスチャから直接呼んで配色を作る。
//
// 複数 root を同じ UiWorld に spawn すれば renderUi が可視 root を全合成するので、組み合わせ
// シーン（HUD 全部乗せ）は各 root の frameStep を 1 つの UiWorld 上で順に走らせるだけで作る。
// アトラス生成は重いので 1 つの @Test で 1 度だけ行い、全フィクスチャを回す。
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
    // 出力解像度 = design × outScale。実機 GPU 描画と同じくドット絵をくっきり出すため大きめに拡大する。
    def outScale(): Int32 = 8i32
    /// index.html の img CSS 幅（Retina 2x 前提で実ピクセル幅 ÷ 2。ブラウザ側の補間をゼロにする）。
    pub def outWidthPx(): Int32 = designW() * outScale() / 2i32

    /// 1 フレームぶんの経過（frameStep / advance の delta）。
    pub def dt(): Duration.Duration = Duration.millis(16)

    // ════════════════════════════════════════════════════════
    // オーケストレータ
    // ════════════════════════════════════════════════════════

    /// 全 UI スナップショットを 1 度のアトラス生成で処理する。撮る対象は SnapshotCatalog の
    /// PNG エントリ、drive は名前で driveByName に分岐する。golden 不一致があればそのリストを
    /// assert で提示して落ちる（更新モードでは golden を書き直して pass）。撮り終えたら
    /// ReferenceSite でカタログ全体（PNG+GIF）を回遊できる HTML サイトに生成し直す。
    @Test
    def testUiSnapshots(): Unit \ {Assert, Fs.FileRead, Fs.FileWrite, IO} = region rc {
        let atlas = HeadlessFont.buildUiAtlas(ttfPath(), joyoPath());
        let texPaths = SnapshotSupport.buildTexturePaths();
        let texInfo = SnapshotSupport.buildTextureInfo(texPaths, atlasDim());
        let ctx: SnapshotSupport.Ctx = {
            atlas = atlas, atlasDim = atlasDim(), ttfPath = ttfPath(), texInfo = texInfo, texPaths = texPaths,
            background = clearColor(), scale = outScale(), design = designSize()
        };
        // 各シーンを撮影しつつ幾何リンタ（RenderLint）を走らせる。結果は (名前, golden 相違, Finding 列)。
        let results = SnapshotCatalog.pngEntries() |> List.map(entry -> renderAndLint(rc, ctx, entry));
        let goldenFailures = results |> List.filterMap(r -> {let (_n, gf, _fs) = r; gf});
        // 抑制タグ（lint-allow:Rx）で許していない Finding だけを fail 対象にする。
        let activeFindings = results
            |> List.flatMap(r -> {let (_n, _gf, fs) = r; List.filter(f -> not f#suppressed, fs)});
        // GIF は素の flix test では再生成しないが、test/snapshots/gifs/（コミット対象）に既にあれば
        // build/snapshots/ へコピーしてページに常時表示させる（恒久化。無ければ何もしない）。
        SnapshotSupport.syncGifs(SnapshotCatalog.gifEntries() |> List.map(entry -> entry#name));
        // lint 結果を name→バッジにしてダッシュボード（カード）へ渡す。
        let lintByName = results
            |> List.foldLeft((m, r) -> {let (n, _gf, fs) = r; Map.insert(n, badgeOf(fs), m)}, Map.empty());
        ReferenceSite.generate(siteConfig(), catalogItemsWithLint(lintByName));
        // golden 相違・有効 lint 違反のどちらも 0 でなければ、全詳細を並べて落とす。
        Assert.assertEq(expected = (Nil: List[String]),
            List.append(goldenFailures, List.map(formatFinding, activeFindings)))
    }

    /// カタログのタグから抑制 rule 名（`lint-allow:R1` → `R1`）だけを抜き出す。
    def lintAllow(tags: List[String]): List[String] =
        tags |> List.filterMap(t ->
            if (String.startsWith(prefix = "lint-allow:", t)) Some(String.drop(11, t)) else None)

    /// Finding 列を 1 枚のバッジ（有効/抑制の件数＋詳細）へ。
    def badgeOf(findings: List[RenderLint.Finding]): ReferenceSite.LintBadge =
        let active = List.filter(f -> not f#suppressed, findings);
        let supp = List.filter(f -> f#suppressed, findings);
        {checked = true, findingCount = List.length(active), suppressedCount = List.length(supp),
         details = List.append(List.map(f -> detailLine(false, f), active),
                               List.map(f -> detailLine(true, f), supp))}

    def detailLine(suppressed: Bool, f: RenderLint.Finding): String =
        "${if (suppressed) "[抑制] " else ""}${f#rule}: ${f#detail}"

    /// assert メッセージ用の 1 行（シーン名つき）。
    def formatFinding(f: RenderLint.Finding): String =
        "[${f#sceneName}] ${f#rule} ${f#severity}: ${f#detail}"

    /// カタログ Item に lint バッジを差し込む（GIF など未検査項目は既定 noLint のまま）。
    pub def catalogItemsWithLint(lintByName: Map[String, ReferenceSite.LintBadge]): List[ReferenceSite.Item] \ IO =
        catalogItems() |> List.map(item ->
            {lint = Option.getWithDefault(ReferenceSite.noLint(), Map.get(item#name, lintByName)) | item})

    /// ReferenceSite の設定。出力先・見出し・Retina 前提の CSS 縮小率（実ピクセル ÷ 2）。
    pub def siteConfig(): ReferenceSite.Config =
        {outDir = "build/snapshots", title = "fe_rogue UI snapshots", cssScale = 2i32}

    /// カタログ全枚を ReferenceSite の表示用 Item 列へ。PNG/GIF で実ピクセル幅が違うので両方渡す
    /// （GIF が未生成なら生成コマンドの案内をカードに出す）。ストリップが生成済みの GIF は
    /// コマ送りビューア情報（filmstripByName）を添えてインタラクティブなカードにする。
    pub def catalogItems(): List[ReferenceSite.Item] \ IO =
        SnapshotCatalog.toItems({pngPxWidth = outWidthPx(), gifPxWidth = TestGifSnapshots.gifWidthPx()},
            "未生成。<code>FE_ROGUE_SNAPSHOT_GIF=1 FE_ROGUE_SNAPSHOT_UPDATE=1 flix test</code> で生成できます。",
            TestGifSnapshots.filmstripByName())

    /// 1 シーンを撮影し（golden 比較 + PNG 出力）、同じ UiWorld へ幾何リンタをかける。
    /// drive → renderUi → build/snapshots へ生成する、の後に、描画に使ったのと同じ UiWorld を
    /// SnapshotLint で構造データへ射影して RenderLint.check する（描画には一切影響しない検査のみ）。
    /// 返り値は (名前, golden 相違 Option, Finding 列)。
    /// drive を record 越しに持ち回すと効果多相が効かないので名前で `driveByName` に分岐する。
    def renderAndLint(rc: Region[r], ctx: SnapshotSupport.Ctx, entry: SnapshotCatalog.Entry):
            (String, Option[String], List[RenderLint.Finding]) \ (IO + Fs.FileRead + Fs.FileWrite + r) =
        // ミニマップは renderUi 経路でなく `MinimapDriver.minimapDrawList`（純粋）を宣言フィクスチャで
        // 直接ラスタライズする。UiWorld も lint も持たない（幾何は minimapDrawList 内で確定）。
        if (isMinimapEntry(entry#name)) {
            let goldenFail = SnapshotSupport.snapshot(ctx, entry#name, minimapRendered(entry#name));
            (entry#name, goldenFail, (Nil: List[RenderLint.Finding]))
        } else renderUiEntry(rc, ctx, entry)

    /// renderUi 経路のシーン（HUD/メニュー各種）を撮影して lint をかける本体。
    def renderUiEntry(rc: Region[r], ctx: SnapshotSupport.Ctx, entry: SnapshotCatalog.Entry):
            (String, Option[String], List[RenderLint.Finding]) \ (IO + Fs.FileRead + Fs.FileWrite + r) =
        let bundle = SnapshotSupport.withMockGame(ctx#atlas, ctx#texInfo, () ->
            UiWorldState.withState(rc, () -> {
                driveByName(entry#name);
                let rendered = UiHud.renderUi();
                let ui = UiWorldState.State.get();
                let input = SnapshotLint.buildInput(entry#name, lintAllow(entry#tags),
                    designSize()#x, designSize()#y, ui);
                {drawables = rendered#drawables, polygons = rendered#polygons,
                 findings = RenderLint.check(input)}
            }));
        let goldenFail = SnapshotSupport.snapshot(ctx, entry#name,
            {drawables = bundle#drawables, polygons = bundle#polygons});
        (entry#name, goldenFail, bundle#findings)

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
            case "title_menu"           => driveTitleMenu()
            case "character_select"     => driveCharacterSelect()
            case "log_lines"            => driveLogLines()
            case "turn_end_hold_50"     => driveTurnEndHold()
            case "item_pickup_popup"    => driveItemPickupPopup()
            case "battle_panel"         => driveBattlePanel()
            case "level_up_panel"       => driveLevelUpPanel()
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

    // ════════════════════════════════════════════════════════
    // カタログ由来の実データ（味方 / 敵 / 在庫）で World を組む
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

    /// 味方宣言 → 実カタログ由来の `PlayerDriver.Data`（本物の frameStep が読む在庫まで詰める）。
    pub def mkPlayer(s: PlayerSpec): PlayerDriver.Data \ Fs.FileRead =
        let res = UnitCatalog.lookupUnit(s#classId, unitCatalog());
        ({id = s#id, classId = s#classId, gridPos = s#gridPos, moveTiles = res#moveTiles,
          hp = s#hp, waited = s#waited, attackTargetId = None, resource = res,
          weapons = List.map(weaponRes, s#weaponIds),
          staves = Nil,
          consumables = List.map(consumableRes, s#consumableIds),
          rings = List.map(ringRes, s#ringIds),
          ringEquipped = s#ringEquipped, selectedItem = s#selectedItem,
          moveStepsTaken = 0, facing = Dir4.Down, hidden = false, usedStairs = false,
          level = s#level, exp = s#exp, pendingLevelUp = None, statuses = Nil,
          followUpUsed = false}: PlayerDriver.Data)

    /// 敵 1 体を実カタログ由来の `EnemyDriver.Data` に組む。`weaponId` は装備武器（None＝素手表示）。
    pub def mkEnemy(id: Int32, resourceId: String, gridPos: {x = Int32, y = Int32}, hp: Int32,
                weaponId: Option[String]): EnemyDriver.Data \ Fs.FileRead =
        let res = match EnemyCatalog.get(resourceId, EnemyCatalog.load()) {
            case Some(e) => e
            case None    => bug!("snapshot: enemy '${resourceId}' not in catalog")
        };
        ({id = id, resourceId = resourceId, gridPos = gridPos, alerted = false, homeModuleIdx = 0,
          moveTiles = res#moveTiles, hp = hp, isDying = false, attackTargetId = None, resource = res,
          weapon = Option.map(weaponRes, weaponId), acted = false, prevPos = None, statuses = Nil,
          ring = None, followUpUsed = false, bottleUsed = false}: EnemyDriver.Data)

    /// 駒も盤面も無い空の World。各フィクスチャが addPlayer / addEnemy / 配置物 seed で組み上げる。
    pub def emptyWorld(): World = World.empty()

    /// Cmd 列を World へ順に適用する（production と同じ applyCmd を通す）。
    def applyAll(cmds: List[World.Cmd], w: World): World =
        List.foldLeft((acc, c) -> World.applyCmd(c, acc), w, cmds)

    /// 味方 1 体を World store へ seed する。PartyQuery / WorldQuery が読む全 store
    /// （dataFromWorld の gate 16 store + selectedItem / pendingLevelUp / hidden / attackTarget）を
    /// `d` と同値で書くので、World から再構築した Data は `d` と一致する。
    pub def addPlayer(d: PlayerDriver.Data, w: World): World =
        let ref = World.EntityRef.Player(d#id);
        let seeded = applyAll(
            World.Cmd.Spawn(ref)
                :: World.Cmd.Move(ref, d#gridPos)
                :: World.Cmd.SetRenderPos(ref, MapSnapshot.cellCenter(d#gridPos))
                :: World.Cmd.SetHp(ref, d#hp)
                :: World.Cmd.SetWaited(ref, d#waited)
                :: World.Cmd.SetUsedStairs(ref, d#usedStairs)
                :: World.Cmd.SetFollowUpUsed(ref, d#followUpUsed)
                :: World.Cmd.SetProgress(ref, d#level, d#exp)
                :: World.Cmd.SetWeapons(ref, d#weapons)
                :: World.Cmd.SetBaseStats(ref, Combat.baseStatsFrom(d#resource))
                :: World.Cmd.SetMoveTiles(ref, d#moveTiles)
                :: World.Cmd.SetStaves(ref, d#staves)
                :: World.Cmd.SetConsumables(ref, d#consumables)
                :: World.Cmd.SetRings(ref, d#rings)
                :: World.Cmd.SetRingEquipped(ref, d#ringEquipped)
                :: World.Cmd.SetWeaponView(ref, PlayerDriver.equippedWeaponView(d))
                :: World.Cmd.SetRingBonus(ref, PlayerDriver.equippedRingBonus(d))
                :: World.Cmd.SetGrowth(d#id, {base = LevelSystem.statsOf(d#resource),
                                              rates = d#resource#growthRates,
                                              name = d#resource#description})
                :: World.Cmd.SetClassId(d#id, d#classId)
                :: World.Cmd.SetPlayerResource(d#id, d#resource)
                :: World.Cmd.SetFacing(d#id, d#facing)
                :: World.Cmd.SetMoveSteps(d#id, d#moveStepsTaken)
                :: World.Cmd.SetSelectedItem(d#id, d#selectedItem)
                :: World.Cmd.SetPendingLevelUp(d#id, d#pendingLevelUp)
                :: World.Cmd.SetHidden(ref, d#hidden)
                :: Nil, w);
        match d#attackTargetId {
            case Some(t) => World.applyCmd(World.Cmd.SetAttackTarget(ref, t), seeded)
            case None    => seeded
        }

    /// 敵 1 体を World store へ seed する（addPlayer の敵版）。可視はフォグ導出なので、
    /// 「見えている敵」を要するシーンは `boardWorld` を重ねて同室のプレイヤーで部屋を点灯させる。
    pub def addEnemy(d: EnemyDriver.Data, w: World): World =
        let ref = World.EntityRef.Enemy(d#id);
        let seeded = applyAll(
            World.Cmd.Spawn(ref)
                :: World.Cmd.Move(ref, d#gridPos)
                :: World.Cmd.SetRenderPos(ref, MapSnapshot.cellCenter(d#gridPos))
                :: World.Cmd.SetHp(ref, d#hp)
                :: World.Cmd.SetAlerted(ref, d#alerted)
                :: World.Cmd.SetActed(ref, d#acted)
                :: World.Cmd.SetBottleUsed(ref, d#bottleUsed)
                :: World.Cmd.SetFollowUpUsed(ref, d#followUpUsed)
                :: World.Cmd.SetWeapons(ref, Option.toList(d#weapon))
                :: World.Cmd.SetBaseStats(ref, Combat.baseStatsFrom(d#resource))
                :: World.Cmd.SetMoveTiles(ref, d#moveTiles)
                :: World.Cmd.SetWeaponView(ref, EnemyDriver.equippedWeaponView(d))
                :: World.Cmd.SetRingBonus(ref, EnemyDriver.equippedRingBonus(d))
                :: World.Cmd.SetEffectRule(d#id, d#resource#effectRule)
                :: World.Cmd.SetEnemyRing(d#id, d#ring)
                :: World.Cmd.SetEnemyProfile(d#id, {resourceId = d#resourceId,
                                                    homeModuleIdx = d#homeModuleIdx})
                :: World.Cmd.SetEnemyResource(d#id, d#resource)
                :: Nil, w);
        match d#attackTargetId {
            case Some(t) => World.applyCmd(World.Cmd.SetAttackTarget(ref, t), seeded)
            case None    => seeded
        }

    /// 床アイテム 1 個を `cell` へ seed する（「拾う」判定の World 権威）。
    def addGroundItem(cell: {x = Int32, y = Int32}, kind: ItemData.GroundItemKind, w: World): World =
        World.applyCmd(World.Cmd.SpawnItem(
            ({gridPos = cell, itemKey = "snap-ground", item = kind,
              elapsed = Duration.zero()}: GroundItems.Data)), w)

    /// 配置済み階段を `cell` に置く（「階段」項目が成立する）。
    def addStairs(cell: {x = Int32, y = Int32}, w: World): World =
        World.applyCmd(World.Cmd.SetStairs(Some(cell)), w)

    /// 宝箱を `cell` に置く（「あける」項目が成立する）。
    def addChest(cell: {x = Int32, y = Int32}, content: ItemData.GroundItemKind, w: World): World =
        World.applyCmd(World.Cmd.SpawnChest(
            ({gridPos = cell, chestKey = "wooden", contentId = "snap-chest",
              content = content}: Chests.Data)), w)

    /// 盤面（13×13 の 1 部屋）を World へ seed する。敵可視はフォグの明るい穴×
    /// 敵位置の World 導出なので、敵カード等の「見えている敵」を要する scenario はこれを重ねる
    /// （プレイヤーと同室の敵が点灯＝可視になる）。
    def boardWorld(w: World): World =
        applyAll(TestWorldFixtures.boardCmds({w = 13, h = 13}, None), w)

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

    /// 選択カーソル index を名前パスの list へ書き込む（表示範囲スクロールの下端選択を作る用途）。
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
        let world = emptyWorld()
            |> addPlayer(lord)
            |> addPlayer(ally)
            |> addEnemy(enemy)
            |> addGroundItem({x = 1, y = 1}, ItemData.GroundItemKind.WeaponItem(weaponRes("iron_sword")))
            |> addStairs({x = 1, y = 1})
            |> addChest({x = 1, y = 1}, ItemData.GroundItemKind.WeaponItem(weaponRes("steel_lance")));
        {phase = TurnPhase.Phase.ActionSelect, selectedId = Some(0) | SnapshotHarness.config(world)}

    def driveActionMenu7(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) =
        let cfg = actionFullConfig();
        spawnUi(ActionMenuUi.specPath());
        SnapshotHarness.withMocks(cfg, () -> ActionMenuUi.frameStep(dt()))

    /// 空マス（未選択）メニュー: gather / turnEnd / suspend の 3 項目。
    def actionSpaceConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = mkPlayer(basePlayer(0, "knight", {x = 1, y = 1}));
        let ally = mkPlayer(basePlayer(1, "paladin", {x = 4, y = 4}));
        let world = emptyWorld() |> addPlayer(lord) |> addPlayer(ally);
        {phase = TurnPhase.Phase.ActionSelect, selectedId = None | SnapshotHarness.config(world)}

    def driveActionMenu3(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) =
        let cfg = actionSpaceConfig();
        spawnUi(ActionMenuUi.specPath());
        SnapshotHarness.withMocks(cfg, () -> ActionMenuUi.frameStep(dt()))

    // ── WeaponSelect ──

    /// 武器 2 本の味方＋射程内の敵。カーソルを敵に乗せて「対象上」を作る。
    def weaponSelectConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = mkPlayer({weaponIds = "iron_sword" :: "steel_lance" :: Nil
                             | basePlayer(0, "knight", {x = 1, y = 1})});
        let enemy = mkEnemy(9, "fighter_t1", {x = 1, y = 2}, 12, Some("iron_sword"));
        let world = emptyWorld() |> addPlayer(lord) |> addEnemy(enemy);
        {phase = TurnPhase.Phase.WeaponSelect, selectedId = Some(0), cursor = {x = 1, y = 2}
         | SnapshotHarness.config(world)}

    def driveWeaponSelect(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = weaponSelectConfig();
        spawnUi(WeaponSelectUi.specPath());
        SnapshotHarness.withMocks(cfg, () -> WeaponSelectUi.frameStep(dt()))

    // ── ItemMenu ──

    /// 武器 3 本＋消費＋指輪を持つ味方。本物の ItemMenu は 1 カテゴリ表示なので武器カテゴリが出る
    /// （◀ 武器 ▶ の切替ヒント・重量ヘッダは実ロジック）。
    def itemSelectConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = mkPlayer({weaponIds = "iron_sword" :: "steel_lance" :: "silver_sword" :: Nil,
                             consumableIds = "vulnerary" :: Nil, ringIds = "power_ring" :: Nil
                             | basePlayer(0, "knight", {x = 1, y = 1})});
        let world = emptyWorld() |> addPlayer(lord);
        {phase = TurnPhase.Phase.ItemSelect, selectedId = Some(0), itemCategory = 0
         | SnapshotHarness.config(world)}

    def driveItemMenuSelect(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = itemSelectConfig();
        spawnUi(ItemMenuUi.specPath());
        SnapshotHarness.withMocks(cfg, () -> ItemMenuUi.frameStep(dt()))

    /// サブメニュー（武器を選んだ後）: そうび / なげる / すてる。
    def itemActionConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = mkPlayer({weaponIds = "iron_sword" :: Nil,
                             selectedItem = Some(PlayerData.ItemKind.Weapon(0))
                             | basePlayer(0, "knight", {x = 1, y = 1})});
        let world = emptyWorld() |> addPlayer(lord);
        {phase = TurnPhase.Phase.ItemActionSelect, selectedId = Some(0) | SnapshotHarness.config(world)}

    def driveItemMenuAction(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = itemActionConfig();
        spawnUi(ItemMenuUi.specPath());
        SnapshotHarness.withMocks(cfg, () -> ItemMenuUi.frameStep(dt()))

    /// 満載シーン: 武器 5 本を持たせ、表示範囲（3 行）をスクロールさせる。`sel` は選択 index。
    def itemFullConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = mkPlayer({hp = 22,
                             weaponIds = "silver_sword" :: "killing_edge" :: "iron_sword"
                                          :: "steel_axe" :: "iron_bow" :: Nil
                             | basePlayer(0, "knight", {x = 1, y = 1})});
        let world = emptyWorld() |> addPlayer(lord);
        {phase = TurnPhase.Phase.ItemSelect, selectedId = Some(0), itemCategory = 0
         | SnapshotHarness.config(world)}

    def driveItemMenuFull(sel: Int32): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = itemFullConfig();
        spawnUi(ItemMenuUi.specPath());
        // 選択 index を先に注入してから frameStep で表示 offset・ハイライトを実ロジックで決めさせる。
        putSel("ItemMenu/panel/menu", sel);
        SnapshotHarness.withMocks(cfg, () -> ItemMenuUi.frameStep(dt()))

    // ── TradeMenu ──

    /// 2 人交換。各ペインは在庫＋（満杯でないので）末尾に空きスロット行が出る。
    def trade2Config(): SnapshotHarness.Config \ Fs.FileRead =
        let p0 = mkPlayer({weaponIds = "iron_sword" :: Nil, consumableIds = "vulnerary" :: Nil
                           | basePlayer(0, "knight", {x = 1, y = 1})});
        let p1 = mkPlayer({weaponIds = "steel_lance" :: Nil, consumableIds = "great_vulnerary" :: Nil
                           | basePlayer(1, "paladin", {x = 2, y = 1})});
        let world = emptyWorld() |> addPlayer(p0) |> addPlayer(p1);
        let trade = {members = 0 :: 1 :: Nil, focus = 0 | TradeMenuUi.defaultPanelData()};
        {phase = TurnPhase.Phase.TradeInventory, trade = trade | SnapshotHarness.config(world)}

    def driveTradeMenu2(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = trade2Config();
        spawnUi(TradeMenuUi.specPath());
        SnapshotHarness.withMocks(cfg, () -> TradeMenuUi.frameStep(dt()))

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
        let world = emptyWorld() |> addPlayer(p0) |> addPlayer(p1) |> addPlayer(p2) |> addPlayer(p3);
        let trade = {members = 0 :: 1 :: 2 :: 3 :: Nil, focus = 0 | TradeMenuUi.defaultPanelData()};
        {phase = TurnPhase.Phase.TradeInventory, trade = trade | SnapshotHarness.config(world)}

    def driveTradeMenu4(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = trade4Config();
        spawnUi(TradeMenuUi.specPath());
        SnapshotHarness.withMocks(cfg, () -> TradeMenuUi.frameStep(dt()))

    // ── GameOverMenu / SuspendConfirm（モーダル：可視トグル + ハイライトだけ実ロジック）──

    def driveGameOverMenu(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = {simPhase = SimPhase.GameOver | SnapshotHarness.config(emptyWorld())};
        spawnUi(GameOverMenuUi.specPath());
        SnapshotHarness.withMocks(cfg, () -> GameOverMenuUi.frameStep(dt()))

    def driveSuspendConfirm(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = {phase = TurnPhase.Phase.SuspendConfirm | SnapshotHarness.config(emptyWorld())};
        spawnUi(SuspendConfirmUi.specPath());
        SnapshotHarness.withMocks(cfg, () -> SuspendConfirmUi.frameStep(dt()))

    // ── TitleMenu / Log（frameStep / step の実ロジックをフィクスチャ状態で駆動）──

    /// タイトル画面: 再開可能（resumable=true）で 2 択が有効・カーソル先頭に塗り箱ハイライト。
    /// TitleMenuUi.frameStep は root が可視のときだけハイライトを置くので、先に可視化してから回す。
    def driveTitleMenu(): Unit \ (Fs.FileRead + UiWorldState.State) = region rc {
        spawnUi(TitleMenuUi.specPath());
        UiWorldState.State.put(UiStore.setVisible(TitleMenuUi.rootPath(), true, UiWorldState.State.get()));
        TitleMenuState.withState(rc, () -> {
            TitleMenuState.State.put({cursor = 0, resumable = true});
            TitleMenuUi.frameStep(dt())
        })
    }

    /// 出撃メンバー選択: 実カタログの players プール（8 人）で候補を組み、3 人選択済み・注目カードを
    /// 4 番目（index 3）にした状態を実 frameStep で描く。カルーセルは注目カードを中央へ寄せ、選択済み
    /// カードは金枠、注目カードは白枠で拡大する。3 人揃っているので「出撃」ボタンは有効（オレンジ）。
    def driveCharacterSelect(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) = region rc {
        spawnUi(CharacterSelectUi.specPath());
        let catalog = UnitCatalog.load(AssetPath.resolve("resources/units.json"), WeaponCatalog.load());
        let players = UnitCatalog.pool("players", catalog);
        UiWorldState.State.put(UiStore.setVisible(CharacterSelectUi.rootPath(), true, UiWorldState.State.get()));
        CharacterSelectState.withState(rc, () -> {
            let data = {focus = 3, selected = 0 :: 1 :: 2 :: Nil,
                        carouselX = CharacterSelectUi.targetCarouselX(3)
                        | CharacterSelectUi.initialState(players)};
            CharacterSelectState.State.put(data);
            CharacterSelectUi.frameStep(dt())
        })
    }

    /// ログ HUD: 3 件のログをキューに積んだ状態で LogUi.step を回し、3 行が右下に並ぶ様子を撮る
    /// （GameLogger は空 drain のモック。新着なしなので既存 3 件がそのまま表示される）。
    def driveLogLines(): Unit \ (Fs.FileRead + UiWorldState.State) = region rc {
        spawnUi(LogUi.specPath());
        let seeded = {queue = logEntry("T1: 剣士 の こうげき", GameLogger.playerColor())
                              :: logEntry("T1: ゴブリン に 6 のダメージ", GameLogger.playerColor())
                              :: logEntry("T1: ゴブリン の はんげき", GameLogger.enemyColor()) :: Nil,
                      idleSince = Duration.zero()};
        LogState.withState(rc, () -> {
            LogState.State.put(seeded);
            TestUnitFixtures.withMockGameLogger(() -> LogUi.step(dt()))
        })
    }

    /// 表示用ログエントリの簡易ビルダ。color は engine の Color（構造的に {r,g,b} Float32）。
    def logEntry(text: String, color: {r = Float32, g = Float32, b = Float32}): LogState.LogEntry =
        {text = text, color = color}

    /// ターンスキップ長押しゲージ 50%: ログ帯を背景に出し、実ロジック（TurnEndHoldUi.applyRing）で
    /// 充填リング 50% を UiWorld へ塗る。ログ帯 + 充填リング + 「ターンスキップ」文字が重なる様子を撮る。
    def driveTurnEndHold(): Unit \ (Fs.FileRead + UiWorldState.State) =
        spawnUi(LogUi.specPath());
        spawnUi(TurnEndHoldUi.specPath());
        UiWorldState.State.put(UiStore.setVisible(LogUi.rootPath(), true, UiWorldState.State.get()));
        UiWorldState.State.put(TurnEndHoldUi.applyRing(0.5, true, UiWorldState.State.get()))

    /// 中央アイテム取得ポップアップ（表示中）: 実ロジック（ItemPickupPopupUi.applyAppearance）で
    /// ratio=1.0・文言つきの見た目を UiWorld へ塗る。ポップアップ + 中央の「○○を手に入れた」を撮る。
    def driveItemPickupPopup(): Unit \ (Fs.FileRead + UiWorldState.State) =
        spawnUi(ItemPickupPopupUi.specPath());
        UiWorldState.State.put(
            ItemPickupPopupUi.applyAppearance(1.0, "銀の剣を手に入れた", UiWorldState.State.get()))

    /// 戦闘予報ミニウィンドウ（表示中）: PlayerAttack フェーズで攻撃対象を抱えた味方 × 隣接の敵を組み、
    /// 本物の BattlePanelUi.frameStep に命中/必殺/反撃の予報数値・相性三角を組ませて撮る
    /// （カメラ無しなので panel は ui.json の既定位置に出る）。
    def driveBattlePanel(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) = region rc {
        let lord = {attackTargetId = Some(9)
                    | mkPlayer({weaponIds = "iron_sword" :: Nil | basePlayer(0, "knight", {x = 1, y = 1})})};
        let enemy = mkEnemy(9, "fighter_t1", {x = 1, y = 2}, 12, Some("iron_sword"));
        let world = emptyWorld() |> addPlayer(lord) |> addEnemy(enemy);
        let cfg = {phase = TurnPhase.Phase.PlayerAttack, selectedId = Some(0), cursor = {x = 1, y = 2}
                   | SnapshotHarness.config(world)};
        spawnUi(BattlePanelUi.specPath());
        BattlePanelState.withState(rc, () ->
          UnitHPBarRender.withForecast(rc, () ->
            CameraState.withState(rc, () ->
              SnapshotHarness.withFullMocks(cfg, () -> {
                // 本番の PlayerAttack ではカメラがカーソル（攻撃対象マス）へ寄る。panel は
                // 対象の画面近傍へ出るので、カメラをカーソルマスへスナップして本番同様の配置を撮る。
                CameraState.snapTo(MapSnapshot.cellCenter({x = 1, y = 2}));
                BattlePanelUi.frameStep(dt())
              }))))
    }

    /// レベルアップのステータス変化パネル（増分表示の途中）: 味方に保留レベルアップ結果を持たせ、
    /// 演出ステートを「途中まで出した」状態（started・revealed=6・待ち時間残り）に直接注入してから
    /// 本物の LevelUpPanelUi.frameStep を 1 回回す（timer が残るので revealed は動かず、その revealed
    /// ぶんの本文が描かれる）。左列は全行・右列は途中まで出た様子を撮る。
    def driveLevelUpPanel(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) = region rc {
        spawnUi(LevelUpPanelUi.specPath());
        let lord = {pendingLevelUp = Some(levelUpFixtureResult())
                    | mkPlayer(basePlayer(0, "knight", {x = 1, y = 1}))};
        // pendingLevelUp は World 権威＝保留結果ごと World store へ seed して渡す。
        let world = emptyWorld() |> addPlayer(lord);
        LevelUpPanelState.withState(rc, () -> {
            LevelUpPanelState.State.put({started = true, revealed = 6, timer = Duration.millis(500)});
            TestUnitFixtures.withWorldQuery(world, () ->
              TestUnitFixtures.withFixedPhase(TurnPhase.Phase.LevelUpView, () ->
                TestUnitFixtures.withMockAudio(() ->
                  LevelUpPanelUi.frameStep(dt()))))
        })
    }

    /// スナップショット / GIF 共通のレベルアップ結果フィクスチャ（9 ステータス）。
    /// レイアウト最悪ケースを固定して被り再発を検知する: 「こううん」等の**4 文字ラベルが上昇**し、
    /// かつ**2 桁の現在値・新値**（例 こううん 15 -> 16）を含む。4 文字ラベル + 2 桁 + 矢印 + +1 が
    /// 1 行に並んでも数値・矢印列に被らないことを golden で凍結する。
    pub def levelUpFixtureResult(): LevelSystem.Result =
        {unitName = "ロード", fromLevel = 4, toLevel = 5, changes =
            ({label = "HP",   before = 20, after = 21, gained = true}:  LevelSystem.StatChange) ::
            ({label = "ちから", before = 6,  after = 7,  gained = true}:  LevelSystem.StatChange) ::
            ({label = "まりょく", before = 12, after = 13, gained = true}: LevelSystem.StatChange) ::
            ({label = "わざ",   before = 8,  after = 9,  gained = true}:  LevelSystem.StatChange) ::
            ({label = "すばやさ", before = 17, after = 18, gained = true}: LevelSystem.StatChange) ::
            ({label = "こううん", before = 15, after = 16, gained = true}:  LevelSystem.StatChange) ::
            ({label = "しゅび", before = 6,  after = 6,  gained = false}: LevelSystem.StatChange) ::
            ({label = "まぼう", before = 1,  after = 1,  gained = false}: LevelSystem.StatChange) ::
            ({label = "たいかく", before = 8, after = 8, gained = false}: LevelSystem.StatChange) :: Nil}

    // ── UnitCard / EnemyCard（frameStep が対象を解決して両カードを描く）──

    /// 選択中味方のカードを解決させる config（ActionSelect＝カーソル依存でない経路）。
    def unitCardConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = mkPlayer({weaponIds = "iron_sword" :: Nil, ringIds = "power_ring" :: Nil,
                             ringEquipped = true | basePlayer(0, "knight", {x = 1, y = 1})});
        let world = emptyWorld() |> addPlayer(lord);
        {phase = TurnPhase.Phase.ActionSelect, selectedId = Some(0) | SnapshotHarness.config(world)}

    /// 両カード root を spawn する（frameStep は対象なし側を隠す）。
    def spawnCards(): Unit \ (Fs.FileRead + UiWorldState.State) =
        spawnUi(UnitCardUi.specPath());
        spawnAs(UnitCardUi.specPath(), UnitCardUi.enemyRootName())

    def driveUnitCard(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) =
        let cfg = unitCardConfig();
        spawnCards();
        SnapshotHarness.withMocks(cfg, () -> UnitCardUi.frameStep(dt()))

    /// WeaponSelect のカーソル上の敵カードを解決させる config（味方カードは未選択で隠れる）。
    /// 敵可視はフォグ導出なので、盤面 seed（boardWorld）＋同室のプレイヤーで部屋を点灯させる
    /// （プレイヤーは未選択のため左カードは出ない＝golden 不変）。
    def enemyCardConfig(): SnapshotHarness.Config \ Fs.FileRead =
        let lord = mkPlayer(basePlayer(0, "knight", {x = 1, y = 1}));
        let enemy = mkEnemy(9, "fighter_t1", {x = 3, y = 3}, 12, Some("iron_sword"));
        let world = emptyWorld() |> addPlayer(lord) |> addEnemy(enemy) |> boardWorld;
        {phase = TurnPhase.Phase.WeaponSelect, selectedId = None, cursor = {x = 3, y = 3}
         | SnapshotHarness.config(world)}

    def driveEnemyCard(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) =
        let cfg = enemyCardConfig();
        spawnCards();
        SnapshotHarness.withMocks(cfg, () -> UnitCardUi.frameStep(dt()))

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
        SnapshotHarness.withMocks(cfg, () -> UnitCardUi.frameStep(dt()))

    /// TopBar + アクションメニュー（フル）。
    def driveHudActionMenu(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) =
        let cfg = actionFullConfig();
        applyTopBar(allyFrame(), false);
        spawnUi(ActionMenuUi.specPath());
        SnapshotHarness.withMocks(cfg, () -> ActionMenuUi.frameStep(dt()))

    /// 攻撃フロー最盛：WeaponSelect フェーズで TopBar + アクション + 武器選択 + 自軍/敵カードが同居。
    /// ActionMenu は WeaponSelect フェーズでも可視（随伴ウィンドウ）なので同じ config で全部が生きる。
    def driveHudAttackFlow(): Unit \ (Fs.FileRead + GameEngine.Game + UiWorldState.State) =
        let lord = mkPlayer({weaponIds = "iron_sword" :: "steel_lance" :: Nil,
                             ringIds = "power_ring" :: Nil, ringEquipped = true
                             | basePlayer(0, "knight", {x = 1, y = 1})});
        let ally = mkPlayer(basePlayer(1, "paladin", {x = 2, y = 1}));
        let enemy = mkEnemy(9, "fighter_t1", {x = 1, y = 2}, 12, Some("iron_sword"));
        // 敵カード（右）はフォグ導出の敵可視を要するため盤面を seed する（boardWorld）。
        let world = emptyWorld() |> addPlayer(lord) |> addPlayer(ally) |> addEnemy(enemy) |> boardWorld;
        let cfg = {phase = TurnPhase.Phase.WeaponSelect, selectedId = Some(0), cursor = {x = 1, y = 2}
                   | SnapshotHarness.config(world)};
        applyTopBar(allyFrame(), false);
        spawnUi(ActionMenuUi.specPath());
        spawnUi(WeaponSelectUi.specPath());
        spawnCards();
        SnapshotHarness.withMocks(cfg, () -> {
            ActionMenuUi.frameStep(dt());
            WeaponSelectUi.frameStep(dt());
            UnitCardUi.frameStep(dt())
        })

    /// TopBar + 持ち物メニュー。
    def driveHudItemMenu(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = itemSelectConfig();
        applyTopBar(allyFrame(), false);
        spawnUi(ItemMenuUi.specPath());
        SnapshotHarness.withMocks(cfg, () -> ItemMenuUi.frameStep(dt()))

    /// TopBar(敵軍) + ゲームオーバーモーダル。
    def driveHudGameOver(): Unit \ (Fs.FileRead + UiWorldState.State) =
        let cfg = {simPhase = SimPhase.GameOver | SnapshotHarness.config(emptyWorld())};
        applyTopBar(enemyFrame(), false);
        spawnUi(GameOverMenuUi.specPath());
        SnapshotHarness.withMocks(cfg, () -> GameOverMenuUi.frameStep(dt()))

    // ════════════════════════════════════════════════════════
    // minimap（宣言フィクスチャを純粋 `minimapDrawList` に流して直描き）
    // ════════════════════════════════════════════════════════
    //
    // ミニマップは World-entity UI ではなく `RenderWorld.renderMinimap` の直描き System。実効果つきの
    // データ解決（訪問記憶 / ユニット位置 / 階段 / アイテムの読み）は live ゲーム & TestMinimapDriver の
    // 純関数テストで担保し、ここでは「解決済みデータ → 幾何 → Drawable/Polygon」の中核 `minimapDrawList`
    // だけを宣言フィクスチャで凍結する（World / effect ハーネス不要 = 最小拡張）。
    //
    // フィクスチャ地形（左下原点・y 下向き。数字=idx。#=壁 .=床）:
    //   部屋0 (0,0)-(6,5)   通路2 (6,1)-(12,3)   部屋1 (12,0)-(17,5)
    //
    //       0123456789012345678
    //     0 .0000.      .11111.
    //     1 .0000.222222.11111.
    //     2 .0000.222222.11111.
    //     3 .0000.      .11111.
    //     4 .0000.      .11111.

    def minimapNames(): List[String] = "minimap_normal" :: "minimap_explored" :: Nil
    def isMinimapEntry(name: String): Bool = List.memberOf(name, minimapNames())

    /// 部屋2 + 通路1 の module 配置（部屋 idx<2・通路 idx=2）。
    def minimapPlacements(): List[DungeonComposer.ModulePlacement] =
        RoomLayout.placement(0, 0,  0, 6, 5) ::
        RoomLayout.placement(1, 12, 0, 5, 5) ::
        RoomLayout.placement(2, 6,  1, 6, 2) :: Nil
    def minimapRoomCount(): Int32 = 2

    /// module 床以外を壁にした地形スナップショット。moduleRect の青塗り bbox から、床セル
    /// （module の floorBounds 内）だけを黒く抜くため、床でないセルはすべて壁として登録する。
    def minimapSnapshot(): MapSnapshot =
        let placements = minimapPlacements();
        let w = 18; let h = 6;
        let cells = List.range(0, w)
            |> List.flatMap(x -> List.map(y -> (x, y), List.range(0, h)));
        let walls = cells
            |> List.filter(c -> let (x, y) = c;
                    Option.isEmpty(MapSnapshot.moduleOfCellIn(({x = x, y = y}: {x = Int32, y = Int32}), placements)))
            |> List.toSet;
        {tileSize   = MapSnapshot.tileSize(),
         usedRect   = {position = {x = 0, y = 0}, size = {x = w, y = h}},
         wallCells  = walls,
         mapGlobal  = {x = 0.0, y = 0.0},
         placements = placements}

    /// 訪問済み module。normal=部屋0+通路2（部屋1 は未訪問→未表示・隣接通路はヒント）、
    /// explored=全 module。
    def minimapVisited(name: String): Set[Int32] =
        if (name == "minimap_explored") Set#{0, 1, 2} else Set#{0, 2}

    /// 宣言マーカー（セル + 色）。色は `MinimapDriver` の意味色（リーダー黄 / 味方青 / アイテム橙 /
    /// 敵赤 / 階段紫）に対応させた固定値。全探索では部屋1 に階段マーカーを足す。
    def minimapMarkers(name: String): List[{cell = {x = Int32, y = Int32}, color = Color}] =
        let leaderCol = ({r = 0.95f32, g = 0.85f32, b = 0.20f32}: Color);
        let playerCol = ({r = 0.30f32, g = 0.70f32, b = 0.95f32}: Color);
        let itemCol   = ({r = 0.95f32, g = 0.60f32, b = 0.20f32}: Color);
        let enemyCol  = ({r = 0.92f32, g = 0.25f32, b = 0.22f32}: Color);
        let stairsCol = ({r = 0.90f32, g = 0.30f32, b = 0.85f32}: Color);
        let base =
            {cell = {x = 2, y = 2}, color = leaderCol} ::   // リーダー（部屋0）
            {cell = {x = 3, y = 3}, color = playerCol} ::   // 味方（部屋0）
            {cell = {x = 1, y = 1}, color = itemCol}   ::   // アイテム（部屋0）
            {cell = {x = 8, y = 1}, color = enemyCol}  :: Nil;  // 敵（通路2）
        if (name == "minimap_explored")
            List.append(base, {cell = {x = 14, y = 2}, color = stairsCol} :: Nil)  // 階段（部屋1）
        else base

    /// 宣言フィクスチャ → 純粋な描画リスト（矩形 Drawable + マーカー Polygon）。
    def minimapRendered(name: String):
            {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]} =
        MinimapDriver.minimapDrawList(({visited = minimapVisited(name), placements = minimapPlacements(),
            roomCount = minimapRoomCount(), snapshot = minimapSnapshot(),
            markers = minimapMarkers(name)}: MinimapDriver.RenderInput))
}
