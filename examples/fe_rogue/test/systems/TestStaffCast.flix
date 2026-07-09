// StaffCast の効果適用ロジックの検証。
//
// 杖・消費アイテムの「実際に HP を動かす」段を確認する。フル発動（applyStaffCast /
// applyConsumableUse）は effect が多く（Tween / TurnPhase / SelectedPlayer /
// EnemyTurn / Audio …）モックが重いため、回復の中核 2 関数を単体で確認する。
//
// 検証する観点:
//   - 回復は最大 HP を超えない（上限クランプの不変条件）
//   - 消費アイテムは使用者自身を healAmount だけ回復する
//
// 方向選択の純粋ロジック（deltaToDirection / pickHealDirection）は Staff モジュールに
// 移したので TestStaff 側で検証している。
//
// 駒・状態の権威は World。駒 fixture は `World.Cmd` の spawn 列で組み、効果適用関数は
// `World.WorldQuery` / `World.Command` を通して読み書きする。

mod TestStaffCast {

    // ════════════════════════════════════════════════════════
    // テスト用 World フィクスチャ
    // ════════════════════════════════════════════════════════

    /// 味方 1 体分の spawn Cmd 列。`TestWorldFixtures.playerCmds` を土台に、現在 HP と
    /// 魔力込みの戦闘値（moveTiles=5 / 最大HP=10 固定）を上書きする。
    def playerCmdsMagic(id: Int32, pos: {x = Int32, y = Int32}, hp: Int32, magicAttack: Int32): List[World.Cmd] =
        let spec = {moveTiles = 5, hp = 10 | TestWorldFixtures.unitSpec(id, pos)};
        let res  = TestUnitFixtures.testResourceMagic(5, 10, 3, 1, magicAttack, 0, 3);
        let ref  = World.EntityRef.Player(id);
        List.append(TestWorldFixtures.playerCmds(spec),
            World.Cmd.SetHp(ref, hp)
                :: World.Cmd.SetBaseStats(ref, Combat.baseStatsFrom(res))
                :: World.Cmd.SetPlayerResource(id, res)
                :: Nil)

    /// World 内の Player(0) の Data を取り出す（効果適用関数に渡す caster 用）。
    def playerData(): PlayerDriver.Data \ World.WorldQuery =
        match PlayerDriver.get(0) {
            case Some(d) => d
            case None    => bug!("player 0 not found in test world")
        }

    /// テスト用の消費アイテム（回復量を指定）。
    def healItem(healAmount: Int32): Consumable.ConsumableResource =
        {name       = "きずぐすり",
         effect     = Consumable.ConsumableEffect.Heal,
         magnitude  = healAmount,
         duration   = 0,
         healAmount = healAmount,
         durability = 5,
         weight     = 0.5,
         sprite     = ({texture = "t", hframes = 1, vframes = 1, frame = 0,
                         offset = {x = 0.0, y = 0.0},
                         scale = {x = 1.0, y = 1.0}, flipForFacing = false}: SpriteRes.SpriteResource),
         description = "", effectRule = None}

    /// effectRule を差し込めるテスト用の杖（effect 種別は DSL 経路では使われないのでダミー）。
    def staffWithRule(ruleJson: Option[Util.Json.Json]): Staff.StaffResource =
        {name = "テスト杖", effect = Staff.StaffEffect.Bind, durability = 3, weight = 0.75,
         sprite = ({texture = "t", hframes = 1, vframes = 1, frame = 0,
                     offset = {x = 0.0, y = 0.0},
                     scale = {x = 1.0, y = 1.0}, flipForFacing = false}: SpriteRes.SpriteResource),
         description = "", effectRule = ruleJson}

    /// JSON(簡易合成形式) を EffectRule へ decode するフィクスチャ。decode 失敗は即 bug。
    /// （bug! は正格評価されるので getWithDefault ではなく match で None のときだけ発火させる）
    def ruleOf(json: String): EffectRule.EffectRule =
        match Util.Json.parse(json) |> Result.toOption |> Option.flatMap(EffectBridge.fromComposer) {
            case Some(r) => r
            case None    => bug!("rule decode failed: ${json}")
        }

    /// 杖 DSL 経路を BoardQuery / GameLogger をスタブして発火する。盤面は 13×13 壁なし固定
    /// （unitCmds で seed した駒を乗せて Board を組む）。施術者は id=0 固定。
    /// dir は knockback 用（他 op では未使用）。戻り値は最終 World。
    def fireStaffDsl(staff: Staff.StaffResource, rule: EffectRule.EffectRule,
                      hit: RayHit, dir: {x = Int32, y = Int32}, unitCmds: List[World.Cmd]): World =
        region rc {
            let w0 = TestWorldFixtures.worldOf(
                List.append(TestWorldFixtures.boardCmds({w = 13, h = 13}, None), unitCmds));
            let board = match World.boardOf(w0) {
                case Some(b) => b
                case None    => bug!("fireStaffDsl: board not seeded")
            };
            let (_, w) = TestUnitFixtures.withWorldAppliedSeeded(rc, w0, () ->
                TestUnitFixtures.withMockBoard(board, () ->
                    TestUnitFixtures.withMockGameLogger(() ->
                        StaffCast.applyStaffEffectDsl(0, staff, rule, hit, dir))));
            w
        }

    // ════════════════════════════════════════════════════════
    // 回復杖（ライブ）— 最大 HP を超えない
    // ════════════════════════════════════════════════════════

    /// HP 5 / 最大 10 の味方に「魔力 0 + 10 = 10」回復をかけると、5 + 10 = 15 ではなく
    /// 上限 10 で頭打ちになる（回復は最大 HP を超えない）。
    /// クランプ則の単一源泉 `Combat.heal`（純粋）を直接 pin する。
    @Test
    def testHealStaffClampsAtMaxHp(): Unit \ Assert =
        Assert.assertEq(expected = 10, (Combat.heal(5, 10, 10))#newHp)

    // ════════════════════════════════════════════════════════
    // 消費アイテム — 使用者自身を healAmount 回復
    // ════════════════════════════════════════════════════════

    /// HP 4 / 最大 10 の味方が回復量 3 の消費アイテムを使うと、HP が 7 になる
    /// （4 + 3 = 7、上限 10 には届かないのでそのまま）。
    @Test
    def testConsumableHealRestoresHp(): Unit \ Assert =
        region rc {
            let unitCmds = playerCmdsMagic(0, {x = 5, y = 5}, 4, 0);
            let (_, _, w) = TestUnitFixtures.withTracedWorld(rc, 0i64, unitCmds, () ->
                TestUnitFixtures.withMockGameLogger(() -> {
                    let user = playerData();
                    StaffCast.applyConsumableHeal(0, user, healItem(3))
                }));
            Assert.assertEq(expected = Some(7), World.hpOf(World.EntityRef.Player(0), w))
        }

    // ════════════════════════════════════════════════════════
    // DSL 経路（EffectRule → planActions → runPlan）が旧経路と同じ HP を生むか
    //   きずぐすりを「効果 JSON」として宣言し、World 書込 handler で発火しても
    //   applyConsumableHeal と同じ結果（HP 4 → 7）になることを確認する。
    // ════════════════════════════════════════════════════════

    /// PlanItem を World へ落とす handler 束。heal だけ実装し、他は恒等（このテストでは未使用）。
    /// heal は applyConsumableHeal と同じ「Combat.heal → PlayerDriver.setHp」を行う（ログは省略）。
    def dslWorldHandlers(): EffectRunner.PlanHandlers[Unit, {World.Command, World.WorldQuery}] = {
        heal       = (_u, id, _, amount) -> checked_ecast(healPlayerHp(id, amount)),
        fullHeal   = (u, _, _)          -> checked_ecast(u),
        damage     = (u, _, _, _)       -> checked_ecast(u),
        maxHpUp    = (u, _, _, _)       -> checked_ecast(u),
        status     = (u, _, _, _, _, _) -> checked_ecast(u),
        immobilize = (u, _, _, _)       -> checked_ecast(u),
        revive     = (u, _, _)          -> checked_ecast(u),
        custom     = (u, _, _, _)       -> checked_ecast(u),
        sfx        = (u, _)             -> checked_ecast(u),
        noOp       = (u, _)             -> checked_ecast(u)
    }

    /// `dslWorldHandlers` の heal 分岐本体: 現在 HP を World から読み、`Combat.heal` の結果を
    /// `PlayerDriver.setHp` で書き戻す（`StaffCast.applyConsumableHeal` と同じ式）。
    def healPlayerHp(id: Int32, amount: Int32): Unit \ {World.Command, World.WorldQuery} =
        PlayerDriver.get(id)
            |> Option.map(p -> {
                let cur = World.hpOf(World.EntityRef.Player(id), World.WorldQuery.get())
                              |> Option.getWithDefault(p#hp);
                let r = Combat.heal(cur, p#resource#hp, amount);
                PlayerDriver.setHp(id, r#newHp)
            })
            |> Option.getWithDefault(())

    /// きずぐすりを効果 JSON として宣言 → decode → plan → runPlan で World に発火 → HP 7。
    /// 旧経路 testConsumableHealRestoresHp と同じ結果になり、DSL 化が等価であることを示す。
    @Test
    def testConsumableHealViaDsl(): Unit \ Assert =
        region rc {
            let unitCmds = playerCmdsMagic(0, {x = 5, y = 5}, 4, 0);
            let json = "{\"when\":\"onUse\",\"do\":[{\"to\":{\"role\":\"self\"},\"op\":\"healFlat\",\"amount\":{\"flat\":3}}]}";
            let ctx = {selfId = 0, attackerId = 0, actorIsPlayer = true, rayUnits = (Nil: List[EffectRule.RayUnit]),
                       amount = {max = 10, dealt = 0, incoming = 0, magic = 0}};
            let items = Util.Json.parse(json)
                            |> Result.toOption
                            |> Option.flatMap(EffectRuleCodec.decodeRule)
                            |> Option.map(r -> EffectPlan.planActions(r, ctx))
                            |> Option.getWithDefault(Nil);
            let (_, w) = TestUnitFixtures.withWorldAppliedSeeded(rc, TestWorldFixtures.worldOf(unitCmds), () ->
                EffectRunner.runPlan(dslWorldHandlers(), items, ()));
            Assert.assertEq(expected = Some(7), World.hpOf(World.EntityRef.Player(0), w))
        }

    // ════════════════════════════════════════════════════════
    // 本番スイッチ後: applyConsumableSelfEffect が DSL 経路で旧挙動と一致する
    //   （applyConsumableSelfEffect は EffectBridge→planActions→runPlan→既存 primitive を通る）
    // ════════════════════════════════════════════════════════

    /// きずぐすり(Heal,3): DSL 経路の applyConsumableSelfEffect で HP 4→7。
    @Test
    def testSelfEffectHealViaDslPath(): Unit \ Assert =
        region rc {
            let unitCmds = playerCmdsMagic(0, {x = 5, y = 5}, 4, 0);
            let (_, w) = TestUnitFixtures.withWorldAppliedSeeded(rc, TestWorldFixtures.worldOf(unitCmds), () ->
                TestUnitFixtures.withMockGameLogger(() -> {
                    let user = playerData();
                    StaffCast.applyConsumableSelfEffect(0, user, healItem(3))
                }));
            Assert.assertEq(expected = Some(7), World.hpOf(World.EntityRef.Player(0), w))
        }

    /// ちから薬(AtkUp,4,3T): DSL 経路で AtkUp+4 が付与される（→ applySelfStatus）。
    @Test
    def testSelfEffectAtkUpViaDslPath(): Unit \ Assert =
        let item = Consumable.bottle(Consumable.ConsumableEffect.AtkUp, 4, 3, "ちから薬");
        // statuses は World 権威＝emit を World に積んで最終 World を読む。
        let w = region rc {
            let unitCmds = playerCmdsMagic(0, {x = 5, y = 5}, 10, 0);
            snd(TestUnitFixtures.withWorldAppliedSeeded(rc, TestWorldFixtures.worldOf(unitCmds), () ->
                TestUnitFixtures.withMockGameLogger(() -> {
                    let user = playerData();
                    StaffCast.applyConsumableSelfEffect(0, user, item)
                })))
        };
        let atk = StatusSystem.sumOf(StatusSystem.StatusEffect.AtkUp,
                                     World.statusEffectsOf(World.EntityRef.Player(0), w));
        Assert.assertEq(expected = 4, atk)

    /// 命の草(MaxHpUp,3): DSL 経路で HP と最大HP を両方 +3（4/10 → 7/13）。
    @Test
    def testSelfEffectMaxHpUpViaDslPath(): Unit \ Assert =
        let item = Consumable.bottle(Consumable.ConsumableEffect.MaxHpUp, 3, 0, "命の草");
        let hpMax = region rc {
            let unitCmds = playerCmdsMagic(0, {x = 5, y = 5}, 4, 0);
            let (_, w) = TestUnitFixtures.withWorldAppliedSeeded(rc, TestWorldFixtures.worldOf(unitCmds), () ->
                TestUnitFixtures.withMockGameLogger(() -> {
                    let user = playerData();
                    StaffCast.applyConsumableSelfEffect(0, user, item)
                }));
            World.dataFromWorld(0, w) |> Option.map(d -> (d#hp, d#resource#hp)) |> Option.getWithDefault((-1, -1))
        };
        Assert.assertEq(expected = (7, 13), hpMax)

    // ════════════════════════════════════════════════════════
    // 投擲の DSL 経路（applyConsumableEffectDsl）が当たった相手に効く（ally で player/enemy 出し分け）
    //   ここでは味方(ally=true)に当てる枝を確認。enemy 枝は同一ヘルパの else で対称。
    // ════════════════════════════════════════════════════════

    /// きずぐすりを味方#0 に投げて当てると HP 4→7（applyConsumableEffectToPlayer と同一）。
    @Test
    def testThrowHealAtAllyViaDsl(): Unit \ Assert =
        region rc {
            let unitCmds = playerCmdsMagic(0, {x = 5, y = 5}, 4, 0);
            let (_, w) = TestUnitFixtures.withWorldAppliedSeeded(rc, TestWorldFixtures.worldOf(unitCmds), () ->
                StaffCast.applyConsumableEffectDsl(healItem(3), 0, true));
            Assert.assertEq(expected = Some(7), World.hpOf(World.EntityRef.Player(0), w))
        }

    /// effectRule（IDE合成）が legacy effect を上書きしてゲームを駆動する。
    /// legacy magnitude=99 だが effectRule の amount=3 なので HP 4→7（10にならない＝effectRule優先）。
    @Test
    def testEffectRuleDrivesSelfHeal(): Unit \ Assert =
        region rc {
            let unitCmds = playerCmdsMagic(0, {x = 5, y = 5}, 4, 0);
            let ruleJson = Util.Json.parse("{\"when\":\"onUse\",\"to\":\"self\",\"op\":\"healFlat\",\"amount\":3,\"for\":\"instant\",\"forTurns\":0,\"sfx\":\"\",\"vfx\":\"\"}")
                            |> Result.toOption;
            let item = {effectRule = ruleJson | healItem(99)};
            let (_, w) = TestUnitFixtures.withWorldAppliedSeeded(rc, TestWorldFixtures.worldOf(unitCmds), () ->
                TestUnitFixtures.withMockGameLogger(() -> {
                    let user = playerData();
                    StaffCast.applyConsumableSelfEffect(0, user, item)
                }));
            Assert.assertEq(expected = Some(7), World.hpOf(World.EntityRef.Player(0), w))
        }

    /// ちから薬を味方#0 に投げて当てると AtkUp+4 が付与される（投擲で味方を強化できる）。
    @Test
    def testThrowAtkUpAtAllyViaDsl(): Unit \ Assert =
        let item = Consumable.bottle(Consumable.ConsumableEffect.AtkUp, 4, 3, "ちから薬");
        // statuses は World 権威＝emit を World に積んで最終 World を読む。
        let w = region rc {
            let unitCmds = playerCmdsMagic(0, {x = 5, y = 5}, 10, 0);
            snd(TestUnitFixtures.withWorldAppliedSeeded(rc, TestWorldFixtures.worldOf(unitCmds), () ->
                StaffCast.applyConsumableEffectDsl(item, 0, true)))
        };
        let atk = StatusSystem.sumOf(StatusSystem.StatusEffect.AtkUp,
                                     World.statusEffectsOf(World.EntityRef.Player(0), w));
        Assert.assertEq(expected = 4, atk)

    /// 杖の effectRule(onUse, immobilize) が当たった相手を完全停止にする。
    /// legacy enum 分岐ではなく DSL 経路（planActions → runPlan → immobilizeUnit）が bind を駆動する。
    @Test
    def testStaffEffectRuleImmobilizesTarget(): Unit \ Assert =
        let staff = staffWithRule(None);
        let rule = ruleOf("{\"when\":\"onUse\",\"to\":\"target\",\"op\":\"immobilize\",\"amount\":0,\"for\":\"untilHit\",\"forTurns\":0,\"sfx\":\"\",\"vfx\":\"\"}");
        let hit = RayHit.HitPlayer(0, {x = 5, y = 5});
        let unitCmds = playerCmdsMagic(0, {x = 5, y = 5}, 10, 0);
        let w = fireStaffDsl(staff, rule, hit, {x = 0, y = 0}, unitCmds);
        // statuses は World 権威＝最終 World の statusEffects を読む。
        let immob = StatusSystem.isImmobilized(World.statusEffectsOf(World.EntityRef.Player(0), w));
        Assert.assertEq(expected = true, immob)

    /// bind の停止ターン数が effectRule の forTurns で駆動される（5 固定でなく編集が効く）。
    /// forTurns=3 → 付与された Immobilized の remaining が 3。
    @Test
    def testStaffBindTurnsDrivenByEffectRule(): Unit \ Assert =
        let staff = staffWithRule(None);
        let rule = ruleOf("{\"when\":\"onUse\",\"to\":\"target\",\"op\":\"immobilize\",\"amount\":0,\"for\":\"turns\",\"forTurns\":3,\"sfx\":\"\",\"vfx\":\"\"}");
        let hit = RayHit.HitPlayer(0, {x = 5, y = 5});
        let unitCmds = playerCmdsMagic(0, {x = 5, y = 5}, 10, 0);
        let w = fireStaffDsl(staff, rule, hit, {x = 0, y = 0}, unitCmds);
        // statuses は World 権威＝最終 World の statusEffects を読む。
        let rem = World.statusEffectsOf(World.EntityRef.Player(0), w)
                   |> List.filter(s -> s#effect == StatusSystem.StatusEffect.Immobilized)
                   |> List.map(s -> s#remaining)
                   |> List.head
                   |> Option.getWithDefault(-1);
        Assert.assertEq(expected = 3, rem)

    /// custom op: 杖の effectRule(onUse, swapPos) が施術者(0)と当たった相手(1)の gridPos を入れ替える。
    /// custom ハンドラが op 文字列で applySwapWithPlayer へ振り分け、位置を World から逆引きすることを確認。
    @Test
    def testStaffEffectRuleSwapsPositions(): Unit \ Assert =
        let staff = staffWithRule(None);
        let rule = ruleOf("{\"when\":\"onUse\",\"to\":\"target\",\"op\":\"swapPos\",\"amount\":0,\"for\":\"instant\",\"forTurns\":0,\"sfx\":\"\",\"vfx\":\"\"}");
        let hit = RayHit.HitPlayer(1, {x = 5, y = 3});
        let unitCmds = List.append(playerCmdsMagic(0, {x = 5, y = 5}, 10, 0), playerCmdsMagic(1, {x = 5, y = 3}, 10, 0));
        let w = fireStaffDsl(staff, rule, hit, {x = 0, y = -1}, unitCmds);
        let p0 = TestWorldFixtures.posT(World.EntityRef.Player(0), w) |> Option.getWithDefault((-1, -1));
        let p1 = TestWorldFixtures.posT(World.EntityRef.Player(1), w) |> Option.getWithDefault((-1, -1));
        Assert.assertEq(expected = ((5, 3), (5, 5)), (p0, p1))
        // knockback / warpToStairs は customStaffEffect の同じ match で legacy
        // applyBlowback*/applyStopgap* へ委譲する（full 検証はここでは省略。
        // dispatch 機構自体は上の swapPos で実証済み）。

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
            cellTuple(StaffRules.warpCellFor(Some({x = 5, y = 5}), board)))

    /// 階段が埋まっていれば、隣接する歩ける空きマス（最初に試す上 = y-1）へ。
    @Test
    def testWarpCellStairsOccupied(): Unit \ Assert =
        let board = mkBoard(Set#{}, (Piece.Enemy(9), {x = 5, y = 5}) :: Nil);
        Assert.assertEq(
            expected = Some((5, 4)),
            cellTuple(StaffRules.warpCellFor(Some({x = 5, y = 5}), board)))

    /// 階段が埋まり隣接 4 マスがすべて壁なら、ワープ先なし（None → 停止だけ）。
    @Test
    def testWarpCellNoFreeNeighbor(): Unit \ Assert =
        let walls = Set#{(5, 4), (5, 6), (4, 5), (6, 5)};
        let board = mkBoard(walls, (Piece.Enemy(9), {x = 5, y = 5}) :: Nil);
        Assert.assertEq(
            expected = None,
            cellTuple(StaffRules.warpCellFor(Some({x = 5, y = 5}), board)))

    /// 階段が未配置（None）ならワープ先なし。
    @Test
    def testWarpCellNoStairs(): Unit \ Assert =
        let board = mkBoard(Set#{}, Nil);
        Assert.assertEq(expected = None, cellTuple(StaffRules.warpCellFor(None, board)))

    // ════════════════════════════════════════════════════════
    // 敵クレリックが詠唱する杖（enemyStaffFor・純粋）
    // ════════════════════════════════════════════════════════

    /// クレリック_T2 はかなしばり、T3 は一時しのぎ、それ以外の職は詠唱しない。
    @Test
    def testEnemyStaffForByClass(): Unit \ Assert =
        Assert.assertEq(
            expected = (Some(Staff.StaffEffect.Bind), Some(Staff.StaffEffect.Stopgap), None),
            (StaffCast.enemyStaffFor("クレリック_T2"),
             StaffCast.enemyStaffFor("クレリック_T3"),
             StaffCast.enemyStaffFor("ファイター_T1")))
}
