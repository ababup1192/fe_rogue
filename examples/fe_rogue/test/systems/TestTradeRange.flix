/// TradeRange — 「こうかん」確定後の緑マス overlay の振る舞いを pin する
///
/// 検証する観点:
///   - `show` 直後の `cells` が選択中味方の隣接味方マスを返す (斜めや self は除く)
///   - 隣接味方が居ないときは `show` を呼んでも `cells` は空
///   - `clear` 後は `cells` が空に戻る
mod TestTradeRange {

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    /// テスト用に最小限のフィールドだけ意味を持たせた PlayerDriver.Data。
    /// id と gridPos が役割で、他は中庸な固定値。
    def buildPartyMember(id: Int32, gridPos: {x = Int32, y = Int32}):
            PlayerDriver.Data = {
        id              = id,
        classId         = "test_player",
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
        facing          = Dir4.Down,
        hidden          = false,
        usedStairs          = false,
        level                   = 1,
        exp                     = 0,
        pendingLevelUp          = None,
        statuses                = Nil,
        rings          = Nil,
        ringEquipped          = false,
        followUpUsed   = false
    }

    /// `TradeRange.cells` の戻りを (x, y) タプルに整形する。
    /// レコードフィールドの直接比較を避け、assertEq で 1 行で比べやすくする。
    /// 緑マスは範囲 resource が権威なので `RangeOverlayState.State` を読む。
    def cellTuples(): List[(Int32, Int32)] \ RangeOverlayState.State =
        List.map(c -> (c#x, c#y), TradeRange.cells())

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
        region rc {
            TestUnitFixtures.withRangeOverlay(rc, () -> {
                let self     = buildPartyMember(0, {x = 5, y = 5});
                let northern = buildPartyMember(1, {x = 5, y = 4});
                let western  = buildPartyMember(2, {x = 4, y = 5});
                let eastern  = buildPartyMember(3, {x = 6, y = 5});
                let southern = buildPartyMember(4, {x = 5, y = 6});
                let diagSE   = buildPartyMember(5, {x = 6, y = 6});
                let party = self :: northern :: western ::
                            eastern :: southern :: diagSE :: Nil;
                TestUnitFixtures.withSelectedPlayer(0, () ->
                    TestUnitFixtures.withMockPartyQuery(party, () ->
                        TradeRange.show()));
                Assert.assertEq(
                    expected = (5, 4) :: (4, 5) :: (6, 5) :: (5, 6) :: Nil,
                    cellTuples())
            })
        }

    /// 隣接味方が居なければ `cells` は空 (= Nil)。
    /// 防御的: 隣接味方ゼロなら resource に何も書かない。
    @Test
    def testShowNoOpWhenNoAdjacentAlly(): Unit \ Assert =
        region rc {
            TestUnitFixtures.withRangeOverlay(rc, () -> {
                let self   = buildPartyMember(0, {x = 5, y = 5});
                let diagSE = buildPartyMember(1, {x = 6, y = 6});
                let party  = self :: diagSE :: Nil;
                TestUnitFixtures.withSelectedPlayer(0, () ->
                    TestUnitFixtures.withMockPartyQuery(party, () ->
                        TradeRange.show()));
                Assert.assertEq(expected = Nil, cellTuples())
            })
        }

    // ════════════════════════════════════════════════════════
    // clear — overlay を取り除く
    // ════════════════════════════════════════════════════════

    /// 一度 show で緑マスを敷いた後 clear すると `cells` が空に戻る。
    /// TradeTargetSelect → 他フェーズへ抜けるとき overlay を必ず片付けられることの保険。
    @Test
    def testClearRemovesOverlay(): Unit \ Assert =
        region rc {
            TestUnitFixtures.withRangeOverlay(rc, () -> {
                let self     = buildPartyMember(0, {x = 5, y = 5});
                let northern = buildPartyMember(1, {x = 5, y = 4});
                let party    = self :: northern :: Nil;
                TestUnitFixtures.withSelectedPlayer(0, () ->
                    TestUnitFixtures.withMockPartyQuery(party, () ->
                        TradeRange.show()));
                // show 後は 1 セル。clear は resource を空へ戻すので、その後の cells は 0 セル。
                let shownCount = List.length(cellTuples());
                TradeRange.clear();
                Assert.assertEq(
                    expected = (1, 0),
                    (shownCount, List.length(cellTuples())))
            })
        }
}
