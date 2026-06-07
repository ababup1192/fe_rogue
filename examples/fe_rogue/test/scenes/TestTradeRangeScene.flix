/// TradeRangeScene — 「こうかん」確定後の緑マス overlay の振る舞いを pin する
///
/// 検証する観点:
///   - `show` 直後の `cells` が選択中味方の隣接味方マスを返す (斜めや self は除く)
///   - 隣接味方が居ないときは `show` を呼んでも overlay ノードは作られず `cells` は空
///   - `clear` 後は `cells` が空に戻る (overlay ノードが取り除かれる)
mod TestTradeRangeScene {

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    /// テスト用に最小限のフィールドだけ意味を持たせた PlayerScene.Data。
    /// id と gridPos が役割で、他は中庸な固定値。
    def buildPartyMember(id: Int32, gridPos: {x = Int32, y = Int32}):
            PlayerScene.Data = {
        id              = id,
        gridPos         = gridPos,
        moveTiles       = 5,
        hp              = 10,
        waited          = false,
        attackTargetId  = None,
        resource        = TestUnitFixtures.testResource(5, 10),
        weapons         = TestUnitFixtures.testWeapon() :: Nil,
        staves          = Nil,
        consumables     = Nil,
        selectedItem    = None,
        moveStepsTaken  = 0,
        facing          = Staff.Direction.Down,
        hidden          = false,
        usedStairs          = false,
        level                   = 1,
        exp                     = 0,
        pendingLevelUp          = None
    }

    /// World + 与えた party の Marker2D 並びで scene を組む。
    /// PartyQuery 経由で getAll を呼ぶと id 昇順で取れる。
    def sceneWithParty(party: List[PlayerScene.Data]): Scene[NodeTag] =
        let world = Marker2D.make(Vec2.zero());
        let withWorld = Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag));
        List.foldLeft((acc, data) -> {
            let marker = Marker2D.make(Vec2.zero());
            Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(data#id),
                EngineNode.Marker2DWithState(marker, NodeTag.Player(data)), acc)
        }, withWorld, party)

    /// SelectedPlayer.State の get を指定 id 固定にする stub。put は捨てる。
    /// TradeRangeScene.show は「選択中味方の隣接味方」を見るので必要。
    def withSelectedFor(playerId: Int32, gridPos: {x = Int32, y = Int32},
                         thunk: Unit -> a \ ef): a \ (ef - SelectedPlayer.State) =
        run { thunk() } with handler SelectedPlayer.State {
            def get(k)    = k({id = Some(playerId), origin = Some(gridPos)})
            def put(_, k) = k()
        }

    /// `TradeRangeScene.cells` の戻りを (x, y) タプルに整形する。
    /// レコードフィールドの直接比較を避け、assertEq で 1 行で比べやすくする。
    def cellTuples(scene: Scene[NodeTag]): List[(Int32, Int32)] =
        List.map(c -> (c#x, c#y), TradeRangeScene.cells(scene))

    // ════════════════════════════════════════════════════════
    // show — 選択中味方の隣接マスだけを緑で敷く
    // ════════════════════════════════════════════════════════

    /// 配置 (self id=0 at (5,5)):
    ///       (5,4) id=1
    /// (4,5) (5,5) (6,5) id=3
    ///  id=2 (self)
    ///       (5,6) id=4
    ///   (6,6) id=5  ← 斜めなので非隣接 / overlay には載らない
    ///
    /// 期待 (id 昇順 = (5,4) → (4,5) → (6,5) → (5,6)):
    @Test
    def testShowPaintsOnlyOrthogonalAllyCells(): Unit \ Assert =
        let self     = buildPartyMember(0, {x = 5, y = 5});
        let northern = buildPartyMember(1, {x = 5, y = 4});
        let western  = buildPartyMember(2, {x = 4, y = 5});
        let eastern  = buildPartyMember(3, {x = 6, y = 5});
        let southern = buildPartyMember(4, {x = 5, y = 6});
        let diagSE   = buildPartyMember(5, {x = 6, y = 6});
        let scene = sceneWithParty(self :: northern :: western ::
                                    eastern :: southern :: diagSE :: Nil);
        let after = withSelectedFor(0, {x = 5, y = 5}, () ->
            TestUnitFixtures.withMockPartyQuery(scene, () ->
                TradeRangeScene.show(scene)));
        Assert.assertEq(
            expected = (5, 4) :: (4, 5) :: (6, 5) :: (5, 6) :: Nil,
            cellTuples(after))

    /// 隣接味方が居なければ overlay は作られず `cells` は空 (= Nil)。
    /// 防御的: 描画ノードを無駄に作らない。
    @Test
    def testShowNoOpWhenNoAdjacentAlly(): Unit \ Assert =
        let self   = buildPartyMember(0, {x = 5, y = 5});
        let diagSE = buildPartyMember(1, {x = 6, y = 6});
        let scene = sceneWithParty(self :: diagSE :: Nil);
        let after = withSelectedFor(0, {x = 5, y = 5}, () ->
            TestUnitFixtures.withMockPartyQuery(scene, () ->
                TradeRangeScene.show(scene)));
        Assert.assertEq(expected = Nil, cellTuples(after))

    // ════════════════════════════════════════════════════════
    // clear — overlay ノードを取り除く
    // ════════════════════════════════════════════════════════

    /// 一度 show で緑マスを敷いた後 clear すると `cells` が空に戻る。
    /// TradeTargetSelect → 他フェーズへ抜けるとき overlay を必ず片付けられることの保険。
    @Test
    def testClearRemovesOverlay(): Unit \ Assert =
        let self     = buildPartyMember(0, {x = 5, y = 5});
        let northern = buildPartyMember(1, {x = 5, y = 4});
        let scene = sceneWithParty(self :: northern :: Nil);
        let withRange = withSelectedFor(0, {x = 5, y = 5}, () ->
            TestUnitFixtures.withMockPartyQuery(scene, () ->
                TradeRangeScene.show(scene)));
        let cleared = TradeRangeScene.clear(withRange);
        // (show 後は 1 セル / clear 後は 0 セル) を 1 タプルで pin
        Assert.assertEq(
            expected = (1, 0),
            (List.length(TradeRangeScene.cells(withRange)),
             List.length(TradeRangeScene.cells(cleared))))
}
