// TradeMenu のキー操作シナリオを「ユーザー操作 → 交換後の各メンバーのインベントリ」で検証する。
//
// 物交換は通常ターンの隣接 2 人交換と集合後の N 人 (最大 3 人) 交換を同じ World で扱う。
// ここでは index ベースのペイン操作 DSL で「一連のキー操作 → 最終インベントリ / phase」を検証する。
//
// 設計方針:
//   - 本体 (`TradeMenuUi.weaponEntry` / `staffEntry` / `emptySlotEntry`) が並べているのと
//     同じ `ItemEntry` を `confirmAt` に渡す (テスト固有の entry コンストラクタを置かない)
//   - フィクスチャは本体経路: `UnitCatalog.load` / `Staff.load` + `PlayerDriver.addOnePlayer`
//   - DSL はアクション (`pressZOnPane` 等) のみ。assertion はテスト末尾の 1 回だけ
//   - **検証は「交換後の各メンバーのインベントリ」または「cancel 後の phase」のみ**
//
// 純粋な swap ロジックは TestPlayerDriver の swapItem テストで網羅済。
// 純粋な状態遷移 (decideConfirm / moveFocus) はこのファイル末尾で別途単体テストする。

mod TestTradeMenuUi {

    // ────────────────────────────────────────────────────────
    // (A) シナリオ状態 + プレイヤー仕様
    // ────────────────────────────────────────────────────────

    /// 1 シナリオの状態。`world` の中に N Player が居る（World-entity UI 版はウィンドウノードを
    /// 持たないので、交換する味方の在庫だけ揃っていればよい）。
    /// `members` はペイン index → player id の対応 (PanelData と同じ並び)。
    /// `panel` はセッション開始時の PanelData。`runScenario` が `TradeMenuState.State` へ seed する。
    pub type alias TradeScenario = {
        world   = World,
        members = List[Int32],
        panel   = TradeMenuUi.PanelData
    }

    type alias PlayerSpec = {
        id      = Int32,
        weapons = List[String],
        staves  = List[String]
    }

    // ────────────────────────────────────────────────────────
    // (B) フィクスチャ: 初期 World 構築
    // ────────────────────────────────────────────────────────

    /// 各メンバーのインベントリ (本番 catalog の ID) と origin から TradeMenu フィクスチャを組む。
    /// players は specs の順に id を付け、PanelData の members も同じ並びにする。
    def buildScenario(rc: Region[r], specs: List[PlayerSpec], origin: TradeMenuUi.Origin):
            TradeScenario \ {Fs.FileRead} + r =
        let weaponCatalog = WeaponCatalog.load();
        let catalog = UnitCatalog.load("resources/units.json", weaponCatalog);
        let staffCatalog = Staff.load();
        let unitSample = match List.head(UnitCatalog.pool("players", catalog)) {
            case Some(pair) => snd(pair)
            case None       => bug!("no players in catalog")
        };
        let mkSpawn = spec ->
            ({id = spec#id, classId = "test_player", gridPos = {x = 0, y = 0}, resource = unitSample,
              weapons = List.map(wId -> UnitCatalog.lookupWeapon(wId, catalog), spec#weapons),
              staves  = List.map(sId -> Staff.lookup(sId, staffCatalog), spec#staves),
              consumables = Nil, rings = Nil}:
                PlayerDriver.Spawn);
        // addOnePlayer は World.Command を emit する。ここで一括適用して初期 World を組む
        // （World-entity UI 版はウィンドウノードを scene に積まない＝交換する味方だけ居ればよい）。
        let (_, world) = TestUnitFixtures.withWorldApplied(rc, () ->
            List.forEach(spec -> PlayerDriver.addOnePlayer(mkSpawn(spec)), specs));
        let members = List.map(s -> s#id, specs);
        // PanelData は resource へ直接書かず scenario に載せ、`runScenario` が seed する
        // （`TradeMenuState.State` handler の外で書けないため）。
        let panel = ({members = members, focus = 0, pick = None, origin = origin,
                      marks = Set#{}, markPane = None}: TradeMenuUi.PanelData);
        {world = world, members = members, panel = panel}

    /// 武器だけ持つ 2 人 (id 0,1) の隣接交換シナリオ (origin = FromTurn)。
    /// 引数の string は **catalog 武器 ID** ("iron_lance", "iron_bow" 等)。
    def freshTradeWithWeapons(rc: Region[r], selfWeapons: List[String], partnerWeapons: List[String]):
            TradeScenario \ {Fs.FileRead} + r =
        buildScenario(rc,
            ({id = 0, weapons = selfWeapons,    staves = Nil}: PlayerSpec) ::
            ({id = 1, weapons = partnerWeapons, staves = Nil}: PlayerSpec) :: Nil,
            TradeMenuUi.Origin.FromTurn)

    /// 武器だけ持つ 3 人 (id 0,1,2) の集合交換シナリオ (origin = FromGather)。
    def freshGatherTrade(rc: Region[r], w0: List[String], w1: List[String], w2: List[String]):
            TradeScenario \ {Fs.FileRead} + r =
        buildScenario(rc,
            ({id = 0, weapons = w0, staves = Nil}: PlayerSpec) ::
            ({id = 1, weapons = w1, staves = Nil}: PlayerSpec) ::
            ({id = 2, weapons = w2, staves = Nil}: PlayerSpec) :: Nil,
            TradeMenuUi.Origin.FromGather)

    // ────────────────────────────────────────────────────────
    // (C) DSL アクション: キー押下（World.Command / TradeMenuState を直接更新する）
    // ────────────────────────────────────────────────────────

    /// ペイン `paneIndex` の「`itemName` のスロット」に Z を押す (実体アイテムのみ)。
    pub def pressZOnPane(paneIndex: Int32, itemName: String, s: TradeScenario):
            Unit \ {GameLogger.GameLogger, SelectedPlayer.State, TradeMenuState.State,
                     World.Command, World.WorldQuery} =
        let pid = memberId(paneIndex, s);
        let entry = entryForInventoryItem(itemName, pid);
        TradeMenuUi.confirmAt(paneIndex, entry)

    /// ペイン `paneIndex` の「空スロット (空きスロット)」に Z を押す。
    pub def pressZOnPaneEmpty(paneIndex: Int32, _s: TradeScenario):
            Unit \ {GameLogger.GameLogger, SelectedPlayer.State, TradeMenuState.State,
                     World.Command, World.WorldQuery} =
        TradeMenuUi.confirmAt(paneIndex, TradeMenuUi.emptySlotEntry())

    /// X を押す (キャンセル / pick 解除)。
    pub def pressXAt(_s: TradeScenario):
            Unit \ {TurnPhase.State, TradeMenuState.State, RangeOverlayState.State} =
        TradeMenuUi.cancelCurrent()

    /// ← (左矢印) = focus を 1 つ左へ。
    pub def moveFocusLeft(_s: TradeScenario): Unit \ TradeMenuState.State =
        TradeMenuUi.setPaneFocusDelta(-1)

    /// → (右矢印) = focus を 1 つ右へ。
    pub def moveFocusRight(_s: TradeScenario): Unit \ TradeMenuState.State =
        TradeMenuUi.setPaneFocusDelta(1)

    /// ペイン `giverPane` の `itemName` に印を付ける (Shift 相当)。ItemList カーソルを介さず
    /// PanelData を直接更新するので、本体の `toggledMarks` のトグル規約をそのまま通す。
    pub def markOnPane(giverPane: Int32, itemName: String, s: TradeScenario):
            Unit \ {TradeMenuState.State, World.WorldQuery} =
        let pid = memberId(giverPane, s);
        let entry = entryForInventoryItem(itemName, pid);
        match entry#metadata |> Option.flatMap(ItemMenuUi.parseItemKind) {
            case Some(kind) =>
                TradeMenuUi.mapPanelData(d -> TradeMenuUi.toggledMarks(giverPane, kind, d))
            case None => bug!("cannot parse item kind for '${itemName}'")
        }

    /// ペイン `receiverPane` でまとめ渡しの Z を押す。印が別ペインに付いていれば bulk transfer。
    /// 受け取り側の entry は bulk 時は使われないので空スロット entry を渡す。
    pub def pressZBulkOnPane(receiverPane: Int32, _s: TradeScenario):
            Unit \ {GameLogger.GameLogger, SelectedPlayer.State, TradeMenuState.State,
                     World.Command, World.WorldQuery} =
        TradeMenuUi.confirmAt(receiverPane, TradeMenuUi.emptySlotEntry())

    // ────────────────────────────────────────────────────────
    // (D) 内部ヘルパー
    // ────────────────────────────────────────────────────────

    /// ペイン index → member の player id。
    def memberId(paneIndex: Int32, s: TradeScenario): Int32 =
        match List.nth(paneIndex, s#members) {
            case Some(id) => id
            case None     => bug!("pane index ${paneIndex} out of range")
        }

    /// `itemName` を該当プレイヤーのインベントリから探し、本体の `weaponEntry` / `staffEntry`
    /// を使って ItemEntry を組む。見つからなければテストを潰す (= 入力ミス検知)。
    def entryForInventoryItem(itemName: String, playerId: Int32): ItemEntry \ World.WorldQuery =
        let weapons = PlayerDriver.getWeapons(playerId);
        match findIndexed(w -> w#name == itemName, weapons) {
            case Some((idx, weapon)) => TradeMenuUi.weaponEntry(idx, weapon)
            case None                =>
                let staves = PlayerDriver.getStaves(playerId);
                match findIndexed(s -> s#name == itemName, staves) {
                    case Some((idx, staff)) => TradeMenuUi.staffEntry(idx, staff)
                    case None               =>
                        bug!("Item '${itemName}' not found in player ${playerId}")
                }
        }

    def findIndexed(pred: a -> Bool, list: List[a]): Option[(Int32, a)] =
        List.mapWithIndex(i -> x -> (i, x), list)
            |> List.find(p -> pred(snd(p)))

    /// 指定 player の武器名リスト (assertion 用・在庫は World 権威)。
    def weaponNames(playerId: Int32): List[String] \ World.WorldQuery =
        PlayerDriver.getWeapons(playerId) |> List.map(w -> w#name)

    // ────────────────────────────────────────────────────────
    // (E) effect handlers
    // ────────────────────────────────────────────────────────

    /// シナリオで使う effect (GameLogger / SelectedPlayer.State / TurnPhase.State)
    /// をまとめて discharge して body を実行し、結果と最終 phase を返す。
    def runScenario(rc: Region[r], initialPhase: TurnPhase.Phase, s0: TradeScenario,
                     thunk: Unit -> a \ ef):
            ((a, TurnPhase.Phase), World) \
            (ef - GameLogger.GameLogger - SelectedPlayer.State - TurnPhase.State - TradeMenuState.State
                - RangeOverlayState.State - World.Command - World.WorldQuery + r) =
        // 在庫は World 権威＝`buildScenario` が組んだ初期 World を seed し、
        // シナリオ全 step を同一 World（1 region）で回す。最終 World は assertion 用に返す。
        TestUnitFixtures.withWorldAppliedSeeded(rc, s0#world, () ->
        TestUnitFixtures.withTradeMenu(rc, () -> {
            TradeMenuState.State.put(s0#panel);   // セッション開始状態を seed
            // 「こうかん」キャンセルは範囲 resource を掃除するため RangeOverlayState を供給する。
            TestUnitFixtures.withPhaseRef(rc, initialPhase, () ->
                TestUnitFixtures.withMockGameLogger(() ->
                    TestUnitFixtures.withSelectedPlayer(0, () ->
                        TestUnitFixtures.withRangeOverlay(rc, thunk))))
        }))

    // ════════════════════════════════════════════════════════
    // 2 人交換 (回帰ガード) — index 化前と同じ最終結果を確認する
    // ════════════════════════════════════════════════════════

    /// 「ペイン0で槍 Z → ペイン1で弓 Z」→ 互いのインベントリが入れ替わる。
    @Test
    def testFullSwapFlowExchangesInventories(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshTradeWithWeapons(rc, "iron_lance" :: Nil, "iron_bow" :: Nil);
            let ((_, _), wFin) = runScenario(rc, TurnPhase.Phase.TradeInventory, s0, () -> {
                pressZOnPane(0, "てつのやり", s0);
                pressZOnPane(1, "てつの弓", s0)
            });
            Assert.assertEq(
                expected = ("てつの弓" :: Nil, "てつのやり" :: Nil),
                TestUnitFixtures.withWorldQuery(wFin, () ->
                    (weaponNames(0), weaponNames(1))))
        }

    /// 「→ でペイン1に移動 → 弓 Z → ペイン0で槍 Z」→ 互いのインベントリが入れ替わる。
    @Test
    def testPartnerStartSwapExchangesInventories(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshTradeWithWeapons(rc, "iron_lance" :: Nil, "iron_bow" :: Nil);
            let ((_, _), wFin) = runScenario(rc, TurnPhase.Phase.TradeInventory, s0, () -> {
                moveFocusRight(s0);
                pressZOnPane(1, "てつの弓", s0);
                pressZOnPane(0, "てつのやり", s0)
            });
            Assert.assertEq(
                expected = ("てつの弓" :: Nil, "てつのやり" :: Nil),
                TestUnitFixtures.withWorldQuery(wFin, () ->
                    (weaponNames(0), weaponNames(1))))
        }

    /// 「ペイン0で空スロット Z → ペイン1で弓 Z」→ 弓を受取、相手側は空に。
    @Test
    def testReceivePartnerItemViaEmptyPick(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshTradeWithWeapons(rc, Nil, "iron_bow" :: Nil);
            let ((_, _), wFin) = runScenario(rc, TurnPhase.Phase.TradeInventory, s0, () -> {
                pressZOnPaneEmpty(0, s0);
                pressZOnPane(1, "てつの弓", s0)
            });
            Assert.assertEq(
                expected = ("てつの弓" :: Nil, Nil),
                TestUnitFixtures.withWorldQuery(wFin, () ->
                    (weaponNames(0), weaponNames(1))))
        }

    /// 隣接 2 人交換 (FromTurn) で「pick 未選択で X」→ ActionSelect に戻る。
    @Test
    def testTurnCancelWithNoPickExitsToActionSelect(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshTradeWithWeapons(rc, "iron_lance" :: Nil, "iron_bow" :: Nil);
            let ((_, finalPhase), _wFin) = runScenario(rc, TurnPhase.Phase.TradeInventory, s0, () -> {
                pressXAt(s0)
            });
            Assert.assertEq(expected = TurnPhase.Phase.ActionSelect, finalPhase)
        }

    // ════════════════════════════════════════════════════════
    // 3 人交換 (集合)
    // ════════════════════════════════════════════════════════

    /// 「ペイン0で槍 Z → ペイン1で弓 Z」→ P0↔P1 入替、P2 は不変。
    @Test
    def testGatherSwapBetweenPane0And1(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshGatherTrade(rc, "iron_lance" :: Nil, "iron_bow" :: Nil, "iron_sword" :: Nil);
            let ((_, _), wFin) = runScenario(rc, TurnPhase.Phase.TradeInventory, s0, () -> {
                pressZOnPane(0, "てつのやり", s0);
                moveFocusRight(s0);
                pressZOnPane(1, "てつの弓", s0)
            });
            Assert.assertEq(
                expected = ("てつの弓" :: Nil, "てつのやり" :: Nil, "てつの剣" :: Nil),
                TestUnitFixtures.withWorldQuery(wFin, () ->
                    (weaponNames(0), weaponNames(1), weaponNames(2))))
        }

    /// 「ペイン0で槍 Z → ペイン2で空スロット Z」→ P0→P2 片方向 transfer、P1 不変。
    @Test
    def testGatherOneWayTransferToPane2(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshGatherTrade(rc, "iron_lance" :: Nil, "iron_bow" :: Nil, Nil);
            let ((_, _), wFin) = runScenario(rc, TurnPhase.Phase.TradeInventory, s0, () -> {
                pressZOnPane(0, "てつのやり", s0);
                moveFocusRight(s0);
                moveFocusRight(s0);
                pressZOnPaneEmpty(2, s0)
            });
            Assert.assertEq(
                expected = (Nil, "てつの弓" :: Nil, "てつのやり" :: Nil),
                TestUnitFixtures.withWorldQuery(wFin, () ->
                    (weaponNames(0), weaponNames(1), weaponNames(2))))
        }

    /// 「ペイン1で空スロット Z → ペイン0で剣 Z」→ P0→P1 受取、P2 不変。
    @Test
    def testGatherReceiveViaEmptyPick(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshGatherTrade(rc, "iron_sword" :: Nil, Nil, "iron_bow" :: Nil);
            let ((_, _), wFin) = runScenario(rc, TurnPhase.Phase.TradeInventory, s0, () -> {
                moveFocusRight(s0);
                pressZOnPaneEmpty(1, s0);
                moveFocusLeft(s0);
                pressZOnPane(0, "てつの剣", s0)
            });
            Assert.assertEq(
                expected = (Nil, "てつの剣" :: Nil, "てつの弓" :: Nil),
                TestUnitFixtures.withWorldQuery(wFin, () ->
                    (weaponNames(0), weaponNames(1), weaponNames(2))))
        }

    /// 集合交換 (FromGather) で「pick 未選択で X」→ 集合の隣接メニュー(ActionSelect) に戻る。
    @Test
    def testGatherCancelWithNoPickExitsToActionSelect(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshGatherTrade(rc, "iron_lance" :: Nil, "iron_bow" :: Nil, "iron_sword" :: Nil);
            let ((_, finalPhase), _wFin) = runScenario(rc, TurnPhase.Phase.TradeInventory, s0, () -> {
                pressXAt(s0)
            });
            Assert.assertEq(expected = TurnPhase.Phase.ActionSelect, finalPhase)
        }

    /// pick 中に X → pick 解除のみ。全員のインベントリは不変 (swap が起きていない)。
    @Test
    def testCancelDuringPickLeavesInventoriesUnchanged(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshGatherTrade(rc, "iron_lance" :: Nil, "iron_bow" :: Nil, "iron_sword" :: Nil);
            let ((_, _), wFin) = runScenario(rc, TurnPhase.Phase.TradeInventory, s0, () -> {
                pressZOnPane(0, "てつのやり", s0);
                pressXAt(s0)
            });
            Assert.assertEq(
                expected = ("てつのやり" :: Nil, "てつの弓" :: Nil, "てつの剣" :: Nil),
                TestUnitFixtures.withWorldQuery(wFin, () ->
                    (weaponNames(0), weaponNames(1), weaponNames(2))))
        }

    // ════════════════════════════════════════════════════════
    // 自分のアイテム並び替え (同じペイン内 pick → 別スロット)
    // ════════════════════════════════════════════════════════

    /// 「ペイン0で剣 Z → 同ペイン0で弓 Z」→ P0 の武器の並びが入れ替わる。他は不変。
    @Test
    def testReorderWithinOwnPane(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshGatherTrade(rc, "iron_sword" :: "iron_bow" :: Nil,
                                       "iron_lance" :: Nil, Nil);
            let ((_, _), wFin) = runScenario(rc, TurnPhase.Phase.TradeInventory, s0, () -> {
                pressZOnPane(0, "てつの剣", s0);
                pressZOnPane(0, "てつの弓", s0)
            });
            Assert.assertEq(
                expected = ("てつの弓" :: "てつの剣" :: Nil, "てつのやり" :: Nil, Nil),
                TestUnitFixtures.withWorldQuery(wFin, () ->
                    (weaponNames(0), weaponNames(1), weaponNames(2))))
        }

    /// 「ペイン0で剣 Z → 同ペイン0で同じ剣 Z」→ pick 解除のみ。並びは不変。
    @Test
    def testReSelectSameSlotDeselects(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshGatherTrade(rc, "iron_sword" :: "iron_bow" :: Nil,
                                       "iron_lance" :: Nil, Nil);
            let ((_, _), wFin) = runScenario(rc, TurnPhase.Phase.TradeInventory, s0, () -> {
                pressZOnPane(0, "てつの剣", s0);
                pressZOnPane(0, "てつの剣", s0)
            });
            Assert.assertEq(
                expected = "てつの剣" :: "てつの弓" :: Nil,
                TestUnitFixtures.withWorldQuery(wFin, () -> weaponNames(0)))
        }

    // ════════════════════════════════════════════════════════
    // 複数選択 → まとめ渡し (Shift で印 → 別ペインで Z)
    // ════════════════════════════════════════════════════════

    /// 「ペイン0で槍と弓に印 → ペイン1でまとめ確定」→ 両方 P1 へ移り P0 は空になる。
    /// 渡す順は index の大きい方からなので、P1 には弓 (index1) → 槍 (index0) の順で末尾に積まれる。
    @Test
    def testBulkTransferMovesAllMarkedItems(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let s0 = freshTradeWithWeapons(rc, "iron_lance" :: "iron_bow" :: Nil, Nil);
            let ((_, _), wFin) = runScenario(rc, TurnPhase.Phase.TradeInventory, s0, () -> {
                markOnPane(0, "てつのやり", s0);
                markOnPane(0, "てつの弓", s0);
                pressZBulkOnPane(1, s0)
            });
            Assert.assertEq(
                expected = (Nil, "てつの弓" :: "てつのやり" :: Nil),
                TestUnitFixtures.withWorldQuery(wFin, () ->
                    (weaponNames(0), weaponNames(1))))
        }

    /// まとめ渡しはアイテム単位で「受け取ると重量過多になるか」を判定し、超える手前で止める。
    /// 受け取り役は knight（体格7・力5 → 最大積載量 10.0、過多しきい値 110% = 11.0）。
    /// P1 は てつの剣(2.25) × 3 = 6.75 を持つ。P0 が槍(3.05) と弓(2.4) に印を付けて渡すと、
    /// 1 個目（6.75+2.4=9.15 or 6.75+3.05=9.8 ＜11.0）は渡るが、2 個目（合計 12.2 ≧11.0）は
    /// 過多になるため止まる → P0 に 1 個残り、P1 は 4 個になる。
    @Test
    def testBulkTransferStopsWhenReceiverFull(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let three = List.repeat(3, "iron_sword");
            let s0 = buildScenario(rc,
                ({id = 0, weapons = "iron_lance" :: "iron_bow" :: Nil, staves = Nil}: PlayerSpec) ::
                ({id = 1, weapons = three, staves = Nil}: PlayerSpec) :: Nil,
                TradeMenuUi.Origin.FromTurn);
            let ((_, _), wFin) = runScenario(rc, TurnPhase.Phase.TradeInventory, s0, () -> {
                markOnPane(0, "てつのやり", s0);
                markOnPane(0, "てつの弓", s0);
                pressZBulkOnPane(1, s0)
            });
            // 渡ったのは 1 個だけ（P0 に 1 個残り、P1 は 3 → 4 個）。
            Assert.assertEq(
                expected = (1, 4),
                TestUnitFixtures.withWorldQuery(wFin, () ->
                    (List.length(weaponNames(0)),
                     List.length(weaponNames(1)))))
        }

    /// toggledMarks (純粋): 別ペインに印を付け替えると前ペインの印は捨て、新しいペインを印元にする。
    /// 同じアイテムをもう一度トグルすると外れ、空になった時点で印元 (markPane) も None に戻る。
    @Test
    def testToggledMarksReplacesPaneAndClears(): Unit \ Assert =
        let base = {members = 0 :: 1 :: Nil, focus = 0, pick = None,
                    origin = TradeMenuUi.Origin.FromTurn, marks = Set#{}, markPane = None};
        // ペイン0で武器0に印 → ペイン1で武器0に印 (ペイン替え) → もう一度ペイン1武器0 (解除)
        let m0 = TradeMenuUi.toggledMarks(0, PlayerData.ItemKind.Weapon(0), base);
        let m1 = TradeMenuUi.toggledMarks(1, PlayerData.ItemKind.Weapon(0), m0);
        let m2 = TradeMenuUi.toggledMarks(1, PlayerData.ItemKind.Weapon(0), m1);
        Assert.assertEq(
            expected = (Some(0), Some(1), None, 0),
            (m0#markPane, m1#markPane, m2#markPane, Set.size(m2#marks)))

    // ════════════════════════════════════════════════════════
    // 純粋関数: decideConfirm / moveFocus / paneEntries(満杯)
    // ════════════════════════════════════════════════════════

    /// moveFocus は両端でラップする (左端で← → 右端、右端で→ → 左端)。
    @Test
    def testMoveFocusWrapsAtEnds(): Unit \ Assert =
        let data3 = {members = 0 :: 1 :: 2 :: Nil, focus = 0, pick = None,
                     origin = TradeMenuUi.Origin.FromGather, marks = Set#{}, markPane = None};
        let leftAt0  = TradeMenuUi.moveFocus(-1, data3);                 // 0 で左 → 2 (wrap)
        let rightMax = TradeMenuUi.moveFocus(1, {focus = 2 | data3});    // 2 で右 → 0 (wrap)
        let right    = TradeMenuUi.moveFocus(1, data3);                  // 0 で右 → 1
        Assert.assertEq(expected = (2, 0, 1), (leftAt0#focus, rightMax#focus, right#focus))

    /// decideConfirm: pick=None でスロットを pick → JustUpdate で pick がセットされる。
    @Test
    def testDecideConfirmSetsPick(): Unit \ Assert =
        let data = {members = 0 :: 1 :: Nil, focus = 0, pick = None,
                    origin = TradeMenuUi.Origin.FromTurn, marks = Set#{}, markPane = None};
        let kind = Some(PlayerData.ItemKind.Weapon(0));
        // Pick は record alias で Eq が無いので、primitive のタプルに落として比較する。
        let picked = match TradeMenuUi.decideConfirm(0, kind, data) {
            case TradeMenuUi.ConfirmOutcome.JustUpdate(d) =>
                d#pick |> Option.map(p -> (p#paneIndex, p#kind))
            case _                                            => None
        };
        Assert.assertEq(expected = Some((0, kind)), picked)

    /// decideConfirm: 別ペインで確定 → DoSwap で picker/receiver の id と kind が members から解決される。
    @Test
    def testDecideConfirmDifferentPaneProducesSwap(): Unit \ Assert =
        let data = {members = 10 :: 20 :: 30 :: Nil, focus = 0,
                    pick = Some({paneIndex = 0, kind = Some(PlayerData.ItemKind.Weapon(1))}),
                    origin = TradeMenuUi.Origin.FromGather, marks = Set#{}, markPane = None};
        let receiverKind = Some(PlayerData.ItemKind.Staff(0));
        let plan = match TradeMenuUi.decideConfirm(2, receiverKind, data) {
            case TradeMenuUi.ConfirmOutcome.DoSwap(_, p) =>
                Some((p#pickerId, p#pickerKind, p#receiverId, p#receiverKind))
            case _ => None
        };
        Assert.assertEq(
            expected = Some((10, Some(PlayerData.ItemKind.Weapon(1)), 30, receiverKind)),
            plan)

    /// decideConfirm: 同ペインの別実体スロット → DoReorder で playerId/kindA/kindB が解決される。
    @Test
    def testDecideConfirmSamePaneProducesReorder(): Unit \ Assert =
        let data = {members = 10 :: 20 :: Nil, focus = 0,
                    pick = Some({paneIndex = 0, kind = Some(PlayerData.ItemKind.Weapon(0))}),
                    origin = TradeMenuUi.Origin.FromGather, marks = Set#{}, markPane = None};
        let plan = match TradeMenuUi.decideConfirm(0, Some(PlayerData.ItemKind.Weapon(1)), data) {
            case TradeMenuUi.ConfirmOutcome.DoReorder(_, p) => Some((p#playerId, p#kindA, p#kindB))
            case _ => None
        };
        Assert.assertEq(
            expected = Some((10, PlayerData.ItemKind.Weapon(0), PlayerData.ItemKind.Weapon(1))),
            plan)

    /// 満杯メンバーのペインには空スロット "空きスロット" が出ない (片方向流入をブロック)。
    /// テストの player は catalog 先頭 (knight = ロード職) なので上限は 16。
    /// 16 個ちょうど持たせて、paneEntries の末尾が空スロットでないことを確認する。
    @Test
    def testFullPaneHasNoEmptySlot(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let sixteen = List.repeat(16, "iron_sword");
            let s0 = buildScenario(rc,
                ({id = 0, weapons = sixteen, staves = Nil}: PlayerSpec) ::
                ({id = 1, weapons = "iron_bow" :: Nil, staves = Nil}: PlayerSpec) :: Nil,
                TradeMenuUi.Origin.FromGather);
            let entries = TestUnitFixtures.withMockPartyQuery(TestUnitFixtures.worldPlayers(s0#world), () ->
                TradeMenuUi.paneEntries(0));
            let hasEmpty = List.exists(e -> e#metadata == Some(TradeMenuUi.emptySlotMeta()), entries);
            Assert.assertEq(expected = (16, false), (List.length(entries), hasEmpty))
        }

    // ════════════════════════════════════════════════════════
    // 実 asset の表示範囲の行数 ⇔ maxSlots() の一致 / チップがハイライトに収まる（幾何・ItemMenu と同型）
    // ════════════════════════════════════════════════════════

    /// 実 asset（TradeMenu.ui.json）を parse し、1 ペインの menu 直下の "row" 名の子の数を数える。
    def tradeMenuRowCount(): Int32 \ Fs.FileRead =
        match UiSpec.load(TradeMenuUi.specPath()) {
            case Ok(root) => UiSpec.countPrefixedChildren(
                                "panel" :: "panesRow" :: "pane0" :: "menu" :: Nil, "row", root)
            case Err(_)   => bug!("TradeMenu.ui.json load failed")
        }

    /// 実 asset の row 宣言数が `TradeMenuUi.maxSlots()` と一致する（表示範囲の行数の宣言過不足を弾く）。
    @Test
    def testRowDeclarationCountMatchesMaxSlots(): Unit \ {Assert, Fs.FileRead} =
        Assert.assertEq(expected = TradeMenuUi.maxSlots(), tradeMenuRowCount())

    /// design 空間の rootRect。panel は abs で内側に置かれる。
    def designRect(): Rect2.Rect2 =
        {position = {x = 0.0, y = 0.0}, size = {x = 240.0, y = 128.0}}

    /// 実 asset を spawn し、pane0/row0 を可視にして computeLayout を掛けた結果（UiWorld 同梱）。
    def tradeMenuLayout(): (UiStore.UiWorld, Map[EntityId, Rect2.Rect2]) \ Fs.FileRead =
        match UiSpec.load(TradeMenuUi.specPath()) {
            case Err(_)   => bug!("TradeMenu.ui.json load failed")
            case Ok(spec) =>
                let (rootId, ui0) = UiSpec.spawnRoot(spec, UiStore.empty());
                let ui = UiStore.setVisible("TradeMenu/panel/panesRow/pane0/menu/row0", true, ui0);
                let layout = UiLayout.computeLayout(
                    {styles = ui#styles, parents = ui#parents, order = ui#order,
                     measures = Map.empty(), visible = ui#visible},
                    rootId, designRect());
                (ui, layout)
        }

    /// 名前パスの rect を (x, y, w, h) tuple で引く。未確定は None。
    def rectAt(path: String, ui: UiStore.UiWorld, layout: Map[EntityId, Rect2.Rect2]):
            Option[(Float64, Float64, Float64, Float64)] =
        UiStore.idOf(path, ui)
            |> Option.flatMap(id -> Map.get(id, layout))
            |> Option.map(r -> (r#position#x, r#position#y, r#size#x, r#size#y))

    /// inner が outer に 4 辺とも収まるか（左右上下）。
    def contains(outer: (Float64, Float64, Float64, Float64), inner: (Float64, Float64, Float64, Float64)): Bool =
        let (ox, oy, ow, oh) = outer;
        let (ix, iy, iw, ih) = inner;
        ix >= ox and iy >= oy and (ix + iw) <= (ox + ow) and (iy + ih) <= (oy + oh)

    /// チップ（iconBg 色紙）の箱が選択ハイライトの箱に上下左右とも完全収容される
    /// （行テンプレの左 pad 1.5 でチップをハイライト内へ収める。ItemMenu と同じ不変条件）。
    @Test
    def testChipFullyContainedInHighlight(): Unit \ {Assert, Fs.FileRead} =
        let (ui, layout) = tradeMenuLayout();
        let chip = rectAt("TradeMenu/panel/panesRow/pane0/menu/row0/iconBg", ui, layout);
        let hl   = rectAt("TradeMenu/panel/panesRow/pane0/menu/highlight", ui, layout);
        Assert.assertEq(
            expected = Some(true),
            forM (h <- hl; c <- chip) yield contains(h, c))
}
