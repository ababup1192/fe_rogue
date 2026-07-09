// CombatDriver の攻撃解決ロジックの検証（移設前はテスト0件だった領域）。
//
// 検証する観点:
//   - lungeSpec: 中点 hitAt が全長 total のちょうど半分（片道ぶん）で、往復座標は
//     origin/target セル中心（純粋・モック不要）
//   - anyAttacking: 攻撃中（attackTargetId=Some）の味方が居れば true
//   - applyAttackHit 命中: 敵 HP が攻撃力ぶん減り、攻撃側に経験値が入る
//   - applyAttackHit 回避: 敵 HP は不変で、経験値も入らない
//   - stepEntities: 自 entity 宛 signal だけ拾う（他ユニットの signal を食わない）
//
// 命中/回避は乱数モック（withMockRandom → rollPercent()=50）で決定的にする。
// 命中率 = 武器命中 + 技×2 + 幸運÷2 − (敵速さ×2 + 敵幸運)。
// testResource(技2/幸運2) vs testEnemyResource(速さ3/幸運2)・中立相性なので
//   命中率 = 武器命中 − 3。roll=50 なので「命中率 > 50（= 武器命中 > 53）で命中」。

mod TestCombatDriver {

    // ════════════════════════════════════════════════════════
    // フィクスチャ（純粋値・attackForecast の入力専用）
    // ════════════════════════════════════════════════════════

    /// 攻撃対象 enemy=1 を抱えた選択中味方。`weaponHit` で命中率を作り分ける。
    /// 攻撃力は素 3 + 武器 2 = 5、敵防御 1 なので命中時ダメージは 4。
    /// attackForecast は純粋関数（World 不使用）なので、この Data 直書きのままでよい。
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
        facing            = Dir4.Down,
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

    // ════════════════════════════════════════════════════════
    // フィクスチャ（World.Cmd 直組み・副作用テスト用）
    // ════════════════════════════════════════════════════════

    /// 味方 0（武器命中 weaponHit）と隣接する敵 1（HP10・剣・moveTiles3）を 13×13 の壁なし盤面へ
    /// spawn し、味方の攻撃対象を敵 1 に設定した Cmd 列。旧 `battleScene(weaponHit)` と同じ駒構成
    /// （値は player()/enemy() と揃えてある）。
    def battleCmds(weaponHit: Int32): List[World.Cmd] =
        let weapon = ({hit = weaponHit | TestUnitFixtures.testWeapon()}: UnitCatalog.WeaponResource);
        let pRef   = World.EntityRef.Player(0);
        List.flatten(
            TestWorldFixtures.boardCmds({w = 13, h = 13}, None)
                :: TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, {x = 2, y = 2}))
                :: TestWorldFixtures.enemyCmds({moveTiles = 3 | TestWorldFixtures.unitSpec(1, {x = 3, y = 2})})
                :: (World.Cmd.SetWeapons(pRef, weapon :: Nil)
                    :: World.Cmd.SetWeaponView(pRef, Combat.weaponView(Some(weapon), true))
                    :: World.Cmd.SetAttackTarget(pRef, 1)
                    :: Nil)
                :: Nil)

    /// `battleCmds` が組む World と同じ駒構成の Board mock（BoardQuery 用）。
    /// 地形は `battleCmds` の盤面と同一 13×13。
    def battleBoard(cmds: List[World.Cmd]): Board =
        let w = TestWorldFixtures.worldOf(cmds);
        BoardSnapshot.fromParts(TestWorldFixtures.floorSnapshot({w = 13, h = 13}),
            TestUnitFixtures.worldPlayers(w), TestUnitFixtures.worldEnemies(w))

    /// applyAttackHit を副作用モックで包んで実行する。
    /// ONE-Ref の withTracedWorld（Command+WorldQuery+RngDraw を同一 World に結線＝
    /// read-after-write）で駆動し、hp/exp の検証は **World store**（ECS 権威）で行う。
    def runAttack(cmds: List[World.Cmd]): World =
        region rc {
            let (_out, _keys, w) = TestUnitFixtures.withTracedWorld(rc, 0i64, cmds, () ->
                TestUnitFixtures.withMockBoard(battleBoard(cmds), () ->
                TestUnitFixtures.withNoopThiefDrop(() ->
                TestUnitFixtures.withMockRandom(() ->
                TestUnitFixtures.withMockGame(() ->
                TestUnitFixtures.withMockAudio(() ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withNoopTween(() ->
                    CombatDriver.applyAttackHit(0))))))))));
            w
        }

    // ════════════════════════════════════════════════════════
    // lungeSpec — 中点 hitAt = 全長の半分・往復座標はセル中心（純粋）
    // ════════════════════════════════════════════════════════

    /// lunge の中点（AttackHit が発火する hitAt）は全長 total のちょうど半分＝片道ぶん。
    /// origin/target はセル中心 pixel（往復座標列の端点）。
    @Test
    def testLungeSpecHitAtIsHalfOfTotal(): Unit \ Assert =
        let spec = CombatDriver.lungeSpec({x = 2, y = 2}, {x = 3, y = 2});
        Assert.assertEq(
            expected = (spec#total / 2.0, MapSnapshot.cellCenter({x = 2, y = 2})#x,
                        MapSnapshot.cellCenter({x = 3, y = 2})#x),
            (spec#hitAt, spec#origin#x, spec#target#x))

    /// lunge の描画位置導出: t=0 は origin、中点（elapsed=hitAt）は target、終端は origin。
    /// 旧 keyframe（0 → 0.5 → 1.0 の 3 点線形補間）と同じ往復座標列になることの pin。
    @Test
    def testLungeRenderPosRoundTrip(): Unit \ Assert =
        let spec = CombatDriver.lungeSpec({x = 2, y = 2}, {x = 3, y = 2});
        let at = e -> World.lungeRenderPos({origin = spec#origin, target = spec#target,
                                            elapsed = e, hitAt = spec#hitAt,
                                            total = spec#total, hitFired = false});
        Assert.assertEq(
            expected = (spec#origin#x, spec#target#x, spec#origin#x),
            (at(0.0)#x, at(spec#hitAt)#x, at(spec#total)#x))

    // ════════════════════════════════════════════════════════
    // attackForecast — 命中率・ダメージ・経験値の純粋算出（モック不要）
    // ════════════════════════════════════════════════════════

    /// 武器命中 80・素攻撃 5（素3+武器2）・敵防御 1 のとき:
    ///   命中率 = 80 − 3 = 77 / 与ダメージ = 5 − 1 = 4 / 命中後 HP = 10 − 4 = 6 /
    ///   撃破せず（6 > 0）/ 命中で経験値あり。
    /// 乱数も World も使わないので副作用モックなしで検証できる。
    @Test
    def testAttackForecastComputesHitDamageExp(): Unit \ Assert =
        let weapon = ({hit = 80 | TestUnitFixtures.testWeapon()}: UnitCatalog.WeaponResource);
        let plan = CombatDriver.attackForecast(player(80), weapon, enemy());
        Assert.assertEq(
            expected = (77, 4, 6, false, true),
            (plan#hitRate, plan#dmg, plan#newHp, plan#killed, plan#exp > 0))

    // ════════════════════════════════════════════════════════
    // anyAttacking — 攻撃モーション中の味方の有無
    // ════════════════════════════════════════════════════════

    /// attackTargetId=Some を持つ味方が居れば true、攻撃対象をクリアすれば false。
    @Test
    def testAnyAttackingReflectsAttackTarget(): Unit \ Assert =
        region rc {
            let cmds = battleCmds(80);
            let w0 = TestWorldFixtures.worldOf(cmds);
            let attacking = TestUnitFixtures.withWorldQuery(w0, () -> PlayerScene.anyAttacking());
            let (_, w1) = TestUnitFixtures.withWorldAppliedSeeded(rc, w0, () -> CombatDriver.clearAttackTargetId(0));
            let idle = TestUnitFixtures.withWorldQuery(w1, () -> PlayerScene.anyAttacking());
            Assert.assertEq(
                expected = (true, false),
                (attacking, idle))
        }

    // ════════════════════════════════════════════════════════
    // applyAttackHit — 命中で HP 減 + 経験値、回避で不変
    // ════════════════════════════════════════════════════════

    /// 命中（武器命中 80 → 命中率 77 > 50）: 敵 HP は 10 − 4 = 6 になり、攻撃側に経験値が入る。
    @Test
    def testAttackHitDamagesEnemyAndGrantsExp(): Unit \ Assert =
        let w = runAttack(battleCmds(80));
        Assert.assertEq(
            expected = (Some(6), Some(true)),
            (World.hpOf(World.EntityRef.Enemy(1), w),
             World.progressOf(World.EntityRef.Player(0), w) |> Option.map(p -> snd(p) > 0)))

    /// 回避（武器命中 40 → 命中率 37 ≤ 50）: 敵 HP は 10 のまま、経験値も入らない。
    @Test
    def testAttackMissLeavesEnemyAndExpUnchanged(): Unit \ Assert =
        let w = runAttack(battleCmds(40));
        Assert.assertEq(
            expected = (Some(10), Some(0)),
            (World.hpOf(World.EntityRef.Enemy(1), w),
             World.progressOf(World.EntityRef.Player(0), w) |> Option.map(snd)))

    // ════════════════════════════════════════════════════════
    // applyEnemyAttackHit — 敵→味方の鏡像数値（resolveStrike 経由の回帰固定）
    // ════════════════════════════════════════════════════════

    /// applyEnemyAttackHit を副作用モックで包んで実行する（アニメは介在しない）。
    /// runAttack と同じ ONE-Ref traced world 駆動＝検証は World store で。
    def runEnemyAttack(cmds: List[World.Cmd]): (List[Int32], World) =
        region rc {
            let (killed, _keys, w) = TestUnitFixtures.withTracedWorld(rc, 0i64, cmds, () ->
                TestUnitFixtures.withMockBoard(battleBoard(cmds), () ->
                TestUnitFixtures.withMockRandom(() ->
                TestUnitFixtures.withMockGame(() ->
                TestUnitFixtures.withMockAudio(() ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withNoopAnim(() ->
                    CombatDriver.applyEnemyAttackHit(1)))))))));
            (killed, w)
        }

    /// 敵→味方の鏡像数値: 敵(素3+武器2) vs 味方防御 1 → 4 ダメージ、
    /// 命中率 = 80 + 技2×2 + 幸運2÷2 − (速さ3×2 + 幸運2) = 77 > 50 で命中。
    /// 味方 HP は 10 − 4 = 6、死亡には至らないので killed リストは空。
    /// 味方→敵（testAttackHitDamagesEnemyAndGrantsExp）と同じ数値になることが
    /// 攻守が同一の resolveStrike（= Combat.estimate）を通る回帰固定になる。
    @Test
    def testEnemyAttackHitDamagesPlayer(): Unit \ Assert =
        let cmds = List.append(battleCmds(80),
            World.Cmd.SetAttackTarget(World.EntityRef.Enemy(1), 0) :: Nil);
        let (killed, w) = runEnemyAttack(cmds);
        Assert.assertEq(
            expected = (Some(6), true),
            (World.hpOf(World.EntityRef.Player(0), w),
             List.isEmpty(killed)))

    // ════════════════════════════════════════════════════════
    // 死亡演出 — 撃破された敵は isDying=true になり即 despawn しない
    // ════════════════════════════════════════════════════════

    /// 撃破された敵は World から即 despawn されず、`isDying = true` で death_blink 開始
    /// （despawn は death_blink finished の completeDeath まで遅延される）。
    @Test
    def testKillStartsEnemyDeathBlink(): Unit \ Assert =
        let cmds = List.append(battleCmds(80),
            World.Cmd.SetHp(World.EntityRef.Enemy(1), 4) :: Nil);
        let w = runAttack(cmds);
        Assert.assertEq(
            expected = (Some(true), true),
            (World.dataFromWorldEnemy(1, w) |> Option.map(e -> e#isDying),
             World.isDyingOf(World.EntityRef.Enemy(1), w)))

    // ════════════════════════════════════════════════════════
    // onLungeDone phase マトリクス — Player × PlayerAttackHold × Kill
    // ════════════════════════════════════════════════════════

    /// 撃破直後（対象が isDying）の味方 lunge 完了は、PlayerAttackHold を維持したまま
    /// Pacing.hold を積む（撃破演出のホールド。ターンはまだ進めない）。
    @Test
    def testLungeDoneKillHoldsPacing(): Unit \ Assert =
        region rc {
            let w0 = TestWorldFixtures.worldOf(List.append(
                battleCmds(80), World.Cmd.SetDying(World.EntityRef.Enemy(1)) :: Nil));
            let (result, _w) =
                TestUnitFixtures.withWorldAppliedSeeded(rc, w0, () ->
                TestUnitFixtures.withWorldPhase(SimPhase.PlayerTurn, () ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withMockEnemyTurnQueue(() ->
                TestUnitFixtures.withMockRandom(() ->
                    run {
                        TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
                        let _ = CombatDriver.onLungeDone(Faction.Player, 0);
                        (TurnPhase.State.get(), Pacing.State.isHolding())
                    } with TurnPhase.withState(rc)
                      with SelectedPlayer.withState(rc)
                      with CursorState.withState(rc)
                      with Pacing.withState(rc)
                      with RangeOverlayState.withState(rc))))));
            Assert.assertEq(
                expected = (TurnPhase.Phase.PlayerAttackHold, true), result)
        }

    /// 「敵ターンか」の判定が **World 由来**（TurnPhase.State でない）ことを固定する。
    /// TurnPhase.State をわざと非敵ターン（PlayerAttackHold）にしつつ World phase を EnemyTurn にすると、
    /// onLungeDone は敵ターン分岐（attackTargetId クリアのみ・Pacing.hold なし）を取る。
    /// もし読みが TurnPhase.State 由来に退行すれば kill-hold 分岐へ落ち isHolding=true となり赤になる。
    @Test
    def testLungeDoneBranchesOnWorldPhaseNotTurnState(): Unit \ Assert =
        region rc {
            let w0 = TestWorldFixtures.worldOf(List.append(
                battleCmds(80), World.Cmd.SetDying(World.EntityRef.Enemy(1)) :: Nil));
            let (result, _w) =
                TestUnitFixtures.withWorldAppliedSeeded(rc, w0, () ->
                TestUnitFixtures.withWorldPhase(SimPhase.EnemyTurn, () ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withMockEnemyTurnQueue(() ->
                TestUnitFixtures.withMockRandom(() ->
                    run {
                        TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
                        let _ = CombatDriver.onLungeDone(Faction.Player, 0);
                        (TurnPhase.State.get(), Pacing.State.isHolding())
                    } with TurnPhase.withState(rc)
                      with SelectedPlayer.withState(rc)
                      with CursorState.withState(rc)
                      with Pacing.withState(rc)
                      with RangeOverlayState.withState(rc))))));
            // TurnPhase は分岐で触らないので PlayerAttackHold のまま。World=EnemyTurn ゆえ hold は積まれない。
            Assert.assertEq(
                expected = (TurnPhase.Phase.PlayerAttackHold, false), result)
        }

    // ════════════════════════════════════════════════════════
    // stepEntities — シグナル配信（owner 完全一致で自 entity 宛だけ拾う）
    // ════════════════════════════════════════════════════════

    /// GameOverRequest の no-op スタブ（飛んだら何もしない）。
    def withNoopGameOver(thunk: Unit -> a \ ef):
            a \ (ef - CustomEffects.GameOverRequest) =
        run { thunk() } with handler CustomEffects.GameOverRequest {
            def markDeaths(_positions, k) = k()
            def request(scene, k) = k(scene)
            def restartBeginning(scene, k) = k(scene)
            def restartFloor(scene, k) = k(scene)
            def reviveInPlace(scene, k) = k(scene)
        }

    /// signals を CombatDriver.stepEntities で 1 回配信した後の World を返す。
    /// stepEntities は在籍 id を World から辿り、自 entity 宛の signal だけを消費する
    /// （実機の frame パイプラインと同じ経路。node/path の per-entity 呼び分けは廃止済み）。
    /// TurnPhase は EnemyTurn（反撃完了 = attackTargetId クリアの最小観測経路）に固定する。
    def stepOnce(signals: List[World.AnimSignal], cmds: List[World.Cmd]): World =
        let w0 = TestWorldFixtures.worldOf(cmds);
        region rc {
            let (_, w) =
                TestUnitFixtures.withWorldAppliedSeeded(rc, w0, () ->
                TestUnitFixtures.withWorldPhase(SimPhase.EnemyTurn, () ->
                TestUnitFixtures.withMockAudio(() ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withMockEnemyTurnQueue(() ->
                TestUnitFixtures.withNoopThiefDrop(() ->
                withNoopGameOver(() ->
                TestUnitFixtures.withMockRandom(() ->
                    run {
                        TurnPhase.State.put(TurnPhase.Phase.EnemyTurn);
                        CombatDriver.stepEntities(signals)
                    } with TurnPhase.withState(rc)
                      with SelectedPlayer.withState(rc)
                      with CursorState.withState(rc)
                      with Pacing.withState(rc)
                      with RangeOverlayState.withState(rc)))))))));
            w
        }

    /// 他ユニット宛の signal は食わない: Player(0) 宛の LungeDone だけがあるとき、
    /// stepEntities を 1 回回すと Player(0) の attackTargetId はクリアされる一方、
    /// 自分宛の signal が無い Enemy(1) の attackTargetId は不変のまま残る。
    @Test
    def testStepEntitiesDrainsOnlyOwnSignals(): Unit \ Assert =
        let cmds = List.append(battleCmds(80),
            World.Cmd.SetAttackTarget(World.EntityRef.Enemy(1), 0) :: Nil);
        let signals = World.AnimSignal.LungeDone(World.EntityRef.Player(0)) :: Nil;
        let w = stepOnce(signals, cmds);
        Assert.assertEq(
            expected = (None, Some(0)),
            (World.attackTargetOf(World.EntityRef.Player(0), w),
             World.attackTargetOf(World.EntityRef.Enemy(1), w)))

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
            (CombatRules.hitSoundName(0, false, WeaponCatalog.WeaponType.Sword),
             CombatRules.hitSoundName(0, true, WeaponCatalog.WeaponType.Magic)))

    /// 必殺（クリティカル）が発動し、ダメージ 1 以上なら "critical"。
    @Test
    def testHitSoundCriticalWhenCrit(): Unit \ Assert =
        Assert.assertEq(
            expected = "critical",
            CombatRules.hitSoundName(15, true, WeaponCatalog.WeaponType.Sword))

    /// 魔法武器で必殺なしダメージ 1 以上なら "magic"。
    @Test
    def testHitSoundMagicWhenMagicWeapon(): Unit \ Assert =
        Assert.assertEq(
            expected = "magic",
            CombatRules.hitSoundName(5, false, WeaponCatalog.WeaponType.Magic))

    /// 物理武器で必殺なしダメージ 1 以上なら通常の "damage"。
    @Test
    def testHitSoundDamageWhenPhysical(): Unit \ Assert =
        Assert.assertEq(
            expected = "damage",
            CombatRules.hitSoundName(5, false, WeaponCatalog.WeaponType.Lance))
}
