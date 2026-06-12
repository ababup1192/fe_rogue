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
            pendingLevelUp    = None
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
}
