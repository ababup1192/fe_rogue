// PlayerCombatScene の攻撃解決ロジックの検証（移設前はテスト0件だった領域）。
//
// 検証する観点:
//   - attackLungeAnimation: 中点で attack:hit メソッドを 1 つ発火する（純粋・モック不要）
//   - anyAttacking: 攻撃中（attackTargetId=Some）の味方が居れば true
//   - applyAttackHit 命中: 敵 HP が攻撃力ぶん減り、攻撃側に経験値が入る
//   - applyAttackHit 回避: 敵 HP は不変で、経験値も入らない
//
// 命中/回避は乱数モック（withMockRandom → rollPercent()=50）で決定的にする。
// 命中率 = 武器命中 + 技×2 + 幸運÷2 − (敵速さ×2 + 敵幸運)。
// testResource(技2/幸運2) vs testEnemyResource(速さ3/幸運2)・中立相性なので
//   命中率 = 武器命中 − 3。roll=50 なので「命中率 > 50（= 武器命中 > 53）で命中」。

mod TestPlayerCombat {

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// 攻撃対象 enemy=1 を抱えた選択中味方。`weaponHit` で命中率を作り分ける。
    /// 攻撃力は素 3 + 武器 2 = 5、敵防御 1 なので命中時ダメージは 4。
    def player(weaponHit: Int32): PlayerScene.Data = {
        id                = 0,
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
        pendingLevelUp    = None
    }

    /// 隣接 (3,2) の生存中の敵。HP 10・剣持ち（相性は中立）。
    def enemy(): EnemyScene.Data = {
        id             = 1,
        gridPos        = {x = 3, y = 2},
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 3,
        hp             = 10,
        isDying        = false,
        attackTargetId = None,
        resource       = TestUnitFixtures.testEnemyResource(3, 10),
        weapon         = Some(TestUnitFixtures.testWeapon()),
        acted          = false
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
        TestUnitFixtures.withMockRandom(() ->
        TestUnitFixtures.withMockGame(() ->
        TestUnitFixtures.withMockAudio(() ->
        TestUnitFixtures.withMockGameLogger(() ->
        TestUnitFixtures.withNoopAnim(() ->
            PlayerCombatScene.applyAttackHit(0, scene))))))

    // ════════════════════════════════════════════════════════
    // attackLungeAnimation — 中点で attack:hit を 1 つ発火（純粋）
    // ════════════════════════════════════════════════════════

    /// 体当たりアニメは「攻撃が当たる中点」で attack:hit メソッドをちょうど 1 つ持つ。
    /// （このメソッドを engine が拾って onAttackHit → ダメージ適用が走る）
    @Test
    def testLungeFiresOneHitMethod(): Unit \ Assert =
        let anim = PlayerCombatScene.attackLungeAnimation(
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
        let plan = PlayerCombatScene.attackForecast(player(80), weapon, enemy());
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
        let idle      = PlayerCombatScene.clearAttackTargetId(0, attacking);
        Assert.assertEq(
            expected = (true, false),
            (PlayerCombatScene.anyAttacking(attacking),
             PlayerCombatScene.anyAttacking(idle)))

    // ════════════════════════════════════════════════════════
    // applyAttackHit — 命中で HP 減 + 経験値、回避で不変
    // ════════════════════════════════════════════════════════

    /// 命中（武器命中 80 → 命中率 77 > 50）: 敵 HP は 10 − 4 = 6 になり、攻撃側に経験値が入る。
    @Test
    def testAttackHitDamagesEnemyAndGrantsExp(): Unit \ Assert =
        let after = runAttack(battleScene(80));
        match (EnemyScene.get(1, after), PlayerScene.get(0, after)) {
            case (Some(e), Some(p)) =>
                Assert.assertEq(expected = (6, true), (e#hp, p#exp > 0))
            case _ => bug!("player/enemy missing after attack")
        }

    /// 回避（武器命中 40 → 命中率 37 ≤ 50）: 敵 HP は 10 のまま、経験値も入らない。
    @Test
    def testAttackMissLeavesEnemyAndExpUnchanged(): Unit \ Assert =
        let after = runAttack(battleScene(40));
        match (EnemyScene.get(1, after), PlayerScene.get(0, after)) {
            case (Some(e), Some(p)) =>
                Assert.assertEq(expected = (10, 0), (e#hp, p#exp))
            case _ => bug!("player/enemy missing after attack")
        }
}
