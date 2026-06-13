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
    // DSL 経路（EffectRule → planActions → runPlan）が旧経路と同じ HP を生むか
    //   きずぐすりを「効果 JSON」として宣言し、実 Scene handler で発火しても
    //   applyConsumableHeal と同じ結果（HP 4 → 7）になることを実 engine 関数で確認する。
    //   ライブ gameplay コードは一切変えていない（handler はここで組む）。
    // ════════════════════════════════════════════════════════

    /// PlanItem を実 Scene へ落とす handler 束。heal だけ実装し、他は恒等（このテストでは未使用）。
    /// heal は applyConsumableHeal と同じ「Combat.heal → mapPlayer → HPBar 更新」を行う（ログは省略）。
    def dslSceneHandlers(): EffectRunner.PlanHandlers[Scene[NodeTag], {}] = {
        heal       = (sc, id, _, amount) -> match PlayerScene.get(id, sc) {
            case Some(p) =>
                let r = Combat.heal(p#hp, p#resource#hp, amount);
                sc |> PlayerScene.mapPlayer(id, d -> {hp = r#newHp | d})
                   |> UnitHPBarScene.update(PlayerScene.playerPath(id), r#newHp)
            case None    => sc
        },
        fullHeal   = (sc, _, _)          -> sc,
        damage     = (sc, _, _, _)       -> sc,
        maxHpUp    = (sc, _, _, _)       -> sc,
        status     = (sc, _, _, _, _, _) -> sc,
        immobilize = (sc, _, _)          -> sc,
        revive     = (sc, _, _)          -> sc,
        custom     = (sc, _, _, _)       -> sc,
        sfx        = (sc, _)             -> sc,
        noOp       = (sc, _)             -> sc
    }

    /// きずぐすりを効果 JSON として宣言 → decode → plan → runPlan で実 Scene に発火 → HP 7。
    /// 旧経路 testConsumableHealRestoresHp と同じ結果になり、DSL 化が等価であることを示す。
    @Test
    def testConsumableHealViaDsl(): Unit \ Assert =
        let scene = playerScene(4, 0);
        let json = "{\"when\":\"onUse\",\"do\":[{\"to\":{\"role\":\"self\"},\"op\":\"healFlat\",\"amount\":{\"flat\":3}}]}";
        let ctx = {selfId = 0, attackerId = 0, rayUnits = (Nil: List[EffectRule.RayUnit]),
                   amount = {max = 10, dealt = 0, incoming = 0, magic = 0}};
        let items = Util.Json.parse(json)
                        |> Result.toOption
                        |> Option.flatMap(EffectRuleCodec.decodeRule)
                        |> Option.map(r -> EffectPlan.planActions(r, ctx))
                        |> Option.getWithDefault(Nil);
        let after = EffectRunner.runPlan(dslSceneHandlers(), items, scene);
        Assert.assertEq(expected = 7, PlayerScene.getHp(0, after))

    // ════════════════════════════════════════════════════════
    // 本番スイッチ後: applyConsumableSelfEffect が DSL 経路で旧挙動と一致する
    //   （applyConsumableSelfEffect は EffectBridge→planActions→runPlan→既存 primitive を通る）
    // ════════════════════════════════════════════════════════

    /// きずぐすり(Heal,3): DSL 経路の applyConsumableSelfEffect で HP 4→7。
    @Test
    def testSelfEffectHealViaDslPath(): Unit \ Assert =
        let scene = playerScene(4, 0);
        let user = playerData(scene);
        let after = TestUnitFixtures.withMockGameLogger(() ->
            StaffCastScene.applyConsumableSelfEffect(0, user, healItem(3), scene));
        Assert.assertEq(expected = 7, PlayerScene.getHp(0, after))

    /// ちから薬(AtkUp,4,3T): DSL 経路で AtkUp+4 が付与される（→ applySelfStatus）。
    @Test
    def testSelfEffectAtkUpViaDslPath(): Unit \ Assert =
        let scene = playerScene(10, 0);
        let user = playerData(scene);
        let item = Consumable.bottle(Consumable.ConsumableEffect.AtkUp, 4, 3, "ちから薬");
        let after = TestUnitFixtures.withMockGameLogger(() ->
            StaffCastScene.applyConsumableSelfEffect(0, user, item, scene));
        let atk = PlayerScene.get(0, after)
                    |> Option.map(p -> StatusSystem.sumOf(StatusSystem.StatusEffect.AtkUp, p#statuses))
                    |> Option.getWithDefault(-1);
        Assert.assertEq(expected = 4, atk)

    /// 命の草(MaxHpUp,3): DSL 経路で HP と最大HP を両方 +3（4/10 → 7/13）。
    @Test
    def testSelfEffectMaxHpUpViaDslPath(): Unit \ Assert =
        let scene = playerScene(4, 0);
        let user = playerData(scene);
        let item = Consumable.bottle(Consumable.ConsumableEffect.MaxHpUp, 3, 0, "命の草");
        let after = TestUnitFixtures.withMockGameLogger(() ->
            StaffCastScene.applyConsumableSelfEffect(0, user, item, scene));
        let hpMax = PlayerScene.get(0, after)
                    |> Option.map(p -> (p#hp, p#resource#hp))
                    |> Option.getWithDefault((-1, -1));
        Assert.assertEq(expected = (7, 13), hpMax)

    // ════════════════════════════════════════════════════════
    // 投擲の DSL 経路（applyConsumableEffectDsl）が当たった相手に効く（ally で player/enemy 出し分け）
    //   ここでは味方(ally=true)に当てる枝を確認。enemy 枝は同一ヘルパの else で対称。
    // ════════════════════════════════════════════════════════

    /// きずぐすりを味方#0 に投げて当てると HP 4→7（旧 applyConsumableEffectToPlayer と同一）。
    @Test
    def testThrowHealAtAllyViaDsl(): Unit \ Assert =
        let scene = playerScene(4, 0);
        let after = StaffCastScene.applyConsumableEffectDsl(healItem(3), 0, true, scene);
        Assert.assertEq(expected = 7, PlayerScene.getHp(0, after))

    /// ちから薬を味方#0 に投げて当てると AtkUp+4 が付与される（投擲で味方を強化できる）。
    @Test
    def testThrowAtkUpAtAllyViaDsl(): Unit \ Assert =
        let item = Consumable.bottle(Consumable.ConsumableEffect.AtkUp, 4, 3, "ちから薬");
        let scene = playerScene(10, 0);
        let after = StaffCastScene.applyConsumableEffectDsl(item, 0, true, scene);
        let atk = PlayerScene.get(0, after)
                    |> Option.map(p -> StatusSystem.sumOf(StatusSystem.StatusEffect.AtkUp, p#statuses))
                    |> Option.getWithDefault(-1);
        Assert.assertEq(expected = 4, atk)

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
