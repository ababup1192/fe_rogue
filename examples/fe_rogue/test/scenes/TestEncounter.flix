/// Encounter のテスト — units に対するクエリ helper
///
/// `fromScene`（scene → Encounter の join）は scene 構築が要るため scene ベースの
/// 既存テスト（TestEnemyAI / TestActionMenuScene）が間接的にカバーする。ここでは
/// 手組みの units に対する `enemiesOf` / `alliesOf` / `unitAt` / `sameCellAlly` を純粋値で検証する。
mod TestEncounter {

    /// クエリ helper は board を見ないので、最小の床のみ盤面で十分。
    def trivialMap(): MapSnapshot =
        {
            tileSize     = 16.0,
            usedRect     = {position = {x = 0, y = 0}, size = ({x = 8, y = 8}: {x = Int32, y = Int32})},
            wallCells    = (Set#{}: Set[(Int32, Int32)]),
            mapGlobal    = {x = 0.0, y = 0.0},
            placements   = Nil
        }

    def at(x: Int32, y: Int32): {x = Int32, y = Int32} = {x = x, y = y}

    /// hp=10・武器なし・生存の最小 UnitView。実体は TestUnitFixtures.mkUnit（共有 builder）。
    def mkUnit(id: Int32, faction: Faction, pos: {x = Int32, y = Int32}): UnitView =
        TestUnitFixtures.mkUnit(id, faction, pos, 10, false, None)

    def encOf(units: List[UnitView]): Encounter =
        {board = {map = trivialMap(), pieces = Nil}, units = units}

    /// 味方 2 + 敵 2 の Encounter（id: 味方 0,1 / 敵 10,11）。
    def sampleUnits(): List[UnitView] =
        mkUnit(0, Faction.Player, at(0, 0)) ::
        mkUnit(1, Faction.Player, at(1, 0)) ::
        mkUnit(10, Faction.Enemy, at(2, 0)) ::
        mkUnit(11, Faction.Enemy, at(3, 0)) :: Nil

    def idsOf(units: List[UnitView]): List[Int32] =
        List.map(u -> u#id, units)

    // ════════════════════════════════════════════════════════
    // enemiesOf / alliesOf: faction で分ける
    // ════════════════════════════════════════════════════════

    /// 敵視点の「敵」= 味方ユニット（id 0,1）
    @Test
    def testEnemiesOfFromEnemy(): Unit \ Assert =
        Assert.assertEq(expected = 0 :: 1 :: Nil,
                          idsOf(Encounter.enemiesOf(Faction.Enemy, encOf(sampleUnits()))))

    /// 敵視点の「味方」= 敵ユニット（id 10,11）
    @Test
    def testAlliesOfFromEnemy(): Unit \ Assert =
        Assert.assertEq(expected = 10 :: 11 :: Nil,
                          idsOf(Encounter.alliesOf(Faction.Enemy, encOf(sampleUnits()))))

    // ════════════════════════════════════════════════════════
    // unitAt: 座標 → ユニット
    // ════════════════════════════════════════════════════════

    /// (2,0) に居る敵 id=10 を引く
    @Test
    def testUnitAtFindsUnit(): Unit \ Assert =
        let found = Encounter.unitAt(at(2, 0), encOf(sampleUnits())) |> Option.map(u -> u#id);
        Assert.assertEq(expected = Some(10), found)

    /// 誰も居ないセルは None
    @Test
    def testUnitAtEmptyIsNone(): Unit \ Assert =
        let found = Encounter.unitAt(at(7, 7), encOf(sampleUnits())) |> Option.map(u -> u#id);
        Assert.assertEq(expected = None, found)

    // ════════════════════════════════════════════════════════
    // sameCellAlly: 自セルに別の同 faction 味方が重なるか
    // ════════════════════════════════════════════════════════

    /// 自分(id0,(0,0)) のセルに別味方(id1) を重ねると true
    @Test
    def testSameCellAllyOverlap(): Unit \ Assert =
        let self = mkUnit(0, Faction.Player, at(0, 0));
        let units = self ::
                    mkUnit(1, Faction.Player, at(0, 0)) ::
                    mkUnit(10, Faction.Enemy, at(2, 0)) :: Nil;
        Assert.assertEq(expected = true, Encounter.sameCellAlly(self, encOf(units)))

    /// 同セルに敵しか居ない / 自分だけなら false（敵は味方判定に含めない）
    @Test
    def testSameCellAllyNoOverlap(): Unit \ Assert =
        let self = mkUnit(0, Faction.Player, at(0, 0));
        let units = self ::
                    mkUnit(10, Faction.Enemy, at(0, 0)) :: Nil;
        Assert.assertEq(expected = false, Encounter.sameCellAlly(self, encOf(units)))
}
