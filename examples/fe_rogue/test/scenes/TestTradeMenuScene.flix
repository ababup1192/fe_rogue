// TradeMenu のキー操作シナリオを「ユーザー操作 → 交換後のお互いのインベントリ」で検証する。
//
// 設計方針:
//   - 本体 (`TradeMenuScene.weaponEntry` / `staffEntry` / `emptySlotEntry`) が毎フレーム
//     ItemList に並べているのと同じ `ItemEntry` をテストでも使う (= テスト固有の entry
//     コンストラクタを置かない)
//   - フィクスチャは本体経路: `UnitCatalog.load` / `Staff.load` で本番 catalog をロードし、
//     `MapScene.addWorldNode` + `PlayerScene.addOnePlayer` で scene を組む
//   - DSL はアクション (`pressZOnSelf` 等) のみ。assertion はテスト末尾の 1 回だけ
//   - **検証は「交換後のお互いのインベントリ」または「cancel 後の phase」のみ**。
//     pick / focus などの中間状態は検証しない (操作の最終結果だけで仕様を担保する)
//
// 純粋な swap ロジックは TestPlayerScene の swapItem テストで網羅済。
// ここでは「ユーザーの一連のキー操作で最終的に正しいインベントリ / phase になるか」を検証する。

mod TestTradeMenuScene {

    use TradeMenuScene.Pane

    // ────────────────────────────────────────────────────────
    // (A) シナリオ状態 (DSL のチェーンで持ち回す唯一のグルー型)
    // ────────────────────────────────────────────────────────

    /// 1 シナリオの状態。`scene` の中に TradePanel + 2 Player + 2 ItemList が居る。
    pub type alias TradeScenario = {
        scene     = Scene[NodeTag],
        selfId    = Int32,
        partnerId = Int32
    }

    // ────────────────────────────────────────────────────────
    // (B) フィクスチャ: 初期 scene 構築
    // ────────────────────────────────────────────────────────

    /// 「自分 (selfId) と相手 (partnerId) のインベントリ」を初期状態として
    /// TradeMenu フィクスチャを組む。
    /// インベントリは **本番 catalog の ID** ("trainingSpear", "trainingBow", "live_staff" 等)
    /// のリストで指定する。catalog は本番 `resources/*.json` を `UnitCatalog.load` / `Staff.load`
    /// で読む。scene は `MapScene.addWorldNode` + `PlayerScene.addOnePlayer` の本体経路で組む。
    pub def freshTrade(args: {selfId = Int32, partnerId = Int32,
                                selfWeapons = List[String], selfStaves = List[String],
                                partnerWeapons = List[String], partnerStaves = List[String]}):
            TradeScenario \ Fs.FileRead =
        let weaponCatalog = WeaponCatalog.load();
        let catalog = UnitCatalog.load("resources/units.json", weaponCatalog);
        let staffCatalog = Staff.load();
        let unitSample = match List.head(UnitCatalog.pool("players", catalog)) {
            case Some(r) => r
            case None    => bug!("no players in catalog")
        };
        let mkSpawn = (id, weaponIds, staffIds) ->
            ({id = id, gridPos = {x = 0, y = 0}, resource = unitSample,
              weapons = List.map(wId -> UnitCatalog.lookupWeapon(wId, catalog), weaponIds),
              staves  = List.map(sId -> Staff.lookup(sId, staffCatalog), staffIds),
              consumables = Nil}:
                PlayerScene.Spawn);
        let withParty = Scene.empty()
            |> MapScene.addWorldNode
            |> PlayerScene.addOnePlayer(mkSpawn(args#selfId,    args#selfWeapons,    args#selfStaves))
            |> PlayerScene.addOnePlayer(mkSpawn(args#partnerId, args#partnerWeapons, args#partnerStaves));
        let withMenu  = loadTradeMenu(withParty);
        let withPartnerId = TradeMenuScene.mapPanelData(d ->
            {partnerId = args#partnerId | d}, withMenu);
        {scene = withPartnerId, selfId = args#selfId, partnerId = args#partnerId}

    /// 武器だけ持つ最小シナリオ用の簡易版。多くのテストは「selfWeapons / partnerWeapons」
    /// 以外は固定 (selfId=0, partnerId=1, staves=Nil) なので、各テスト先頭の record 引数を
    /// 1 行に縮めるためのコンストラクタ。杖を使うときは `freshTrade` を直接使う。
    /// 引数の string は **catalog 武器 ID** ("trainingSpear", "trainingBow" 等)。
    pub def freshTradeWithWeapons(selfWeapons: List[String],
                                    partnerWeapons: List[String]):
            TradeScenario \ Fs.FileRead =
        freshTrade({selfId = 0, partnerId = 1,
                    selfWeapons = selfWeapons, selfStaves = Nil,
                    partnerWeapons = partnerWeapons, partnerStaves = Nil})

    /// `TradeMenuScene.add` の `{GameEngine.Game, Fs.FileRead}` 効果を discharge。
    /// `TestItemMenuScene.loadItemMenu` と同じ手順 (GameEngine をモック、Fs はそのまま)。
    def loadTradeMenu(scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
        run {
            TestUnitFixtures.withMockGame(() -> TradeMenuScene.add(scene))
        } with handler GameEngine.Game {
            def renderCommands(_, _, _, k)     = k(())
            def initTileBuffer(_, k)        = k((0i32, 0i32))
            def shouldClose(k)              = k(false)
            def getDeltaTime(k)             = k(Duration.seconds(0.016))
            def isKeyPressed(_, k)          = k(false)
            def getMousePosition(k)         = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k)  = k(false)
            def consumeScrollDelta(k)       = k(0.0)
            def getFontAtlas(_, k)          = k(TestUnitFixtures.testFontAtlas())
            def getViewportRect(k)          = k({position = Vec2.zero(), size = {x = 128.0, y = 128.0}})
            def getTextureInfo(_, k)        = k(None)
            def setCursor(_, k)             = k(())
        }

    // ────────────────────────────────────────────────────────
    // (C) DSL アクション: キー押下 (scenario -> scenario)
    // 本体 `TradeMenuScene.weaponEntry / staffEntry / emptySlotEntry` で
    // 「本体が ItemList に並べているのと同じ ItemEntry」を組み立てて渡す。
    // ────────────────────────────────────────────────────────

    /// じぶん側で「`itemName` のスロット」に Z を押す (実体アイテムのみ)。
    /// 空スロットを押したい場合は `pressZOnSelfEmpty` を使う。
    pub def pressZOnSelf(itemName: String, s: TradeScenario):
            TradeScenario \ {GameLogger.GameLogger, SelectedPlayer.State} =
        let entry = entryForInventoryItem(itemName, s#selfId, s#scene);
        {scene = TradeMenuScene.onConfirmSelf(entry, s#scene) | s}

    /// じぶん側の「空スロット (--------)」に Z を押す。
    pub def pressZOnSelfEmpty(s: TradeScenario):
            TradeScenario \ {GameLogger.GameLogger, SelectedPlayer.State} =
        {scene = TradeMenuScene.onConfirmSelf(TradeMenuScene.emptySlotEntry(), s#scene) | s}

    /// あいて側で「`itemName` のスロット」に Z を押す (実体アイテムのみ)。
    pub def pressZOnPartner(itemName: String, s: TradeScenario):
            TradeScenario \ {GameLogger.GameLogger, SelectedPlayer.State} =
        let entry = entryForInventoryItem(itemName, s#partnerId, s#scene);
        {scene = TradeMenuScene.onConfirmPartner(entry, s#scene) | s}

    /// あいて側の「空スロット (--------)」に Z を押す。
    pub def pressZOnPartnerEmpty(s: TradeScenario):
            TradeScenario \ {GameLogger.GameLogger, SelectedPlayer.State} =
        {scene = TradeMenuScene.onConfirmPartner(TradeMenuScene.emptySlotEntry(), s#scene) | s}

    /// じぶん側にフォーカスがある状態で X を押す (キャンセル)。
    pub def pressXOnSelf(s: TradeScenario): TradeScenario \ TurnPhase.State =
        {scene = TradeMenuScene.onCancelSelf(s#scene) | s}

    /// あいて側にフォーカスがある状態で X を押す (キャンセル)。
    pub def pressXOnPartner(s: TradeScenario): TradeScenario \ TurnPhase.State =
        {scene = TradeMenuScene.onCancelPartner(s#scene) | s}

    /// ← (左矢印) を押す = じぶん側にフォーカス移動。
    pub def pressLeftArrow(s: TradeScenario): TradeScenario =
        {scene = TradeMenuScene.setPaneFocus(Pane.Self, s#scene) | s}

    /// → (右矢印) を押す = あいて側にフォーカス移動。
    pub def pressRightArrow(s: TradeScenario): TradeScenario =
        {scene = TradeMenuScene.setPaneFocus(Pane.Partner, s#scene) | s}

    // ────────────────────────────────────────────────────────
    // (D) 内部ヘルパー (名前 → 本体 entry 解決)
    // ────────────────────────────────────────────────────────

    /// `itemName` を該当プレイヤーのインベントリから探し、本体の `weaponEntry` /
    /// `staffEntry` を使って ItemEntry を組む。見つからなければテストを潰す (= 入力ミス検知)。
    def entryForInventoryItem(itemName: String, playerId: Int32,
                                scene: Scene[NodeTag]): ItemEntry =
        let weapons = PlayerScene.getWeapons(playerId, scene);
        match findIndexed(w -> w#name == itemName, weapons) {
            case Some((idx, weapon)) => TradeMenuScene.weaponEntry(idx, weapon)
            case None                =>
                let staves = PlayerScene.getStaves(playerId, scene);
                match findIndexed(s -> s#name == itemName, staves) {
                    case Some((idx, staff)) => TradeMenuScene.staffEntry(idx, staff)
                    case None               =>
                        bug!("Item '${itemName}' not found in player ${playerId}")
                }
        }

    /// 述語が真になる最初の要素を `(index, value)` のタプルで返す。
    /// `Option.getWithDefault(bug!(...))` の eager 評価を踏まないよう、index と value を
    /// 同時に取り出すために使う。
    def findIndexed(pred: a -> Bool, list: List[a]): Option[(Int32, a)] =
        List.mapWithIndex(i -> x -> (i, x), list)
            |> List.find(p -> pred(snd(p)))

    // ────────────────────────────────────────────────────────
    // (E) effect handlers ヘルパー
    // ────────────────────────────────────────────────────────

    /// シナリオで使う effect (GameLogger / SelectedPlayer.State / TurnPhase.State)
    /// をまとめて discharge して body を実行する。
    def runScenario(rc: Region[r], initialPhase: TurnPhase.Phase, selfId: Int32,
                     thunk: Unit -> a \ ef):
            (a, TurnPhase.Phase) \
            (ef - GameLogger.GameLogger - SelectedPlayer.State - TurnPhase.State + r) =
        let phaseRef: Ref[TurnPhase.Phase, r] = Ref.fresh(rc, initialPhase);
        let result =
            TestUnitFixtures.withMockGameLogger(() ->
                run {
                    thunk()
                } with handler SelectedPlayer.State {
                    def get(k)    = k({id = Some(selfId), origin = Some({x = 0i32, y = 0i32})})
                    def put(_, k) = k()
                } with handler TurnPhase.State {
                    def get(k)         = k(Ref.get(phaseRef))
                    def put(target, k) = {
                        Ref.put(target, phaseRef);
                        k()
                    }
                });
        (result, Ref.get(phaseRef))

    // ════════════════════════════════════════════════════════
    // テスト本体 — 1 テスト = 1 シナリオ = 末尾の 1 assertEq
    // インベントリ比較は `TestUnitFixtures.inventoryNamesOf` を直接使う。
    // ════════════════════════════════════════════════════════

    /// 「じぶんで槍 Z → あいてで弓 Z」→ 互いのインベントリが入れ替わる。
    @Test
    def testFullSwapFlowExchangesInventories(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshTradeWithWeapons("trainingSpear" :: Nil, "trainingBow" :: Nil);
            let (after, _) = runScenario(rc, TurnPhase.Phase.TradeInventory, 0, () -> {
                s0 |> pressZOnSelf("てつのやり") |> pressZOnPartner("てつの弓")
            });
            Assert.assertEq(
                expected = ("てつの弓" :: Nil, "てつのやり" :: Nil),
                (PlayerScene.getWeapons(after#selfId,    after#scene) |> List.map(w -> w#name),
                 PlayerScene.getWeapons(after#partnerId, after#scene) |> List.map(w -> w#name)))
        }

    /// 「→ で Partner に移動 → 弓 Z → 自分で槍 Z」(Partner 起動経路) →
    /// 互いのインベントリが入れ替わる (Self 起動と同じ結果)。
    @Test
    def testPartnerStartSwapExchangesInventories(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshTradeWithWeapons("trainingSpear" :: Nil, "trainingBow" :: Nil);
            let (after, _) = runScenario(rc, TurnPhase.Phase.TradeInventory, 0, () -> {
                s0 |> pressRightArrow
                   |> pressZOnPartner("てつの弓")
                   |> pressZOnSelf("てつのやり")
            });
            Assert.assertEq(
                expected = ("てつの弓" :: Nil, "てつのやり" :: Nil),
                (PlayerScene.getWeapons(after#selfId,    after#scene) |> List.map(w -> w#name),
                 PlayerScene.getWeapons(after#partnerId, after#scene) |> List.map(w -> w#name)))
        }

    /// 「じぶんで空スロット Z → あいてで弓 Z」→ 弓を受取、あいて側は空に。
    @Test
    def testReceivePartnerItemViaSelfEmptyPick(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshTradeWithWeapons(Nil, "trainingBow" :: Nil);
            let (after, _) = runScenario(rc, TurnPhase.Phase.TradeInventory, 0, () -> {
                s0 |> pressZOnSelfEmpty |> pressZOnPartner("てつの弓")
            });
            Assert.assertEq(
                expected = ("てつの弓" :: Nil, Nil),
                (PlayerScene.getWeapons(after#selfId,    after#scene) |> List.map(w -> w#name),
                 PlayerScene.getWeapons(after#partnerId, after#scene) |> List.map(w -> w#name)))
        }

    /// 「pick 未選択で X」→ TradeInventory を抜けて ActionSelect フェーズに戻る。
    /// (本質は「メニューが閉じてゲームの行動選択に戻る」ことの確認)
    @Test
    def testCancelWithNoPickExitsToActionSelect(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshTradeWithWeapons("trainingSpear" :: Nil, "trainingBow" :: Nil);
            let (_, finalPhase) = runScenario(rc, TurnPhase.Phase.TradeInventory, 0, () -> {
                s0 |> pressXOnSelf
            });
            Assert.assertEq(expected = TurnPhase.Phase.ActionSelect, finalPhase)
        }
}
