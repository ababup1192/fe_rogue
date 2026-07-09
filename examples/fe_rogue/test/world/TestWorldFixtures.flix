// TestWorldFixtures — World.Cmd 直組みの World フィクスチャ。
//
// 既存 TestUnitFixtures の scene 手組み（Marker2D + syncFromScene）に対し、こちらは
// spawn funnel（PlayerScene.addOnePlayer / EnemyScene.addOneEnemy）が emit するのと
// 同じ形の Cmd 列を World.empty() に適用して、scene 無しで「味方 / 敵 / 盤面」入りの
// World を組む。UnitResource / WeaponResource は TestUnitFixtures の物を再利用する。
//
// 使い方:
//   let w = TestWorldFixtures.duelWorld();                      // 代表 fixture（2 体 + 盤面）
//   let w = TestWorldFixtures.worldOf(List.flatten(
//       TestWorldFixtures.boardCmds({w = 13, h = 13}, Some({x = 5, y = 5}))
//       :: TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, {x = 2, y = 2}))
//       :: TestWorldFixtures.enemyCmds(TestWorldFixtures.unitSpec(1, {x = 3, y = 2}))
//       :: Nil));                                                // 自由に組む

mod TestWorldFixtures {

    use World.Cmd
    use World.EntityRef

    // ════════════════════════════════════════════════════════
    // 宣言（spec）と適用（worldOf）
    // ════════════════════════════════════════════════════════

    /// ユニット 1 体の宣言（味方 / 敵 共用）。id・位置・HP・移動力だけで組める。
    pub type alias UnitSpec = {
        id        = Int32,
        pos       = {x = Int32, y = Int32},
        hp        = Int32,
        moveTiles = Int32
    }

    /// 既定のユニット宣言（HP 10 / 移動 4）。必要なフィールドだけ `{hp = 4 | unitSpec(...)}` で上書きする。
    pub def unitSpec(id: Int32, pos: {x = Int32, y = Int32}): UnitSpec =
        {id = id, pos = pos, hp = 10, moveTiles = 4}

    /// Cmd 列を World.empty() に順に適用して World を組む（production と同じ applyCmd を通す）。
    pub def worldOf(cmds: List[Cmd]): World =
        List.foldLeft((w, c) -> World.applyCmd(c, w), World.empty(), cmds)

    // ════════════════════════════════════════════════════════
    // 味方 / 敵 の spawn Cmd 列
    // ════════════════════════════════════════════════════════

    /// 味方 1 体分の spawn Cmd 列。`PlayerScene.addOnePlayer` が emit する store 集合と同じものを
    /// 埋める（位置 / HP / 各フラグ / 進行度 / 武器 / 戦闘値 / 在庫 / 成長 / 武器投影 / 指輪ボーナス）。
    /// 描画位置（renderPos）もセル中心で seed するので、render 系のテストにもそのまま使える。
    pub def playerCmds(spec: UnitSpec): List[Cmd] =
        let res    = TestUnitFixtures.testResource(spec#moveTiles, spec#hp);
        let weapon = TestUnitFixtures.testWeapon();
        let ref    = EntityRef.Player(spec#id);
        Cmd.Spawn(ref)
            :: Cmd.Move(ref, spec#pos)
            :: Cmd.SetRenderPos(ref, MapSnapshot.cellCenter(spec#pos))
            :: Cmd.SetHp(ref, spec#hp)
            :: Cmd.SetFollowUpUsed(ref, false)
            :: Cmd.SetWaited(ref, false)
            :: Cmd.SetUsedStairs(ref, false)
            :: Cmd.SetProgress(ref, res#level, 0)
            :: Cmd.SetWeapons(ref, weapon :: Nil)
            :: Cmd.SetBaseStats(ref, Combat.baseStatsFrom(res))
            :: Cmd.SetMoveTiles(ref, spec#moveTiles)
            :: Cmd.SetStaves(ref, Nil)
            :: Cmd.SetConsumables(ref, Nil)
            :: Cmd.SetRings(ref, Nil)
            :: Cmd.SetRingEquipped(ref, false)
            :: Cmd.SetGrowth(spec#id, {base = LevelSystem.statsOf(res),
                                       rates = res#growthRates,
                                       name = res#description})
            :: Cmd.SetWeaponView(ref, Combat.weaponView(Some(weapon), true))
            :: Cmd.SetRingBonus(ref, Ring.bonuses(None))
            // テンプレート（classId/resource）と向き/歩数も addOnePlayer と同じく seed する
            // （renderUnits の World 在籍列挙・dataFromWorld gate がこれを要求する）。
            :: Cmd.SetClassId(spec#id, "test_player")
            :: Cmd.SetPlayerResource(spec#id, res)
            :: Cmd.SetFacing(spec#id, Dir4.Down)
            :: Cmd.SetMoveSteps(spec#id, 0)
            :: Nil

    /// 敵 1 体分の spawn Cmd 列。`EnemyScene.addOneEnemy` が emit する store 集合と同じものを埋める
    /// （位置 / HP / 敵フラグ / 武器 / 戦闘値 / effectRule / 指輪 / 武器投影 / 指輪ボーナス）。
    pub def enemyCmds(spec: UnitSpec): List[Cmd] =
        let res    = TestUnitFixtures.testEnemyResource(spec#moveTiles, spec#hp);
        let weapon = TestUnitFixtures.testWeapon();
        let ref    = EntityRef.Enemy(spec#id);
        Cmd.Spawn(ref)
            :: Cmd.Move(ref, spec#pos)
            :: Cmd.SetRenderPos(ref, MapSnapshot.cellCenter(spec#pos))
            :: Cmd.SetHp(ref, spec#hp)
            :: Cmd.SetAlerted(ref, false)
            :: Cmd.SetActed(ref, false)
            :: Cmd.SetBottleUsed(ref, false)
            :: Cmd.SetFollowUpUsed(ref, false)
            :: Cmd.SetWeapons(ref, weapon :: Nil)
            :: Cmd.SetBaseStats(ref, Combat.baseStatsFrom(res))
            :: Cmd.SetMoveTiles(ref, spec#moveTiles)
            :: Cmd.SetEffectRule(spec#id, None)
            :: Cmd.SetEnemyRing(spec#id, None)
            :: Cmd.SetWeaponView(ref, Combat.weaponView(Some(weapon), true))
            :: Cmd.SetRingBonus(ref, Ring.bonuses(None))
            // テンプレート（catalog id / 出身部屋 / resource 本体）も addOneEnemy と同じく seed する
            // （renderUnits の World 在籍列挙・dataFromWorldEnemy gate がこれを要求する）。
            :: Cmd.SetEnemyProfile(spec#id, {resourceId = "test_enemy", homeModuleIdx = 0})
            :: Cmd.SetEnemyResource(spec#id, res)
            :: Nil

    // ════════════════════════════════════════════════════════
    // 盤面（地形 read-model + 階段）
    // ════════════════════════════════════════════════════════

    /// 壁なし w×h・1 部屋の地形 read-model。scene の TileLayer を経由せず MapSnapshot を直組みする
    /// （`Cmd.SetMapSnapshot` に渡す値）。
    pub def floorSnapshot(size: {w = Int32, h = Int32}): MapSnapshot =
        {tileSize   = MapSnapshot.tileSize(),
         usedRect   = {position = {x = 0, y = 0}, size = {x = size#w, y = size#h}},
         wallCells  = Set.empty(),
         mapGlobal  = {x = 0.0, y = 0.0},
         placements = RoomLayout.singleRoom(size#w, size#h)}

    /// 盤面 seed の Cmd 列（地形 read-model・マップ layout・階段セル）。`stairs = None` なら階段なし。
    /// layout は 1 部屋 Plan（roomCount=1・floorSnapshot と整合）＝fog / スポーン系が「部屋」として扱う。
    pub def boardCmds(size: {w = Int32, h = Int32}, stairs: Option[{x = Int32, y = Int32}]): List[Cmd] =
        Cmd.SetMapSnapshot(Some(floorSnapshot(size)))
            :: Cmd.SetMapLayout(Some({
                   plan = ({modulePaths = Nil, sideConnections = Nil, roomCount = 1}: DungeonGenerator.Plan),
                   spawnGrid = {x = 2, y = 2}}))
            :: Cmd.SetStairs(stairs)
            :: Nil

    // ════════════════════════════════════════════════════════
    // 代表 fixture
    // ════════════════════════════════════════════════════════

    /// 代表 fixture: 13×13 の壁なし盤面に、味方 id0=(2,2) と敵 id1=(3,2)（隣接）、階段 (5,5)。
    /// 戦闘 / 移動 / render 系のテストがそのまま使える最小の「駒 2 体 + 盤面」。
    pub def duelWorld(): World =
        worldOf(List.flatten(
            boardCmds({w = 13, h = 13}, Some({x = 5, y = 5}))
                :: playerCmds(unitSpec(0, {x = 2, y = 2}))
                :: enemyCmds(unitSpec(1, {x = 3, y = 2}))
                :: Nil))

    // ════════════════════════════════════════════════════════
    // タプル射影（record は Eq 非派生のため assertEq 用に変換する）
    // ════════════════════════════════════════════════════════

    /// 位置を (x, y) タプルで読む。
    pub def posT(ref: EntityRef, world: World): Option[(Int32, Int32)] =
        World.posOf(ref, world) |> Option.map(p -> (p#x, p#y))

    /// 戦闘ビューの (素の攻撃, 最大 HP, 装備武器の攻撃) を読む（combatViewOf が解決できたかの確認込み。
    /// 武器なしは第 3 要素 -1）。
    pub def combatT(ref: EntityRef, world: World): Option[(Int32, Int32, Int32)] =
        World.combatViewOf(ref, world) |> Option.map(v ->
            (v#attack, v#maxHp,
             v#weapon |> Option.map(wv -> wv#attack) |> Option.getWithDefault(-1)))

    // ════════════════════════════════════════════════════════
    // fixture 自体のユニットテスト（store 値を具体値で pin する）
    // ════════════════════════════════════════════════════════

    /// duelWorld は 味方(2,2)/敵(3,2) の位置と HP 10/10 を World store に seed する。
    /// scene を一切介さず posOf / hpOf が引けること（Cmd 直 seed の成立）を pin する。
    @Test
    def testDuelWorldSeedsPositionsAndHp(): Unit \ Assert =
        let w = duelWorld();
        Assert.assertEq(
            expected = (Some((2, 2)), Some((3, 2)), Some(10), Some(10)),
            (posT(EntityRef.Player(0), w),
             posT(EntityRef.Enemy(1), w),
             World.hpOf(EntityRef.Player(0), w),
             World.hpOf(EntityRef.Enemy(1), w)))

    /// 陣営（team store）と戦闘ビューを pin する。素の攻撃 3 / 最大 HP 10（testResource）、
    /// 装備武器の攻撃 2（testWeapon）。combatViewOf が Some で解決できる＝
    /// baseStats / weaponView / ringBonus が揃って seed されている証拠。
    @Test
    def testDuelWorldSeedsTeamAndCombatView(): Unit \ Assert =
        let w = duelWorld();
        Assert.assertEq(
            expected = (Some(Faction.Player), Some(Faction.Enemy),
                        Some((3, 10, 2)), Some((3, 10, 2))),
            (World.teamOf(0, w), World.teamOf(World.enemyUid(1), w),
             combatT(EntityRef.Player(0), w), combatT(EntityRef.Enemy(1), w)))

    /// 盤面 read-model の pin。scene 無しで Board が組めて（boardOf が Some）、
    /// (2,2) は床・盤外 (13,2) は床でない・階段は (5,5) に立つ。
    @Test
    def testDuelWorldSeedsBoardAndStairs(): Unit \ Assert =
        let w = duelWorld();
        Assert.assertEq(
            expected = (Some(true), Some(false), Some((5, 5))),
            (World.boardOf(w) |> Option.map(b -> MapSnapshot.isFloor({x = 2, y = 2}, b#map)),
             World.boardOf(w) |> Option.map(b -> MapSnapshot.isFloor({x = 13, y = 2}, b#map)),
             World.stairsPosOf(w) |> Option.map(p -> (p#x, p#y))))

    /// Despawn は対象ユニットの store だけを消す（同居ユニットは無傷）。
    /// fixture の Cmd 列が後続 Cmd と自由に合成できることの確認。
    @Test
    def testDespawnRemovesOnlyThatUnit(): Unit \ Assert =
        let w = worldOf(List.flatten(
            boardCmds({w = 13, h = 13}, None)
                :: playerCmds(unitSpec(0, {x = 2, y = 2}))
                :: enemyCmds(unitSpec(1, {x = 3, y = 2}))
                :: (Cmd.Despawn(EntityRef.Enemy(1)) :: Nil)
                :: Nil));
        Assert.assertEq(
            expected = (None, None, Some(10), Some((2, 2))),
            (World.hpOf(EntityRef.Enemy(1), w),
             posT(EntityRef.Enemy(1), w),
             World.hpOf(EntityRef.Player(0), w),
             posT(EntityRef.Player(0), w)))

    /// spec の上書き（HP 4 / 移動 2）が対応する store にそのまま届く。
    @Test
    def testUnitSpecOverridesReachStores(): Unit \ Assert =
        let w = worldOf(playerCmds({hp = 4, moveTiles = 2 | unitSpec(3, {x = 1, y = 1})}));
        Assert.assertEq(
            expected = (Some(4), Some(2), Some((1, 1))),
            (World.hpOf(EntityRef.Player(3), w),
             World.moveTilesOf(EntityRef.Player(3), w),
             posT(EntityRef.Player(3), w)))
}
