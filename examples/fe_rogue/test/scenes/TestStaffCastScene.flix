// StaffCastScene の効果適用ロジックの検証。
//
// 杖・消費アイテムの「実際に HP を動かす」段を確認する。フル発動（applyStaffCast /
// applyConsumableUse）は effect が多く（Tween / AnimationPlayer / TurnPhase / SelectedPlayer /
// EnemyTurn / Audio …）モックが重いため、回復の中核 2 関数を単体で確認する。
//
// 検証する観点:
//   - 回復は最大 HP を超えない（上限クランプの不変条件）
//   - 消費アイテムは使用者自身を healAmount だけ回復する
//
// 方向選択の純粋ロジック（deltaToDirection / pickHealDirection）は Staff モジュールに
// 移したので TestStaff 側で検証している。

mod TestStaffCastScene {

    // ════════════════════════════════════════════════════════
    // テスト用シーン構築
    // ════════════════════════════════════════════════════════

    /// 1 体だけの味方シーンを作る。`hp` は現在 HP、最大 HP は 10 固定（resource#hp）。
    /// `magicAttack` は回復量（魔力 + 10）を決める。HPBar ノードは持たないが、
    /// `UnitHPBarScene.update` は対象が無ければ何もしないので回復結果には影響しない。
    def playerScene(hp: Int32, magicAttack: Int32): Scene[NodeTag] =
        let pos = {x = 80.0, y = 80.0};
        let marker = Marker2D.make(pos);
        let world = Marker2D.make(Vec2.zero())
            |> CanvasItem.setYSortEnabled(true);
        let data: PlayerScene.Data = {
            id                = 0,
            gridPos           = {x = 5, y = 5},
            moveTiles         = 5,
            hp                = hp,
            waited            = false,
            attackTargetId    = None,
            resource          = TestUnitFixtures.testResourceMagic(5, 10, 3, 1, magicAttack, 0, 3),
            weapons           = Nil,
            staves            = Nil,
            consumables       = Nil,
            selectedItem      = None,
            moveStepsTaken    = 0,
            facing            = Staff.Direction.Down,
            hidden            = false,
            usedStairs        = false,
            level             = 1,
            exp               = 0,
            pendingLevelUp    = None,
            statuses          = Nil,
            rings          = Nil,
            ringEquipped          = false,
            followUpUsed   = false
        };
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(marker, NodeTag.Player(data)))

    /// scene 内 Player(0) の Data を取り出す（効果適用関数に渡す caster 用）。
    def playerData(scene: Scene[NodeTag]): PlayerScene.Data =
        match PlayerScene.get(0, scene) {
            case Some(d) => d
            case None    => bug!("player 0 not found in test scene")
        }

    /// テスト用の消費アイテム（回復量を指定）。
    def healItem(healAmount: Int32): Consumable.ConsumableResource =
        {name       = "きずぐすり",
         effect     = Consumable.ConsumableEffect.Heal,
         magnitude  = healAmount,
         duration   = 0,
         healAmount = healAmount,
         durability = 5,
         sprite     = ({texture = "t", hframes = 1, vframes = 1, frame = 0,
                         offset = {x = 0.0, y = 0.0},
                         scale = {x = 1.0, y = 1.0}, flipForFacing = false}: Sprite.SpriteResource),
         description = ""}

    // ════════════════════════════════════════════════════════
    // 回復杖（ライブ）— 最大 HP を超えない
    // ════════════════════════════════════════════════════════

    /// HP 5 / 最大 10 の味方に「魔力 0 + 10 = 10」回復をかけると、5 + 10 = 15 ではなく
    /// 上限 10 で頭打ちになる（回復は最大 HP を超えない）。
    @Test
    def testHealStaffClampsAtMaxHp(): Unit \ Assert =
        let scene = playerScene(5, 0);
        let caster = playerData(scene);
        let after = TestUnitFixtures.withMockGameLogger(() ->
            StaffCastScene.applyHealToPlayer(0, caster, 0, scene));
        Assert.assertEq(expected = 10, PlayerScene.getHp(0, after))

    // ════════════════════════════════════════════════════════
    // 消費アイテム — 使用者自身を healAmount 回復
    // ════════════════════════════════════════════════════════

    /// HP 4 / 最大 10 の味方が回復量 3 の消費アイテムを使うと、HP が 7 になる
    /// （4 + 3 = 7、上限 10 には届かないのでそのまま）。
    @Test
    def testConsumableHealRestoresHp(): Unit \ Assert =
        let scene = playerScene(4, 0);
        let user = playerData(scene);
        let after = TestUnitFixtures.withMockGameLogger(() ->
            StaffCastScene.applyConsumableHeal(0, user, healItem(3), scene));
        Assert.assertEq(expected = 7, PlayerScene.getHp(0, after))

    // ════════════════════════════════════════════════════════
    // 一時しのぎのワープ先選定（warpCellFor・純粋）
    // ════════════════════════════════════════════════════════

    /// 13×13 床・指定 wallCells・指定 pieces のテスト用 Board。
    def mkBoard(wallCells: Set[(Int32, Int32)],
                 pieces: List[(Piece, {x = Int32, y = Int32})]): Board =
        let map: MapSnapshot = {
            tileSize    = 16.0,
            usedRect    = {position = {x = 0, y = 0}, size = ({x = 13, y = 13}: {x = Int32, y = Int32})},
            wallCells   = wallCells,
            mapGlobal   = {x = 0.0, y = 0.0},
            placements  = Nil
        };
        {map = map, pieces = pieces}

    /// `{x, y}` は Eq を持たないので、比較用にタプルへ落とす。
    def cellTuple(c: Option[{x = Int32, y = Int32}]): Option[(Int32, Int32)] =
        Option.map(p -> (p#x, p#y), c)

    /// 階段が空いていれば、ワープ先は階段マスそのもの。
    @Test
    def testWarpCellStairsFree(): Unit \ Assert =
        let board = mkBoard(Set#{}, Nil);
        Assert.assertEq(
            expected = Some((5, 5)),
            cellTuple(StaffCastScene.warpCellFor(Some({x = 5, y = 5}), board)))

    /// 階段が埋まっていれば、隣接する歩ける空きマス（最初に試す上 = y-1）へ。
    @Test
    def testWarpCellStairsOccupied(): Unit \ Assert =
        let board = mkBoard(Set#{}, (Piece.Enemy(9), {x = 5, y = 5}) :: Nil);
        Assert.assertEq(
            expected = Some((5, 4)),
            cellTuple(StaffCastScene.warpCellFor(Some({x = 5, y = 5}), board)))

    /// 階段が埋まり隣接 4 マスがすべて壁なら、ワープ先なし（None → 停止だけ）。
    @Test
    def testWarpCellNoFreeNeighbor(): Unit \ Assert =
        let walls = Set#{(5, 4), (5, 6), (4, 5), (6, 5)};
        let board = mkBoard(walls, (Piece.Enemy(9), {x = 5, y = 5}) :: Nil);
        Assert.assertEq(
            expected = None,
            cellTuple(StaffCastScene.warpCellFor(Some({x = 5, y = 5}), board)))

    /// 階段が未配置（None）ならワープ先なし。
    @Test
    def testWarpCellNoStairs(): Unit \ Assert =
        let board = mkBoard(Set#{}, Nil);
        Assert.assertEq(expected = None, cellTuple(StaffCastScene.warpCellFor(None, board)))

    // ════════════════════════════════════════════════════════
    // 敵クレリックが詠唱する杖（enemyStaffFor・純粋）
    // ════════════════════════════════════════════════════════

    /// クレリック_T2 はかなしばり、T3 は一時しのぎ、それ以外の職は詠唱しない。
    @Test
    def testEnemyStaffForByClass(): Unit \ Assert =
        Assert.assertEq(
            expected = (Some(Staff.StaffEffect.Bind), Some(Staff.StaffEffect.Stopgap), None),
            (StaffCastScene.enemyStaffFor("クレリック_T2"),
             StaffCastScene.enemyStaffFor("クレリック_T3"),
             StaffCastScene.enemyStaffFor("ファイター_T1")))
}
