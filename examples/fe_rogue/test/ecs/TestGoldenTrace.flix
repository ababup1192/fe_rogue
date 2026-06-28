// slice `golden-trace` のテスト（CORE/PARTIAL オラクル）。
//
// 現行 OOP combat（Cmd を emit する legacy 経路）を固定 seed で PUBLIC seam 経由に駆動し、
// その決定論的な **Cmd-stream（cmdKey 列）+ 最終 World** を golden literal として凍結する。
// これが将来の `resolveCombat → (World, [SimEvent])` が再現すべきオラクルになる。
//
// 駆動は PUBLIC seam（applyAttackHit / applyEnemyAttackHit / onLungeDone）。private な
// resolveAttack/resolveEnemyAttack ではない。attackTargetId は **SCENE** で seed する
// （applyAttackHit は d#attackTargetId を scene から読む。World pre-set では no-op になる）。
// ハーネスは `TestUnitFixtures.withTracedWorld`（ONE worldRef を Command/WorldQuery/RngDraw で
// 共有する ref-backed 3-handler）で、combatViewOf の read-after-write を壊さない。
//
// 凍結する 5 fixture（DoD §4）:
//   (A)  level-up: 撃破→経験値 100 跨ぎ→ rollGrowth×9（12 draw）。SetHp(enemy,0)→SetHp(player,newHp)→Progress。
//   (A2) no-level-up: 撃破するが閾値跨がず→ bare SetProgress（ExpGained の live emission を cross-check）。
//   (B)  enemy effectRule subtrace: spdDown を付与→ SetHp(player)→ Cmd.Add(player, SpdDown ordinal=1)。
//   (C)  orchestrated onLungeDone（Kill 分岐）: 追撃 roll は in-position で消費しつつ分岐 OFF→ ClrTgt。
//   (D)  COUNTER-attack chain: 味方攻撃完了→敵反撃開始→敵の反撃が味方を撃破（multi-callback Cmd-stream）。
//
// 全 fixture: combatViewOf-Some pre-guard（vacuous scene-fallback を防ぐ）+ non-empty-stream guard。
// weapon hit=200 で常時命中・weapon crit=0 で必殺なし＝outcome は seed 非依存（roll 値のみ seed 依存・
// 凍結対象は cmdKey/world ゆえ literal は seed 非依存）。reproducibility は二度引きで担保。

mod TestGoldenTrace {

    use World.EntityRef
    use TestUnitFixtures.{testResource, testEnemyResource, testWeapon}

    // 固定 seed（reproducibility テスト用。outcome 自体は seed 非依存）。
    def seed(): Int64 = 12345i64

    // ── fixtures ──────────────────────────────────────────────────────────────

    /// 攻撃中の味方（id=0・{2,2}）。`exp` で level-up 跨ぎを作り分け、`weaponHit` で命中を固定する。
    /// 攻撃力 素3+武器2=5、敵防御1 ゆえ命中ダメージ4。growthRates=0（testResource 既定）で
    /// level-up 時の現在 HP 増分は 0（newHp=10）＝予測可能。
    def player(exp: Int32, hp: Int32, atkTarget: Option[Int32], weaponHit: Int32): PlayerScene.Data = {
        id                = 0,
        classId           = "test_player",
        gridPos           = {x = 2, y = 2},
        moveTiles         = 4,
        hp                = hp,
        waited            = false,
        attackTargetId    = atkTarget,
        resource          = testResource(4, 10),
        weapons           = ({hit = weaponHit | testWeapon()}: UnitCatalog.WeaponResource) :: Nil,
        staves            = Nil,
        consumables       = Nil,
        selectedItem      = None,
        moveStepsTaken    = 0,
        facing            = Staff.Direction.Down,
        hidden            = false,
        usedStairs        = false,
        level             = 1,
        exp               = exp,
        pendingLevelUp    = None,
        statuses          = Nil,
        rings             = Nil,
        ringEquipped      = false,
        followUpUsed      = false
    }

    /// 敵フィクスチャ。`rule` で effectRule（生 Json）を差し込み、`weaponHit` で命中を固定する。
    def enemy(id: Int32, hp: Int32, gridPos: {x = Int32, y = Int32}, isDying: Bool,
              atkTarget: Option[Int32], rule: Option[Util.Json.Json], weaponHit: Int32): EnemyScene.Data = {
        id             = id,
        resourceId     = "test_enemy",
        gridPos        = gridPos,
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 3,
        hp             = hp,
        isDying        = isDying,
        attackTargetId = atkTarget,
        resource       = {effectRule = rule | testEnemyResource(3, 10)},
        weapon         = Some(({hit = weaponHit | testWeapon()}: UnitCatalog.WeaponResource)),
        acted          = false,
        prevPos        = None,
        statuses       = Nil,
        ring           = None,
        followUpUsed   = false,
        bottleUsed     = false
    }

    /// 簡易 JSON を生 Json へ（effectRule 用）。parse 失敗は None で B が non-empty guard に落ちる。
    def ruleJson(s: String): Option[Util.Json.Json] =
        Util.Json.parse(s) |> Result.toOption

    /// LeveledUp の view-only payload（SimEvent オラクル用）。World reducer は level/exp/hp の数値しか使わず
    /// result は触らないため任意のダミーで足りる。
    def dummyResult(): LevelSystem.Result =
        ({unitName = "x", fromLevel = 1, toLevel = 2, changes = Nil}: LevelSystem.Result)

    /// 13×13 の壁なし floor map（toBoard / mapSnapshotOf が map ノードを要求するため）。TestSimEvent 踏襲。
    def floorMapLayer(): TileMapLayer =
        let atlas: TileSetAtlasSource = {
            textureName = "test", texWidth = 0.0, texHeight = 0.0,
            tileSize = 16.0, marginX = 0.0, marginY = 0.0, spacingX = 0.0, spacingY = 0.0
        };
        TileMapLayer.make({
            tileSet        = TileSet.make(atlas),
            tiles          = Nil,
            collisionCells = Nil,
            gridSize       = ({x = 13, y = 13}: {x = Int32, y = Int32})
        })

    def floorMapData(): MapScene.Data = {
        anchorOffset = {x = 0, y = 0},
        spawnGrid    = {x = 5, y = 5},
        placements   = RoomLayout.singleRoom(13, 13),
        roomCount    = 1,
        plan         = ({modulePaths = Nil, sideConnections = Nil, roomCount = 1}: DungeonGenerator.Plan)
    }

    /// World ノード下に player + 任意数の enemy + floor map を挿した最小 scene。
    def sceneOf(p: PlayerScene.Data, enemies: List[EnemyScene.Data]): Scene[NodeTag] =
        let worldM = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        let base = Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(worldM, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(p#id),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.Player(p)))
            |> Scene.addNode("DungeonLevel0",
                EngineNode.TileMapLayerWithState(floorMapLayer(), NodeTag.Map(floorMapData())));
        List.foldLeft((sc, e) ->
            Scene.addChildAt(MapScene.worldPath(), EnemyScene.enemyName(e#id),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.Enemy(e)), sc),
            base, enemies)

    // ── harness runners ───────────────────────────────────────────────────────

    /// applyAttackHit を traced harness + 副作用モックで駆動。(後 scene, cmdKey 列, 最終 World)。
    def runAttack(sc: Scene[NodeTag]): (Scene[NodeTag], List[(String, Int32, Int32, Int32)], World) =
        region rc {
            TestUnitFixtures.withTracedWorld(rc, seed(), sc, () ->
            TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(sc), () ->
            TestUnitFixtures.withNoopThiefDrop(() ->
            TestUnitFixtures.withMockGame(() ->
            TestUnitFixtures.withMockAudio(() ->
            TestUnitFixtures.withMockGameLogger(() ->
            TestUnitFixtures.withNoopAnim(() ->
            TestUnitFixtures.withNoopTween(() ->
                CombatScene.applyAttackHit(0, sc)))))))))
        }

    /// applyAttackHit を CONSTANT-RNG harness で駆動（draw を全て `rngVal` 固定にする）。
    /// roll-dependence 反証用＝seeded 版 `runAttack` と cmd-stream を比較する。
    def runAttackConst(sc: Scene[NodeTag], rngVal: Int32): (Scene[NodeTag], List[(String, Int32, Int32, Int32)], World) =
        region rc {
            TestUnitFixtures.withConstTracedWorld(rc, rngVal, sc, () ->
            TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(sc), () ->
            TestUnitFixtures.withNoopThiefDrop(() ->
            TestUnitFixtures.withMockGame(() ->
            TestUnitFixtures.withMockAudio(() ->
            TestUnitFixtures.withMockGameLogger(() ->
            TestUnitFixtures.withNoopAnim(() ->
            TestUnitFixtures.withNoopTween(() ->
                CombatScene.applyAttackHit(0, sc)))))))))
        }

    /// applyEnemyAttackHit を traced harness + 副作用モックで駆動。((後 scene, killed), cmdKey 列, World)。
    def runEnemyAttack(sc: Scene[NodeTag], enemyId: Int32):
            ((Scene[NodeTag], List[Int32]), List[(String, Int32, Int32, Int32)], World) =
        region rc {
            TestUnitFixtures.withTracedWorld(rc, seed(), sc, () ->
            TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(sc), () ->
            TestUnitFixtures.withNoopThiefDrop(() ->
            TestUnitFixtures.withMockGame(() ->
            TestUnitFixtures.withMockAudio(() ->
            TestUnitFixtures.withMockGameLogger(() ->
            TestUnitFixtures.withNoopAnim(() ->
            TestUnitFixtures.withNoopTween(() ->
                CombatScene.applyEnemyAttackHit(enemyId, sc)))))))))
        }

    // combatViewOf が attacker/defender 両方で Some か（vacuous scene-fallback の pre-guard）。
    def viewSome(ref: EntityRef, sc: Scene[NodeTag]): Bool =
        Option.nonEmpty(World.combatViewOf(ref, World.syncFromScene(sc, World.empty())))

    // ── (A) LEVEL-UP path ─────────────────────────────────────────────────────

    /// 味方が隣接敵を撃破し経験値 100 を跨いで level-up する。isolated applyAttackHit は
    /// 12 draw [hit, crit, thief-pos, growth×9] を引く（roll 値は凍結しない・cmdKey/world を凍結）。
    /// cmd-stream（GENERATE-THEN-FREEZE で凍結した FULL legacy emission）:
    ///   SetHp(enemy,0)[applyHit:653] → SetHp(enemy,0)+Dying(enemy)[startDeathAnimation]
    ///   → SetHp(player,newHp=10)[applyLevelUp:997] → Progress(player, lv2, exp34)[:999]。
    ///   battleExp(1,1,kill)=35、99+35-100=34。growthRates=0 ゆえ現 HP 増分 0（newHp=10）。
    @Test
    def testGoldenLevelUp(): Unit \ Assert =
        let sc = sceneOf(player(99, 10, Some(1), 200), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, keys, w) = runAttack(sc);
        let golden =
            ("SetHp", 1000001, 0, 0) ::
            ("SetHp", 1000001, 0, 0) ::
            ("Dying", 1000001, 0, 0) ::
            ("SetHp", 0, 10, 0) ::
            ("Progress", 0, 2, 34) :: Nil;
        let proj = (World.hpOf(EntityRef.Enemy(1), w),
                    World.hpOf(EntityRef.Player(0), w),
                    World.progressOf(EntityRef.Player(0), w));
        Assert.assertEq(
            expected = (true, true, golden, (Some(0), Some(10), Some((2, 34)))),
            (viewSome(EntityRef.Player(0), sc) and viewSome(EntityRef.Enemy(1), sc),
             not List.isEmpty(keys), keys, proj))

    // ── (A2) NO-LEVEL-UP path ─────────────────────────────────────────────────

    /// 同一フィクスチャだが exp=0 ゆえ撃破しても閾値を跨がない → legacy は bare SetProgress@975 を emit
    /// （SetHp(player) なし・growth roll なし）。これが ExpGained がマップする real legacy emission。
    /// cmd-stream: SetHp(enemy,0) → SetHp(enemy,0)+Dying(enemy)[startDeathAnimation] → bare Progress(player, lv1, exp35)。
    @Test
    def testGoldenNoLevelUp(): Unit \ Assert =
        let sc = sceneOf(player(0, 10, Some(1), 200), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, keys, w) = runAttack(sc);
        let golden =
            ("SetHp", 1000001, 0, 0) ::
            ("SetHp", 1000001, 0, 0) ::
            ("Dying", 1000001, 0, 0) ::
            ("Progress", 0, 1, 35) :: Nil;
        let proj = (World.hpOf(EntityRef.Enemy(1), w),
                    World.hpOf(EntityRef.Player(0), w),
                    World.progressOf(EntityRef.Player(0), w));
        Assert.assertEq(
            expected = (true, golden, (Some(0), Some(10), Some((1, 35)))),
            (not List.isEmpty(keys), keys, proj))

    // ── Phase C 等価: resolveCombat 本体 が legacy と final-World 等価か ───────────

    /// ②検証: `CombatSystem.resolveAttack`（新 sim・(World,[SimEvent]) を返す）を A2 と同じ fixture・同 seed で
    /// 駆動し、legacy `runAttack`（applyAttackHit）の最終 World と **直接一致**するか（enemy hp/player hp/progress）。
    /// no-level-up path は draw 順（crit/thief は crit率0・noopThief で outcome 不変）の影響を受けないので、
    /// hit ロール 1 本で legacy と等価になる。これが cutover の final-World 安全網の最小単位。
    @Test
    def testResolveCombatEqualsLegacyNoLevelUp(): Unit \ Assert =
        let sc = sceneOf(player(0, 10, Some(1), 200), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, legacyW) = runAttack(sc);
        let w0 = World.syncFromScene(sc, World.empty());
        let (sysW, evCount) = region rc {
            let (w, evs) = TestUnitFixtures.withSeededRng(rc, seed(), () ->
                CombatSystem.resolveAttack(w0, {ref = EntityRef.Player(0), level = 1}, {ref = EntityRef.Enemy(1), level = 1}));
            (w, List.length(evs))
        };
        // B4: anti-vacuity — combatViewOf-Some pre-guard（scene-fallback でなく World 由来）+ 非空 stream。
        Assert.assertEq(
            expected = (true, true,
                        (World.hpOf(EntityRef.Enemy(1), legacyW),
                         World.hpOf(EntityRef.Player(0), legacyW),
                         World.progressOf(EntityRef.Player(0), legacyW))),
            (viewSome(EntityRef.Player(0), sc) and viewSome(EntityRef.Enemy(1), sc),
             evCount > 0,
             (World.hpOf(EntityRef.Enemy(1), sysW),
              World.hpOf(EntityRef.Player(0), sysW),
              World.progressOf(EntityRef.Player(0), sysW))))

    /// B5: level-up path も legacy 等価か。A fixture（player exp=99 → 撃破で 100 跨ぎ→ Lv2/exp34）。
    /// growthRates=0 ゆえ hit→growth(spike) と hit→crit→thief→growth(legacy) の draw 順差は最終 World に効かない
    /// 範囲（成長が起きない）で legacy 凍結 World に一致する（その制約は CombatSystem header の ☐ に明記）。
    @Test
    def testResolveCombatEqualsLegacyLevelUp(): Unit \ Assert =
        let sc = sceneOf(player(99, 10, Some(1), 200), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, legacyW) = runAttack(sc);
        let w0 = World.syncFromScene(sc, World.empty());
        let (sysW, evCount) = region rc {
            let (w, evs) = TestUnitFixtures.withSeededRng(rc, seed(), () ->
                CombatSystem.resolveAttack(w0, {ref = EntityRef.Player(0), level = 1}, {ref = EntityRef.Enemy(1), level = 1}));
            (w, List.length(evs))
        };
        Assert.assertEq(
            expected = (true, true,
                        (World.hpOf(EntityRef.Enemy(1), legacyW),
                         World.hpOf(EntityRef.Player(0), legacyW),
                         World.progressOf(EntityRef.Player(0), legacyW))),
            (viewSome(EntityRef.Player(0), sc) and viewSome(EntityRef.Enemy(1), sc),
             evCount > 0,
             (World.hpOf(EntityRef.Enemy(1), sysW),
              World.hpOf(EntityRef.Player(0), sysW),
              World.progressOf(EntityRef.Player(0), sysW))))

    /// B1 を pin: **overkill**（enemy hp=3 を dmg=4 で撃破→ strike#newHp=-1）でも、CombatSystem の clamp で
    /// 最終 enemy hp=0 になり legacy（startDeathAnimation の hard 0）と一致する。clamp が無ければ resolveAttack は
    /// -1 を残し legacy の 0 と乖離してこのテストが落ちる＝clamp の divergence 防止価値を回帰固定する。
    @Test
    def testResolveCombatEqualsLegacyOverkill(): Unit \ Assert =
        let sc = sceneOf(player(0, 10, Some(1), 200), enemy(1, 3, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, legacyW) = runAttack(sc);
        let w0 = World.syncFromScene(sc, World.empty());
        let (sysW, evCount) = region rc {
            let (w, evs) = TestUnitFixtures.withSeededRng(rc, seed(), () ->
                CombatSystem.resolveAttack(w0, {ref = EntityRef.Player(0), level = 1}, {ref = EntityRef.Enemy(1), level = 1}));
            (w, List.length(evs))
        };
        Assert.assertEq(
            expected = (true, Some(0), World.hpOf(EntityRef.Enemy(1), legacyW)),  // legacy も 0
            (evCount > 0, World.hpOf(EntityRef.Enemy(1), sysW), World.hpOf(EntityRef.Enemy(1), sysW)))

    // ── (E) ROLL-DEPENDENT fixture（定数生成器では再現不能）─────────────────────

    /// 既存 fixture は weaponHit=200・crit=0 で「常時命中・必殺なし」＝outcome が draw 値に依存せず、
    /// **定数生成器でも素通り**する穴があった（issue: streams are random-independent）。これを塞ぐ。
    /// weaponHit=33 ⇒ hitRate=30（accuracy 5 − avoid 8 = weaponHit−3）。seed 12345 の最初の draw は 13
    /// （13<30 ⇒ 命中→撃破）だが、定数生成器 50 は 50<30=false ⇒ 回避（applyMiss は Cmd を emit せず空 stream）。
    /// ⇒ SEEDED と CONSTANT-50 で cmd-stream が分岐＝golden が draw 列に依存することを固定する。
    @Test
    def testGoldenRollDependentHit(): Unit \ Assert =
        let sc = sceneOf(player(0, 10, Some(1), 33), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, seededKeys, _) = runAttack(sc);
        let (_, constKeys, _)  = runAttackConst(sc, 50);
        // SEEDED（hitRoll=13<30）＝命中→撃破の cmd-stream（A2 と同形だが今回は roll 依存で命中している）。
        let golden =
            ("SetHp", 1000001, 0, 0) ::
            ("SetHp", 1000001, 0, 0) ::
            ("Dying", 1000001, 0, 0) ::
            ("Progress", 0, 1, 35) :: Nil;
        Assert.assertEq(
            expected = (true, golden, true, true),
            (viewSome(EntityRef.Player(0), sc) and viewSome(EntityRef.Enemy(1), sc),
             seededKeys,
             List.isEmpty(constKeys),       // CONSTANT-50（回避）は world mutation 無し＝空 stream
             seededKeys != constKeys))      // 定数生成器では golden を再現できない＝draw 依存の証明

    // ── (B) ENEMY effectRule subtrace ─────────────────────────────────────────

    /// effectRule(spdDown を player へ・chance 既定100=必発) を持つ敵が applyEnemyAttackHit を駆動。
    /// roll [hit, crit, effect] を引き、命中で味方 HP を 4 削り（10→6・撃破せず）spdDown を付与。
    /// cmd-stream: SetHp(player,6) → ClrImmob(player)[releaseBind:759] → Cmd.Add(player, SpdDown ordinal=1)。
    @Test
    def testGoldenEnemyEffectRule(): Unit \ Assert =
        let rule = ruleJson("{\"when\":\"onHit\",\"to\":\"enemy\",\"op\":\"spdDown\",\"amount\":3,\"for\":\"turns\",\"forTurns\":3}");
        let sc = sceneOf(player(0, 10, None, 80), enemy(1, 10, {x = 3, y = 2}, false, Some(0), rule, 200) :: Nil);
        let ((_, killed), keys, w) = runEnemyAttack(sc, 1);
        // Add の cmdKey 4th slot に magnitude=3 が載る（kind=1=SpdDown）。
        let golden =
            ("SetHp", 0, 6, 0) ::
            ("ClrImmob", 0, 0, 0) ::
            ("Add", 0, 1, 3) :: Nil;
        // 存在チェックでなく付与された Status を FULL 射影で凍結する（effect/magnitude/remaining）。
        // 量や残ターンが違えば将来の resolveCombat はここで落ちる（kind 一致だけでは素通りさせない）。
        let statusProj =
            World.statusEffectsOf(EntityRef.Player(0), w)
                |> List.map(s -> (s#effect, s#magnitude, s#remaining));
        Assert.assertEq(
            expected = (true, true, golden, Some(6), true,
                        (StatusSystem.StatusEffect.SpdDown, 3, 3) :: Nil),
            (viewSome(EntityRef.Enemy(1), sc) and viewSome(EntityRef.Player(0), sc),
             not List.isEmpty(keys), keys,
             World.hpOf(EntityRef.Player(0), w), List.isEmpty(killed), statusProj))

    // ── (C) ORCHESTRATED onLungeDone（Kill 分岐）──────────────────────────────

    /// 撃破済み(isDying)の敵に対する味方主攻撃完了。追撃 roll は line:203 で IN POSITION に消費されるが
    /// 追撃分岐は plain weapon（brave/pursuit なし）で OFF。続いて decideView→Kill → ClrTgt + PlayerAttackHold。
    /// cmd-stream: ClrTgt(player)。最終 Phase=PlayerAttackHold。
    @Test
    def testGoldenOnLungeDoneKill(): Unit \ Assert =
        let sc = sceneOf(player(0, 10, Some(1), 80), enemy(1, 4, {x = 3, y = 2}, true, None, ruleJson(""), 80) :: Nil);
        region rc {
            let ((_, finalPhase), keys, _) =
                TestUnitFixtures.withTracedWorld(rc, seed(), sc, () ->
                TestUnitFixtures.withWorldPhase(SimPhase.PlayerTurn, () ->
                TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(sc), () ->
                TestUnitFixtures.withNoopThiefDrop(() ->
                TestUnitFixtures.withMockGame(() ->
                TestUnitFixtures.withMockAudio(() ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withMockEnemyTurnQueue(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withNoSelection(() ->
                    run {
                        TestUnitFixtures.withPhaseRef(rc, TurnPhase.Phase.PlayerAttackHold, () ->
                            CombatScene.onLungeDone(Faction.Player, 0, sc))
                    } with Pacing.withState(rc))))))))))));
            let golden = ("ClrTgt", 0, 0, 0) :: Nil;
            Assert.assertEq(
                expected = (true, golden, TurnPhase.Phase.PlayerAttackHold),
                (not List.isEmpty(keys), keys, finalPhase))
        }

    // ── (D) COUNTER-attack chain ──────────────────────────────────────────────

    /// 味方攻撃完了→敵反撃開始→敵の反撃が味方を撃破、の multi-callback Cmd-stream を凍結する
    /// （resolveCombat の最難 async path＝Phase-C motivating scenario）。
    /// seam を順に駆動:
    ///   (1) onLungeDone(Player,0): decideView→Counter(1) → ClrTgt(player) + startEnemyCounter→startAttack
    ///       (敵に AtkTgt(player) を立てる)。追撃 roll は in-position 消費・分岐 OFF。
    ///   (2) applyEnemyAttackHit(1): 敵が味方(hp4)を 4 ダメージで撃破 → SetHp(player,0)、killed=[0]。
    /// cmd-stream: ClrTgt(player) → AtkTgt(enemy1, player0) → SetHp(player,0) → ClrImmob(player)[releaseBind:759]。
    @Test
    def testGoldenCounterChain(): Unit \ Assert =
        let sc = sceneOf(player(0, 4, Some(1), 80), enemy(1, 10, {x = 3, y = 2}, false, None, ruleJson(""), 200) :: Nil);
        region rc {
            let ((result, _), keys, w) =
                TestUnitFixtures.withTracedWorld(rc, seed(), sc, () ->
                TestUnitFixtures.withWorldPhase(SimPhase.PlayerTurn, () ->
                TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(sc), () ->
                TestUnitFixtures.withNoopThiefDrop(() ->
                TestUnitFixtures.withMockGame(() ->
                TestUnitFixtures.withMockAudio(() ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withMockEnemyTurnQueue(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withNoSelection(() ->
                    run {
                        TestUnitFixtures.withPhaseRef(rc, TurnPhase.Phase.PlayerAttackHold, () -> {
                            let s1 = CombatScene.onLungeDone(Faction.Player, 0, sc);
                            CombatScene.applyEnemyAttackHit(1, s1)
                        })
                    } with Pacing.withState(rc))))))))))));
            let (_, killed) = result;
            let golden =
                ("ClrTgt", 0, 0, 0) ::
                ("AtkTgt", 1000001, 0, 0) ::
                ("SetHp", 0, 0, 0) ::
                ("ClrImmob", 0, 0, 0) :: Nil;
            Assert.assertEq(
                expected = (true, golden, Some(0), 0 :: Nil),
                (not List.isEmpty(keys), keys, World.hpOf(EntityRef.Player(0), w), killed))
        }

    // ── reproducibility + final-board parity ──────────────────────────────────

    /// 同 seed で 2 回駆動すると cmdKey 列・最終 World 射影が bit-identical（決定論）。
    @Test
    def testGoldenReproducible(): Unit \ Assert =
        let mk = () -> sceneOf(player(99, 10, Some(1), 200), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, k1, w1) = runAttack(mk());
        let (_, k2, w2) = runAttack(mk());
        let projOf = w -> (World.hpOf(EntityRef.Enemy(1), w),
                           World.hpOf(EntityRef.Player(0), w),
                           World.progressOf(EntityRef.Player(0), w));
        Assert.assertEq(expected = (true, true), (k1 == k2, projOf(w1) == projOf(w2)))

    /// 隣接攻撃は駒を動かさない＝最終 World 由来の board が、独立に凍結した piece-list literal と一致し、
    /// かつ original scene 由来の board と `boardMatchesScene` で一致する（board-lock を使う凍結契約）。
    @Test
    def testGoldenFinalBoardParity(): Unit \ Assert =
        let sc = sceneOf(player(99, 10, Some(1), 200), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, w) = runAttack(sc);
        // (faction, id, x, y): player(0)@{2,2}, enemy(1)@{3,2}（撃破しても pos は不変）。
        let goldenPieces = (0, 0, 2, 2) :: (1, 1, 3, 2) :: Nil;
        Assert.assertEq(
            expected = (goldenPieces, true),
            (World.boardKey(World.toBoard(w, sc)), World.boardMatchesScene(w, sc)))

    // ── SimEvent ORACLE（frozen [SimEvent] = resolveCombat の比較対象）──────────────
    //
    // golden-trace は legacy の Cmd-stream + 最終 World を凍結する（role a）。しかし将来の
    // `resolveCombat → (World, [SimEvent])` が emit する **[SimEvent] には比較対象が無かった**。
    // ここで idealized な [SimEvent]（legacy の冗長 double-SetHp を畳んだ CLEAN 版）を凍結し（role b）:
    //   (a) eventToCmds 射影が frozen Cmd-key 列に一致（SimEvent-stream 形の regression lock）、
    //   (b) その [SimEvent] を初期 World へ fold した最終 World 射影が、LEGACY 経路の最終 World 射影に
    //       一致（SimEvent オラクルと legacy オラクルが同一 World へ収束＝real equivalence の比較対象）。
    // resolveCombat 実装後は「resolveCombat の返す [SimEvent] == この frozen events」を足せばよい。

    /// (A) level-up を SimEvent で表した frozen オラクル。Damaged→ViewFx(Died)→Dying→LeveledUp。
    @Test
    def testSimEventOracleLevelUp(): Unit \ Assert =
        let sc = sceneOf(player(99, 10, Some(1), 200), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, legacyW) = runAttack(sc);
        let events =
            World.SimEvent.Damaged(EntityRef.Enemy(1), {newHp = 0, dmg = 4}) ::
            World.SimEvent.ViewFx(World.ViewFxKind.Died(EntityRef.Enemy(1))) ::
            World.SimEvent.Dying(EntityRef.Enemy(1)) ::
            World.SimEvent.LeveledUp({entity = EntityRef.Player(0),
                newLevel = 2, newExp = 34, newHp = 10, result = dummyResult()}) :: Nil;
        // (a) CLEAN cmd 射影（敵 SetHp は 1 回だけ＝legacy の startDeathAnimation 二重書きを畳む）。
        let cmdKeys = events |> List.flatMap(World.eventToCmds) |> List.map(World.cmdKey);
        let cmdGolden =
            ("SetHp", 1000001, 0, 0) ::
            ("Dying", 1000001, 0, 0) ::
            ("SetHp", 0, 10, 0) ::
            ("Progress", 0, 2, 34) :: Nil;
        // (b) fold→最終 World 射影が legacy と一致。
        let initW  = World.syncFromScene(sc, World.empty());
        let folded = List.foldLeft((w, ev) -> World.applyEventToWorld(ev, w), initW, events);
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w),
                         World.hpOf(EntityRef.Player(0), w),
                         World.progressOf(EntityRef.Player(0), w),
                         World.isDyingOf(EntityRef.Enemy(1), w));
        Assert.assertEq(
            expected = (cmdGolden, true, (Some(0), Some(10), Some((2, 34)), true)),
            (cmdKeys, proj(folded) == proj(legacyW), proj(folded)))

    /// (B) enemy effectRule を SimEvent で表した frozen オラクル。Damaged→Released→Afflicted。
    /// 新 variant Released（= ClearImmobilized）と Afflicted を含み、fold が legacy の hp/status へ収束する。
    @Test
    def testSimEventOracleEnemyEffectRule(): Unit \ Assert =
        let rule = ruleJson("{\"when\":\"onHit\",\"to\":\"enemy\",\"op\":\"spdDown\",\"amount\":3,\"for\":\"turns\",\"forTurns\":3}");
        let sc = sceneOf(player(0, 10, None, 80), enemy(1, 10, {x = 3, y = 2}, false, Some(0), rule, 200) :: Nil);
        let (_, _, legacyW) = runEnemyAttack(sc, 1);
        let spd = ({effect = StatusSystem.StatusEffect.SpdDown, magnitude = 3, remaining = 3}: StatusSystem.Status);
        let events =
            World.SimEvent.Damaged(EntityRef.Player(0), {newHp = 6, dmg = 4}) ::
            World.SimEvent.Released(EntityRef.Player(0)) ::
            World.SimEvent.Afflicted(EntityRef.Player(0), spd) :: Nil;
        let cmdKeys = events |> List.flatMap(World.eventToCmds) |> List.map(World.cmdKey);
        // ここでは legacy（fixture B）と完全一致（double-write 無し）＝frozen 列 == legacy の cmdKeys。
        let cmdGolden =
            ("SetHp", 0, 6, 0) ::
            ("ClrImmob", 0, 0, 0) ::
            ("Add", 0, 1, 3) :: Nil;
        let initW  = World.syncFromScene(sc, World.empty());
        let folded = List.foldLeft((w, ev) -> World.applyEventToWorld(ev, w), initW, events);
        let proj = w -> (World.hpOf(EntityRef.Player(0), w),
                         World.statusEffectsOf(EntityRef.Player(0), w)
                            |> List.map(s -> (s#effect, s#magnitude, s#remaining)));
        Assert.assertEq(
            expected = (cmdGolden, true, (Some(6), (StatusSystem.StatusEffect.SpdDown, 3, 3) :: Nil)),
            (cmdKeys, proj(folded) == proj(legacyW), proj(folded)))
}
