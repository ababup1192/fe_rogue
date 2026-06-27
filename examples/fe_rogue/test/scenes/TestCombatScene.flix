// CombatScene の攻撃解決ロジックの検証（移設前はテスト0件だった領域）。
//
// 検証する観点:
//   - attackLungeAnimation: 中点で attack:hit メソッドを 1 つ発火する（純粋・モック不要）
//   - anyAttacking: 攻撃中（attackTargetId=Some）の味方が居れば true
//   - applyAttackHit 命中: 敵 HP が攻撃力ぶん減り、攻撃側に経験値が入る
//   - applyAttackHit 回避: 敵 HP は不変で、経験値も入らない
//   - process: 自ノード宛 signal だけ drain する（他ユニットの signal を食わない）/
//     signal handler が self を更新したら最新ノードを返す
//
// 命中/回避は乱数モック（withMockRandom → rollPercent()=50）で決定的にする。
// 命中率 = 武器命中 + 技×2 + 幸運÷2 − (敵速さ×2 + 敵幸運)。
// testResource(技2/幸運2) vs testEnemyResource(速さ3/幸運2)・中立相性なので
//   命中率 = 武器命中 − 3。roll=50 なので「命中率 > 50（= 武器命中 > 53）で命中」。

mod TestCombatScene {

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// 攻撃対象 enemy=1 を抱えた選択中味方。`weaponHit` で命中率を作り分ける。
    /// 攻撃力は素 3 + 武器 2 = 5、敵防御 1 なので命中時ダメージは 4。
    def player(weaponHit: Int32): PlayerScene.Data = {
        id                = 0,
        classId           = "test_player",
        gridPos           = {x = 2, y = 2},
        moveTiles         = 4,
        hp                = 10,
        waited            = false,
        attackTargetId    = Some(1),
        resource          = TestUnitFixtures.testResource(4, 10),
        weapons           = ({hit = weaponHit | TestUnitFixtures.testWeapon()}: UnitCatalog.WeaponResource) :: Nil,
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
    }

    /// 隣接 (3,2) の生存中の敵。HP 10・剣持ち（相性は中立）。
    def enemy(): EnemyScene.Data = {
        id             = 1,
        resourceId     = "test_enemy",
        gridPos        = {x = 3, y = 2},
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 3,
        hp             = 10,
        isDying        = false,
        attackTargetId = None,
        resource       = TestUnitFixtures.testEnemyResource(3, 10),
        weapon         = Some(TestUnitFixtures.testWeapon()),
        acted          = false,
        prevPos        = None,
        statuses       = Nil,
        ring           = None,
        followUpUsed   = false,
        bottleUsed     = false
    }

    /// World 配下に Player(0) と Enemy(1) を直接挿した最小シーン。
    /// HPBar / DamagePopupsRoot は持たないが、`UnitHPBarScene.update` /
    /// `DamagePopupScene.emit` は対象が無ければ何もしないので結果に影響しない。
    def battleScene(weaponHit: Int32): Scene[NodeTag] =
        let world = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        let pMarker = Marker2D.make(Vec2.zero());
        let eMarker = Marker2D.make(Vec2.zero());
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(pMarker, NodeTag.Player(player(weaponHit))))
            |> Scene.addChildAt(MapScene.worldPath(), EnemyScene.enemyName(1),
                EngineNode.Marker2DWithState(eMarker, NodeTag.Enemy(enemy())))

    /// applyAttackHit を 5 つの副作用モックで包んで実行する。
    def runAttack(scene: Scene[NodeTag]): Scene[NodeTag] =
        withNoopThiefDrop(() ->
        TestUnitFixtures.withMockRandom(() ->
        TestUnitFixtures.withMockGame(() ->
        TestUnitFixtures.withMockAudio(() ->
        TestUnitFixtures.withMockGameLogger(() ->
        TestUnitFixtures.withNoopAnim(() ->
        TestUnitFixtures.withNoopTween(() ->
            CombatScene.applyAttackHit(0, scene))))))))

    // ════════════════════════════════════════════════════════
    // attackLungeAnimation — 中点で attack:hit を 1 つ発火（純粋）
    // ════════════════════════════════════════════════════════

    /// 体当たりアニメは「攻撃が当たる中点」で attack:hit メソッドをちょうど 1 つ持つ。
    /// （このメソッドを engine が拾って onAttackHit → ダメージ適用が走る）
    @Test
    def testLungeFiresOneHitMethod(): Unit \ Assert =
        let anim = CombatScene.attackLungeAnimation(
                       PlayerScene.playerPath(0), {x = 2, y = 2}, {x = 3, y = 2});
        let firstName = List.head(anim#methods)
            |> Option.map(m -> m#name)
            |> Option.getWithDefault("");
        Assert.assertEq(
            expected = (1, AnimEvent.tagToString(AnimEvent.Tag.AttackHit)),
            (List.length(anim#methods), firstName))

    // ════════════════════════════════════════════════════════
    // attackForecast — 命中率・ダメージ・経験値の純粋算出（モック不要）
    // ════════════════════════════════════════════════════════

    /// 武器命中 80・素攻撃 5（素3+武器2）・敵防御 1 のとき:
    ///   命中率 = 80 − 3 = 77 / 与ダメージ = 5 − 1 = 4 / 命中後 HP = 10 − 4 = 6 /
    ///   撃破せず（6 > 0）/ 命中で経験値あり。
    /// 乱数も Scene も使わないので副作用モックなしで検証できる。
    @Test
    def testAttackForecastComputesHitDamageExp(): Unit \ Assert =
        let weapon = ({hit = 80 | TestUnitFixtures.testWeapon()}: UnitCatalog.WeaponResource);
        let plan = CombatScene.attackForecast(player(80), weapon, enemy());
        Assert.assertEq(
            expected = (77, 4, 6, false, true),
            (plan#hitRate, plan#dmg, plan#newHp, plan#killed, plan#exp > 0))

    // ════════════════════════════════════════════════════════
    // anyAttacking — 攻撃モーション中の味方の有無
    // ════════════════════════════════════════════════════════

    /// attackTargetId=Some を持つ味方が居れば true、攻撃対象をクリアすれば false。
    @Test
    def testAnyAttackingReflectsAttackTarget(): Unit \ Assert =
        let attacking = battleScene(80);
        let idle      = CombatScene.clearAttackTargetId(0, attacking);
        Assert.assertEq(
            expected = (true, false),
            (PlayerScene.anyAttacking(attacking),
             PlayerScene.anyAttacking(idle)))

    // ════════════════════════════════════════════════════════
    // applyAttackHit — 命中で HP 減 + 経験値、回避で不変
    // ════════════════════════════════════════════════════════

    /// 命中（武器命中 80 → 命中率 77 > 50）: 敵 HP は 10 − 4 = 6 になり、攻撃側に経験値が入る。
    @Test
    def testAttackHitDamagesEnemyAndGrantsExp(): Unit \ Assert =
        let after = runAttack(battleScene(80));
        Assert.assertEq(
            expected = (Some(6), Some(true)),
            (EnemyScene.get(1, after)  |> Option.map(e -> e#hp),
             PlayerScene.get(0, after) |> Option.map(p -> p#exp > 0)))

    /// 回避（武器命中 40 → 命中率 37 ≤ 50）: 敵 HP は 10 のまま、経験値も入らない。
    @Test
    def testAttackMissLeavesEnemyAndExpUnchanged(): Unit \ Assert =
        let after = runAttack(battleScene(40));
        Assert.assertEq(
            expected = (Some(10), Some(0)),
            (EnemyScene.get(1, after)  |> Option.map(e -> e#hp),
             PlayerScene.get(0, after) |> Option.map(p -> p#exp)))

    // ════════════════════════════════════════════════════════
    // applyEnemyAttackHit — 敵→味方の鏡像数値（resolveStrike 経由の回帰固定）
    // ════════════════════════════════════════════════════════

    /// applyEnemyAttackHit を副作用モックで包んで実行する（アニメは介在しない）。
    def runEnemyAttack(scene: Scene[NodeTag]): (Scene[NodeTag], List[Int32]) =
        TestUnitFixtures.dischargeWorldCommand(() ->
        TestUnitFixtures.withMockRandom(() ->
        TestUnitFixtures.withMockGame(() ->
        TestUnitFixtures.withMockAudio(() ->
        TestUnitFixtures.withMockGameLogger(() ->
        TestUnitFixtures.withNoopTween(() ->
            CombatScene.applyEnemyAttackHit(1, scene)))))))

    /// 敵→味方の鏡像数値: 敵(素3+武器2) vs 味方防御 1 → 4 ダメージ、
    /// 命中率 = 80 + 技2×2 + 幸運2÷2 − (速さ3×2 + 幸運2) = 77 > 50 で命中。
    /// 味方 HP は 10 − 4 = 6、死亡には至らないので killed リストは空。
    /// 味方→敵（testAttackHitDamagesEnemyAndGrantsExp）と同じ数値になることが
    /// 攻守が同一の resolveStrike（= Combat.estimate）を通る回帰固定になる。
    @Test
    def testEnemyAttackHitDamagesPlayer(): Unit \ Assert =
        let scene = battleScene(80)
            |> EnemyScene.mapEnemy(1, d -> {attackTargetId = Some(0) | d});
        let (after, killed) = runEnemyAttack(scene);
        Assert.assertEq(
            expected = (Some(6), true),
            (PlayerScene.get(0, after) |> Option.map(p -> p#hp),
             List.isEmpty(killed)))

    // ════════════════════════════════════════════════════════
    // 死亡の非対称 — 敵は death_blink でノード残存（味方の即削除は TestPlayerScene が担保）
    // ════════════════════════════════════════════════════════

    /// 撃破された敵は scene から即削除されず、`isDying = true` で death_blink 開始。
    /// （ノード削除は death_blink finished の completeDeath まで遅延される）
    @Test
    def testKillStartsEnemyDeathBlinkAndKeepsNode(): Unit \ Assert =
        let scene = battleScene(80)
            |> EnemyScene.mapEnemy(1, d -> {hp = 4 | d});
        let after = runAttack(scene);
        // None なら「ノードが残っていない」、Some(false) なら「死亡演出が始まっていない」。
        Assert.assertEq(
            expected = Some(true),
            EnemyScene.get(1, after) |> Option.map(e -> e#isDying))

    // ════════════════════════════════════════════════════════
    // onLungeDone phase マトリクス — Player × PlayerAttackHold × Kill
    // ════════════════════════════════════════════════════════

    /// 撃破直後（対象が isDying）の味方 lunge 完了は、PlayerAttackHold を維持したまま
    /// Pacing.hold を積む（撃破演出のホールド。ターンはまだ進めない）。
    @Test
    def testLungeDoneKillHoldsPacing(): Unit \ Assert =
        region rc {
            let scene = battleScene(80)
                |> EnemyScene.mapEnemy(1, d -> {isDying = true | d});
            let result =
                TestUnitFixtures.withWorldCommand(rc, () ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withMockEnemyTurnQueue(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withMockRandom(() ->
                    run {
                        TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
                        let _ = CombatScene.onLungeDone(Faction.Player, 0, scene);
                        (TurnPhase.State.get(), Pacing.State.isHolding())
                    } with Tween.withScheduler(rc)
                      with TurnPhase.withState(rc)
                      with SelectedPlayer.withState(rc)
                      with Pacing.withState(rc))))));
            Assert.assertEq(
                expected = (TurnPhase.Phase.PlayerAttackHold, true), result)
        }

    // ════════════════════════════════════════════════════════
    // process — シグナル配信（owner 完全一致 / 最新ノード返却）
    // ════════════════════════════════════════════════════════

    /// GameOverRequest の no-op スタブ（飛んだら scene をそのまま返す）。
    def withNoopGameOver(thunk: Unit -> a \ ef):
            a \ (ef - CustomEffects.GameOverRequest) =
        run { thunk() } with handler CustomEffects.GameOverRequest {
            def markDeaths(_positions, k) = k()
            def request(scene, k) = k(scene)
            def restartBeginning(scene, k) = k(scene)
            def restartFloor(scene, k) = k(scene)
            def reviveInPlace(scene, k) = k(scene)
        }

    /// ThiefDropRequest の no-op スタブ（盗人ドロップが飛んだら scene をそのまま返す）。
    def withNoopThiefDrop(thunk: Unit -> a \ ef):
            a \ (ef - CustomEffects.ThiefDropRequest) =
        run { thunk() } with handler CustomEffects.ThiefDropRequest {
            def drop(_cell, scene, k) = k(scene)
        }

    /// `path` のノードに対して CombatScene.process を全副作用モックで 1 回回す。
    /// AnimationPlayer は `ownerPath` 宛にだけ attack_lunge finished を返す
    /// （他 owner 宛の drain は空 = 実物 Scheduler と同じ per-owner pull）。
    /// TurnPhase は EnemyTurn（反撃完了 = attackTargetId クリアの最小観測経路）に固定。
    def processOnce(ownerPath: NodePath, path: NodePath,
                     scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        let node = match Scene.getEngineNode(path, scene) {
            case Some(n) => n
            case None    => bug!("processOnce: node missing at path")
        };
        let lungeDone = ({
            methods  = Nil,
            finished = ({owner = ownerPath,
                         name = AnimEvent.tagToString(AnimEvent.Tag.AttackLunge)}: AnimationPlayer.Event) :: Nil
        }: AnimationPlayer.EventBundle);
        region rc {
            TestUnitFixtures.withWorldCommand(rc, () ->
            TestUnitFixtures.withMockRandom(() ->
            TestUnitFixtures.withMockGame(() ->
            TestUnitFixtures.withMockAudio(() ->
            TestUnitFixtures.withMockGameLogger(() ->
            TestUnitFixtures.withMockEnemyTurnQueue(() ->
            TestUnitFixtures.withSignalsFor(ownerPath, lungeDone, () ->
            withNoopThiefDrop(() ->
            withNoopGameOver(() ->
                run {
                    TurnPhase.State.put(TurnPhase.Phase.EnemyTurn);
                    CombatScene.process(Duration.seconds(0.016), node, path, scene)
                } with Tween.withScheduler(rc)
                  with TurnPhase.withState(rc)
                  with SelectedPlayer.withState(rc)
                  with Pacing.withState(rc))))))))))         }

    /// 他ユニット宛の signal は食わない: Player(0) 宛の attack_lunge finished があるとき、
    /// Enemy(1) ノードの process では Player(0) の attackTargetId は残り（敵の drain は空）、
    /// Player(0) ノードの process で初めてクリアされる。
    @Test
    def testProcessDrainsOnlyOwnSignals(): Unit \ Assert =
        let scene = battleScene(80);
        let owner = PlayerScene.playerPath(0);
        let (_, afterEnemy)  = processOnce(owner, EnemyScene.enemyPath(1), scene);
        let (_, afterPlayer) = processOnce(owner, owner, afterEnemy);
        let targetOf = sc -> PlayerScene.get(0, sc) |> Option.flatMap(d -> d#attackTargetId);
        Assert.assertEq(
            expected = (Some(1), (None: Option[Int32])),
            (targetOf(afterEnemy), targetOf(afterPlayer)))

    /// Player ノードの NodeTag から attackTargetId を取り出す（Player ノード以外は None）。
    def nodeAttackTarget(node: EngineNode[NodeTag]): Option[Option[Int32]] =
        match node {
            case EngineNode.Marker2DWithState(_, NodeTag.Player(d)) => Some(d#attackTargetId)
            case _                                                   => None
        }

    /// signal handler が scene 側の self ノードを更新した場合、process は引数の古い node
    /// ではなく最新ノードを返す（フレーム末尾の書き戻しで更新が打ち消されないように）。
    /// None なら「Player ノードが返っていない」、Some(Some(1)) なら「古い node のまま」。
    @Test
    def testProcessReturnsRefreshedNode(): Unit \ Assert =
        let owner = PlayerScene.playerPath(0);
        let (node, _) = processOnce(owner, owner, battleScene(80));
        Assert.assertEq(
            expected = Some((None: Option[Int32])),
            nodeAttackTarget(node))

    // ════════════════════════════════════════════════════════
    // hitSoundName: 命中時の SE 出し分け（防御 / 必殺 / 魔法 / 物理）
    //   優先順位は guard（ダメージ0）> critical（必殺）> magic（魔法）> damage。
    // ════════════════════════════════════════════════════════

    /// ダメージ 0（防御で防がれた）は、物理でも魔法でも "guard"。
    /// 0 判定は必殺・魔法より優先する（必殺で 0 ダメージでも防御音を鳴らす）。
    @Test
    def testHitSoundGuardWhenZeroDamage(): Unit \ Assert =
        Assert.assertEq(
            expected = ("guard", "guard"),
            (CombatScene.hitSoundName(0, false, WeaponCatalog.WeaponType.Sword),
             CombatScene.hitSoundName(0, true, WeaponCatalog.WeaponType.Magic)))

    /// 必殺（クリティカル）が発動し、ダメージ 1 以上なら "critical"。
    @Test
    def testHitSoundCriticalWhenCrit(): Unit \ Assert =
        Assert.assertEq(
            expected = "critical",
            CombatScene.hitSoundName(15, true, WeaponCatalog.WeaponType.Sword))

    /// 魔法武器で必殺なしダメージ 1 以上なら "magic"。
    @Test
    def testHitSoundMagicWhenMagicWeapon(): Unit \ Assert =
        Assert.assertEq(
            expected = "magic",
            CombatScene.hitSoundName(5, false, WeaponCatalog.WeaponType.Magic))

    /// 物理武器で必殺なしダメージ 1 以上なら通常の "damage"。
    @Test
    def testHitSoundDamageWhenPhysical(): Unit \ Assert =
        Assert.assertEq(
            expected = "damage",
            CombatScene.hitSoundName(5, false, WeaponCatalog.WeaponType.Lance))
}
