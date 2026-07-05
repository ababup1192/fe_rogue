// slice `golden-trace` のテスト（CORE/PARTIAL オラクル）。
//
// live combat orchestrator（Cmd を emit する PUBLIC seam）を固定 seed で駆動し、
// その決定論的な **Cmd-stream（cmdKey 列）+ 最終 World** を golden literal として凍結する。
// これが `resolveCombat → (World, [SimEvent])`（純 sim）が再現すべきオラクルになる（wrapper↔system 整合 pin）。
//
// 駆動は PUBLIC seam（applyAttackHit / applyEnemyAttackHit / onLungeDone）。private な
// resolveAttack/resolveEnemyAttack ではない。攻撃対象 id（attackTarget）は driver が **World.attackTarget**
// から読む。ハーネス `withTracedWorld` は scene を `syncFromScene` で seed するため、fixture の
// attackTargetId は World.attackTarget へ mirror され driver に届く（World 直 seed 版の等価は
// testGoldenAttackTargetWorldSeedMatchesScene が固定）。ハーネスは ONE worldRef を
// Command/WorldQuery/RngDraw で共有する ref-backed 3-handler で、combatViewOf の read-after-write を壊さない。
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
        facing            = Dir4.Down,
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

    /// ダミー sprite（指輪/武器の戦闘ロジックに無関係）。
    def fxSprite(): Sprite.SpriteResource = {
        texture = "test-texture", hframes = 1, vframes = 1, frame = 0,
        offset = {x = 0.0, y = 0.0}, scale = {x = 1.0, y = 1.0}, flipForFacing = false
    }

    /// テスト用 RingResource。finisher/lifesteal の `effect`/`power` だけが戦闘に効く。
    def testRing(effect: Ring.RingEffect, power: Int32): Ring.RingResource = {
        name = "test-ring", effect = effect, power = power, weight = 0.4,
        sprite = fxSprite(), description = "", effectRule = None
    }

    /// effect 武器（lifesteal/knockback/thief）を 1 本だけ持つテスト用 WeaponResource。常時命中・必殺なし。
    def fxWeapon(effect: WeaponCatalog.WeaponEffect, effectValue: Int32): UnitCatalog.WeaponResource =
        ({hit = 200, crit = 0, effect = effect, effectValue = effectValue | testWeapon()}: UnitCatalog.WeaponResource)

    /// w0=syncFromScene → resolveAttack(player0 → enemy1) を seed() の seeded PRNG で駆動し
    /// (最終 World, event 数) を返す共通ドライバ（B4 等価テスト群の定型 thunk）。
    def driveResolve(sc: Scene[NodeTag]): (World, Int32) =
        let w0 = World.syncFromScene(sc, World.empty());
        region rc {
            let (w, evs) = TestUnitFixtures.withSeededRng(rc, seed(), () ->
                CombatSystem.resolveAttack(w0, {ref = EntityRef.Player(0), level = 1}, {ref = EntityRef.Enemy(1), level = 1}));
            (w, List.length(evs))
        }

    /// ViewFx(Thief(cell)) の cell を Eq 可能な (x,y) 列へ射影（driveResolveEvs は既存・view-script 節で定義）。
    def thiefCellsT(events: List[World.SimEvent]): List[(Int32, Int32)] =
        events |> List.filterMap(ev -> match ev {
            case World.SimEvent.ViewFx(World.ViewFxKind.Thief(c)) => Some((c#x, c#y))
            case _                                                => None
        })

    /// posOf を Eq 可能な (x,y) タプルへ射影（record は Eq 非自動）。
    def posT(ref: EntityRef, w: World): Option[(Int32, Int32)] =
        World.posOf(ref, w) |> Option.map(p -> (p#x, p#y))

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
                CombatDriver.applyAttackHit(0, sc)))))))))
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
                CombatDriver.applyAttackHit(0, sc)))))))))
        }

    /// applyAttackHit を **World 直 seed** harness で駆動（scene には attackTarget を持たせず、
    /// `seedCmds` で World.attackTarget を直接 seed する）。runAttack と同一のモック stack ＋ seed 以外は同条件。
    /// golden ハーネス脱 scene の第一歩＝attackTarget store を scene Data でなく World store で seed する。
    def runAttackWorldSeeded(sc: Scene[NodeTag], seedCmds: List[World.Cmd]):
            (Scene[NodeTag], List[(String, Int32, Int32, Int32)], World) =
        region rc {
            TestUnitFixtures.withTracedWorldSeeded(rc, seed(), sc, seedCmds, () ->
            TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(sc), () ->
            TestUnitFixtures.withNoopThiefDrop(() ->
            TestUnitFixtures.withMockGame(() ->
            TestUnitFixtures.withMockAudio(() ->
            TestUnitFixtures.withMockGameLogger(() ->
            TestUnitFixtures.withNoopAnim(() ->
            TestUnitFixtures.withNoopTween(() ->
                CombatDriver.applyAttackHit(0, sc)))))))))
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
                CombatDriver.applyEnemyAttackHit(enemyId, sc)))))))))
        }

    // combatViewOf が attacker/defender 両方で Some か（vacuous scene-fallback の pre-guard）。
    def viewSome(ref: EntityRef, sc: Scene[NodeTag]): Bool =
        Option.nonEmpty(World.combatViewOf(ref, World.syncFromScene(sc, World.empty())))

    /// anti-vacuity 前提その①: 両駒の combatViewOf が Some＝scene が World combatView を解決できる
    /// （scene-fallback で素通りしていない）。等価テスト・golden テスト共通の前提。
    def assertViewsResolvable(sc: Scene[NodeTag]): Unit \ Assert =
        Assert.assertEq(expected = true, viewSome(EntityRef.Player(0), sc) and viewSome(EntityRef.Enemy(1), sc))

    /// 等価テストの anti-vacuity 前提（① views 解決可能 ② sim が非空 event を出した）を 1 行に集約する。
    /// これを各テスト冒頭で呼ぶと、残るアサートは「legacy と何が一致するか」だけになる。
    def assertNonVacuous(sc: Scene[NodeTag], evCount: Int32): Unit \ Assert =
        assertViewsResolvable(sc);
        Assert.assertEq(expected = true, evCount > 0)

    /// golden cmd-stream テストの前提（① views 解決可能 ② legacy seam が非空 Cmd を emit）を 1 行に集約する。
    def assertGoldenPremise(sc: Scene[NodeTag], keys: List[(String, Int32, Int32, Int32)]): Unit \ Assert =
        assertViewsResolvable(sc);
        Assert.assertEq(expected = true, not List.isEmpty(keys))

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
        assertGoldenPremise(sc, keys);
        // golden: P6-5a で **ECS 経路（applyAttackHit=live）** の cmd-stream に再凍結（GENERATE-THEN-FREEZE）。
        // 前半 = eventToCmds（sim event の写像: 撃破 SetHp/Dying → level-up の SetHp/Progress）、
        // 後半 = applyEcsSceneEffects/startDeathAnimation の scene 副作用 co-emit
        //（Dying は seam と death-anim の二重 emit＝冪等・SetBaseStats/SetGrowth は resource 成長の束ね）。
        let golden =
            ("SetHp", 1000001, 0, 0) ::
            ("Dying", 1000001, 0, 0) ::
            ("SetHp", 0, 10, 0) ::
            ("Progress", 0, 2, 34) ::
            ("SetHp", 1000001, 0, 0) ::
            ("Dying", 1000001, 0, 0) ::
            ("SetBaseStats", 0, 21, 10) ::
            ("SetGrowth", 0, 10, 0) ::
            ("SetWeapons", 0, 1, 0) ::
            ("SetWeaponView", 0, 2, 0) :: Nil;  // S2.4: 武器耐久消費に 1:1 co-emit（attack=2）
        Assert.assertEq(expected = golden, keys);
        // 最終 World: enemy hp=0 / player hp=10（growthRates=0 ゆえ増分なし）/ progress=(Lv2, exp34)。
        Assert.assertEq(
            expected = (Some(0), Some(10), Some((2, 34))),
            (World.hpOf(EntityRef.Enemy(1), w),
             World.hpOf(EntityRef.Player(0), w),
             World.progressOf(EntityRef.Player(0), w)))

    // ── (A2) NO-LEVEL-UP path ─────────────────────────────────────────────────

    /// 同一フィクスチャだが exp=0 ゆえ撃破しても閾値を跨がない → legacy は bare SetProgress@975 を emit
    /// （SetHp(player) なし・growth roll なし）。これが ExpGained がマップする real legacy emission。
    /// cmd-stream: SetHp(enemy,0) → SetHp(enemy,0)+Dying(enemy)[startDeathAnimation] → bare Progress(player, lv1, exp35)。
    @Test
    def testGoldenNoLevelUp(): Unit \ Assert =
        let sc = sceneOf(player(0, 10, Some(1), 200), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, keys, w) = runAttack(sc);
        assertGoldenPremise(sc, keys);
        // golden: P6-5a で ECS 経路に再凍結。撃破するが閾値を跨がず→ bare Progress（SetHp(player)/growth なし）。
        let golden =
            ("SetHp", 1000001, 0, 0) ::
            ("Dying", 1000001, 0, 0) ::
            ("Progress", 0, 1, 35) ::
            ("SetHp", 1000001, 0, 0) ::
            ("Dying", 1000001, 0, 0) ::
            ("SetWeapons", 0, 1, 0) ::
            ("SetWeaponView", 0, 2, 0) :: Nil;  // S2.4: 武器耐久消費に 1:1 co-emit（attack=2）
        Assert.assertEq(expected = golden, keys);
        // 最終 World: enemy hp=0 / player hp=10（被弾なし）/ progress=(Lv1, exp35)。
        Assert.assertEq(
            expected = (Some(0), Some(10), Some((1, 35))),
            (World.hpOf(EntityRef.Enemy(1), w),
             World.hpOf(EntityRef.Player(0), w),
             World.progressOf(EntityRef.Player(0), w)))

    // ── S2: attackTarget の World-authority 証明（脱 scene seed 第一歩）──────────────
    //
    // driver（applyAttackHit）は攻撃対象 id を **World.attackTarget** から読む。ここでそれを、
    // 「scene に attackTarget を持たせた旧 seed」と「scene には持たせず World.attackTarget を Cmd で
    // 直 seed した新 seed」が **同一の golden cmd-stream + 最終 World** を出すことで証明する
    // （並走 → 一致 assert）。旧経路（sceneOf の attackTargetId seed）は他 golden が使うため据え置き、
    // ここは新旧同値の gate だけを固定する。golden literal は不変。

    /// 旧 seed（scene attackTargetId=Some(1)）と 新 seed（scene=None・World.attackTarget を SetAttackTarget で
    /// 直 seed）が、同 fixture・同 seed で bit-identical な cmd-stream と最終 World 射影を出す。
    /// ⇒ driver は attackTarget を scene Data でなく World store から読む（S2 flip の証明）。
    @Test
    def testGoldenAttackTargetWorldSeedMatchesScene(): Unit \ Assert =
        // 旧 seed: attackTargetId を SCENE に持たせる（syncFromScene が World.attackTarget へ mirror）。
        let scScene = sceneOf(player(0, 10, Some(1), 200), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, keysScene, wScene) = runAttack(scScene);
        // 新 seed: scene player の attackTargetId=None・World.attackTarget を Cmd で直 seed する。
        let scWorld = sceneOf(player(0, 10, None, 200), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let seedCmds = World.Cmd.SetAttackTarget(EntityRef.Player(0), 1) :: Nil;
        let (_, keysWorld, wWorld) = runAttackWorldSeeded(scWorld, seedCmds);
        assertGoldenPremise(scScene, keysScene);
        // 一致①: cmd-stream が新旧 bit-identical（seed 経路に依らず同一トレース）。
        Assert.assertEq(expected = keysScene, keysWorld);
        // 一致②: 最終 World 射影（enemy hp / player hp / progress）も新旧一致。
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w),
                         World.hpOf(EntityRef.Player(0), w),
                         World.progressOf(EntityRef.Player(0), w));
        Assert.assertEq(expected = proj(wScene), proj(wWorld));
        // 独立 pin: 新 seed は scene に attackTarget を持たないのに撃破まで到達（＝World seed が効いた・
        // scene fallback で素通りした vacuous でないことを保証）。
        Assert.assertEq(expected = Some(0), World.hpOf(EntityRef.Enemy(1), wWorld))

    // ── Phase C 等価: resolveCombat 本体 が legacy と final-World 等価か ───────────

    /// 撃破 path の最終 World 射影（enemy hp / player hp / progress）。legacy と sim の両 World に適用して比較する。
    def killProj(w: World): (Option[Int32], Option[Int32], Option[(Int32, Int32)]) =
        (World.hpOf(EntityRef.Enemy(1), w),
         World.hpOf(EntityRef.Player(0), w),
         World.progressOf(EntityRef.Player(0), w))

    /// ②検証: `CombatSystem.resolveAttack`（新 sim・(World,[SimEvent]) を返す）を A2 と同じ fixture・同 seed で
    /// 駆動し、legacy `runAttack`（applyAttackHit）の最終 World と **直接一致**するか（enemy hp/player hp/progress）。
    /// no-level-up path は draw 順（crit/thief は crit率0・noopThief で outcome 不変）の影響を受けないので、
    /// hit ロール 1 本で legacy と等価になる。これが cutover の final-World 安全網の最小単位。
    @Test
    def testResolveCombatEqualsSimNoLevelUp(): Unit \ Assert =
        let sc = sceneOf(player(0, 10, Some(1), 200), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evCount) = driveResolve(sc);
        assertNonVacuous(sc, evCount);
        // 等価: 撃破 path の (enemy hp, player hp, progress) が オラクルと一致。
        Assert.assertEq(expected = killProj(oracleW), killProj(sysW))

    /// B5: level-up path も legacy 等価か。A fixture（player exp=99 → 撃破で 100 跨ぎ→ Lv2/exp34）。
    /// growthRates=0 ゆえ hit→growth(spike) と hit→crit→thief→growth(legacy) の draw 順差は最終 World に効かない
    /// 範囲（成長が起きない）で legacy 凍結 World に一致する（その制約は CombatSystem header の ☐ に明記）。
    @Test
    def testResolveCombatEqualsSimLevelUp(): Unit \ Assert =
        let sc = sceneOf(player(99, 10, Some(1), 200), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evCount) = driveResolve(sc);
        assertNonVacuous(sc, evCount);
        // 等価: 撃破＋level-up（Lv2/exp34/hp10）の (enemy hp, player hp, progress) が オラクルと一致。
        Assert.assertEq(expected = killProj(oracleW), killProj(sysW))

    /// B1 を pin: **overkill**（enemy hp=3 を dmg=4 で撃破→ strike#newHp=-1）でも、CombatSystem の clamp で
    /// 最終 enemy hp=0 になり legacy（startDeathAnimation の hard 0）と一致する。clamp が無ければ resolveAttack は
    /// -1 を残し legacy の 0 と乖離してこのテストが落ちる＝clamp の divergence 防止価値を回帰固定する。
    @Test
    def testResolveCombatEqualsSimOverkill(): Unit \ Assert =
        let sc = sceneOf(player(0, 10, Some(1), 200), enemy(1, 3, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evCount) = driveResolve(sc);
        assertNonVacuous(sc, evCount);
        // 等価: overkill（hp3 を dmg4）でも enemy hp が オラクルと一致。
        Assert.assertEq(expected = World.hpOf(EntityRef.Enemy(1), oracleW), World.hpOf(EntityRef.Enemy(1), sysW));
        // 独立 pin: clamp が効き strike#newHp=-1 でなく 0 に落ちる（clamp が無ければ -1 残りでここが落ちる）。
        Assert.assertEq(expected = Some(0), World.hpOf(EntityRef.Enemy(1), sysW))

    /// draw 順整合の証明: **growthRates>0（roll-sensitive な hp=50）** の level-up で resolveAttack の最終 hp が
    /// オラクルと一致する。crit/thief draw を入れたことで growth draw が legacy と同位置（position 4+）に揃い、
    /// 同 seed で同じ成長ロールを引く＝同じ hp 成長になる。旧実装（hit のみ 1 draw）なら growth が position 2 で
    /// 引かれ legacy(position 4) とロールがずれ、この roll-sensitive fixture で乖離していた（＝本テストが整合を pin）。
    @Test
    def testResolveCombatEqualsSimLevelUpRollSensitive(): Unit \ Assert =
        let bp = player(99, 10, Some(1), 200);
        let gp = {resource = {growthRates = {hp = 50 | UnitCatalog.zeroGrowthRates()} | bp#resource} | bp};
        let sc = sceneOf(gp, enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evCount) = driveResolve(sc);
        assertNonVacuous(sc, evCount);
        // 等価: roll-sensitive な成長(hp=50)でも (player hp, progress) が オラクルと一致＝growth draw が同位置で引かれる証明。
        let proj = w -> (World.hpOf(EntityRef.Player(0), w), World.progressOf(EntityRef.Player(0), w));
        Assert.assertEq(expected = proj(oracleW), proj(sysW))

    /// 非撃破 path 等価: enemy hp=20 を dmg4 で攻撃→生存。hp 更新 + **SetAlerted(true)** + releaseBind が
    /// オラクルと一致する（resolveAttack の非撃破分岐が Alerted/Released を emit する。emit 漏れなら alerted が
    /// false のままで legacy(true) と乖離して落ちる）。
    @Test
    def testResolveCombatEqualsSimNonKill(): Unit \ Assert =
        let sc = sceneOf(player(0, 10, Some(1), 200), enemy(1, 20, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evCount) = driveResolve(sc);
        assertNonVacuous(sc, evCount);
        // 等価: 非撃破での (enemy hp, alerted, progress) が オラクルと一致。progress を含めるのが要点
        // ＝命中 EXP（B1 hit-exp 漏れ）を検出する。alerted を含めるのは SetAlerted emit を legacy にピンするため。
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w),
                         World.alertedOf(EntityRef.Enemy(1), w),
                         World.progressOf(EntityRef.Player(0), w));
        Assert.assertEq(expected = proj(oracleW), proj(sysW))

    /// crit path 等価: crit=100 武器で必ず必殺。base ダメージ4 では enemy hp=10 を撃破できないが、必殺3倍=12 で
    /// 撃破する＝crit が「非撃破→撃破」「hit exp→kill exp」を変える。resolveAttack の applyCrit + crit-kill exp 再計算が
    /// オラクルと一致するか（applyCrit を実際に通す唯一のテスト）。
    @Test
    def testResolveCombatEqualsSimCrit(): Unit \ Assert =
        let critWeapon = ({hit = 200, crit = 100 | testWeapon()}: UnitCatalog.WeaponResource);
        let bp = player(0, 10, Some(1), 200);
        let critP = {weapons = critWeapon :: Nil | bp};
        let sc = sceneOf(critP, enemy(1, 10, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evCount) = driveResolve(sc);
        assertNonVacuous(sc, evCount);
        // 等価: crit が「非撃破→撃破」「hit exp→kill exp」へ反転させた結果の (enemy hp, progress) が オラクルと一致。
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w), World.progressOf(EntityRef.Player(0), w));
        Assert.assertEq(expected = proj(oracleW), proj(sysW));
        // 独立 pin: crit が確かに撃破へ反転した（敵 hp10→0・base dmg4 では到達不能）＝applyCrit no-op を検出する。
        Assert.assertEq(expected = Some(0), World.hpOf(EntityRef.Enemy(1), sysW))

    /// Released(=releaseBind/ClearImmobilized) を pin: かなしばり中の enemy を非撃破で攻撃すると immobilize が
    /// 解除される。w0 は immobilize あり（非空）、攻撃後は sysW/oracleW とも空＝resolveAttack の Released emit を固定。
    @Test
    def testResolveCombatEqualsSimReleasesImmobilize(): Unit \ Assert =
        let e  = {statuses = StatusSystem.immobilizeFor(3) :: Nil
                   | enemy(1, 20, {x = 3, y = 2}, false, None, ruleJson(""), 80)};
        let sc = sceneOf(player(0, 10, Some(1), 200), e :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let w0 = World.syncFromScene(sc, World.empty());
        let (sysW, evCount) = driveResolve(sc);
        assertNonVacuous(sc, evCount);
        let immobilized = w -> not List.isEmpty(World.statusEffectsOf(EntityRef.Enemy(1), w));
        // 前提: 攻撃前の enemy はかなしばり中（status 非空）。
        Assert.assertEq(expected = true, immobilized(w0));
        // 等価: 非撃破攻撃で Released が発火し、sim/legacy とも解除される。
        Assert.assertEq(expected = immobilized(oracleW), immobilized(sysW));
        // 独立 pin: 攻撃後の sim は確かに解除済み（status 空）。
        Assert.assertEq(expected = false, immobilized(sysW))

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
        assertViewsResolvable(sc);
        // SEEDED（hitRoll=13<30）＝命中→撃破の golden cmd-stream（A2 と同形・今回は roll 依存で命中。P6-5a: ECS 経路）。
        let golden =
            ("SetHp", 1000001, 0, 0) ::
            ("Dying", 1000001, 0, 0) ::
            ("Progress", 0, 1, 35) ::
            ("SetHp", 1000001, 0, 0) ::
            ("Dying", 1000001, 0, 0) ::
            ("SetWeapons", 0, 1, 0) ::
            ("SetWeaponView", 0, 2, 0) :: Nil;  // S2.4: 武器耐久消費に 1:1 co-emit（attack=2）
        Assert.assertEq(expected = golden, seededKeys);
        // CONSTANT-50（50<30=false ⇒ 回避）でも D3 で武器耐久は消費される（命中/回避とも毎攻撃で消費＝
        // sim 非依存の scene 副作用）ので SetWeapons だけが出る（hp/dying/progress は不変＝撃破しない）。
        Assert.assertEq(expected = ("SetWeapons", 0, 1, 0) :: ("SetWeaponView", 0, 2, 0) :: Nil, constKeys);
        // ∴ 定数生成器では golden を再現できない＝この fixture の cmd-stream は draw 列に依存する。
        Assert.assertEq(expected = true, seededKeys != constKeys)

    // ── (B) ENEMY effectRule subtrace ─────────────────────────────────────────

    /// effectRule(spdDown を player へ・chance 既定100=必発) を持つ敵が applyEnemyAttackHit を駆動。
    /// roll [hit, crit, effect] を引き、命中で味方 HP を 4 削り（10→6・撃破せず）spdDown を付与。
    /// cmd-stream: SetHp(player,6) → Seed(player)[releaseBind の post-mutation 全置換] → Cmd.Add(player, SpdDown ordinal=1)
    /// → Seed(player)[effectStatus leaf の post-mutation 全置換]。S3 で releaseBind の ClrImmob と status leaf が Seed 化。
    @Test
    def testGoldenEnemyEffectRule(): Unit \ Assert =
        let rule = ruleJson("{\"when\":\"onHit\",\"to\":\"enemy\",\"op\":\"spdDown\",\"amount\":3,\"for\":\"turns\",\"forTurns\":3}");
        let sc = sceneOf(player(0, 10, None, 80), enemy(1, 10, {x = 3, y = 2}, false, Some(0), rule, 200) :: Nil);
        let ((_, killed), keys, w) = runEnemyAttack(sc, 1);
        assertGoldenPremise(sc, keys);
        // golden: P6-5a で ECS 経路に再凍結。SetHp(player,6)→ClrImmob(被弾でかなしばり解除)
        // →Add（magnitude=3・kind=1=SpdDown）→Seed×2（status の scene 権威 mirror）。
        // 敵武器の耐久 co-emit は ECS 経路では敵側 seam が担わない（legacy 固有の emit だった）。
        let golden =
            ("SetHp", 0, 6, 0) ::
            ("ClrImmob", 0, 0, 0) ::
            ("Add", 0, 1, 3) ::
            ("Seed", 0, 0, 0) ::
            ("Seed", 0, 0, 0) :: Nil;
        Assert.assertEq(expected = golden, keys);
        // 撃破せず（killed 戻り値が空）。
        Assert.assertEq(expected = true, List.isEmpty(killed));
        // 最終 World: 味方 hp=6・付与 status を FULL 射影（effect/magnitude/remaining）で凍結。
        // 量や残ターンが違えば落ちる＝kind 一致だけでは素通りさせない。
        let statusProj =
            World.statusEffectsOf(EntityRef.Player(0), w)
                |> List.map(s -> (s#effect, s#magnitude, s#remaining));
        Assert.assertEq(
            expected = (Some(6), (StatusSystem.StatusEffect.SpdDown, 3, 3) :: Nil),
            (World.hpOf(EntityRef.Player(0), w), statusProj))

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
                TestUnitFixtures.withCursor(() ->
                    run {
                        TestUnitFixtures.withPhaseRef(rc, TurnPhase.Phase.PlayerAttackHold, () ->
                            CombatDriver.onLungeDone(Faction.Player, 0, sc))
                    } with Pacing.withState(rc)))))))))))));
            assertGoldenPremise(sc, keys);
            // golden: 追撃分岐 OFF（plain weapon）→ ClrTgt(player) のみ。
            let golden = ("ClrTgt", 0, 0, 0) :: Nil;
            Assert.assertEq(expected = golden, keys);
            // 最終 Phase は PlayerAttackHold（decideView→Kill）。
            Assert.assertEq(expected = TurnPhase.Phase.PlayerAttackHold, finalPhase)
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
                TestUnitFixtures.withCursor(() ->
                    run {
                        TestUnitFixtures.withPhaseRef(rc, TurnPhase.Phase.PlayerAttackHold, () -> {
                            let s1 = CombatDriver.onLungeDone(Faction.Player, 0, sc);
                            CombatDriver.applyEnemyAttackHit(1, s1)
                        })
                    } with Pacing.withState(rc)))))))))))));
            let (_, killed) = result;
            assertGoldenPremise(sc, keys);
            // golden: P6-5a で ECS 経路に再凍結。ClrTgt(player)→AtkTgt(enemy1,player0)
            // →SetHp(player,0)→ClrImmob(被弾でかなしばり解除・sim event)→Seed(status mirror)。
            // 敵武器の耐久 co-emit は ECS 敵 seam では出ない（legacy 固有だった）。
            let golden =
                ("ClrTgt", 0, 0, 0) ::
                ("AtkTgt", 1000001, 0, 0) ::
                ("SetHp", 0, 0, 0) ::
                ("ClrImmob", 0, 0, 0) ::
                ("Seed", 0, 0, 0) :: Nil;
            Assert.assertEq(expected = golden, keys);
            // 最終 World: 敵反撃が味方(hp4)を撃破→ player hp=0・killed=[0]。
            Assert.assertEq(
                expected = (Some(0), 0 :: Nil),
                (World.hpOf(EntityRef.Player(0), w), killed))
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
        // cmdKey 列が二度引きで bit-identical（決定論）。
        Assert.assertEq(expected = k1, k2);
        // 最終 World 射影も bit-identical。
        Assert.assertEq(expected = projOf(w1), projOf(w2))

    /// 隣接攻撃は駒を動かさない＝最終 World 由来の board が、独立に凍結した piece-list literal と一致する。
    /// P6-5c: boardMatchesScene（board-lock 契約 = scene pieces との突合）は退役（scene gridPos twin 撤去で
    /// live に scene 側 board が存在しない）。frozen literal pin のみ残す。
    @Test
    def testGoldenFinalBoardParity(): Unit \ Assert =
        let sc = sceneOf(player(99, 10, Some(1), 200), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, w) = runAttack(sc);
        // (faction, id, x, y): player(0)@{2,2}, enemy(1)@{3,2}（撃破しても pos は不変）。
        let goldenPieces = (0, 0, 2, 2) :: (1, 1, 3, 2) :: Nil;
        Assert.assertEq(expected = goldenPieces, World.boardKey(World.toBoard(w, sc)))

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
        let (_, _, oracleW) = runAttack(sc);
        let events =
            World.SimEvent.Damaged(EntityRef.Enemy(1), {newHp = 0, dmg = 4}) ::
            World.SimEvent.ViewFx(World.ViewFxKind.Died(EntityRef.Enemy(1))) ::
            World.SimEvent.Dying(EntityRef.Enemy(1)) ::
            World.SimEvent.LeveledUp({entity = EntityRef.Player(0),
                newLevel = 2, newExp = 34, newHp = 10, grownStats = LevelSystem.zeroStats(), result = dummyResult()}) :: Nil;
        // (a) [SimEvent]→cmdKey が CLEAN golden（敵 SetHp は 1 回＝legacy の startDeathAnimation 二重書きを畳む）に一致。
        let cmdKeys = events |> List.flatMap(World.eventToCmds) |> List.map(World.cmdKey);
        let cmdGolden =
            ("SetHp", 1000001, 0, 0) ::
            ("Dying", 1000001, 0, 0) ::
            ("SetHp", 0, 10, 0) ::
            ("Progress", 0, 2, 34) :: Nil;
        Assert.assertEq(expected = cmdGolden, cmdKeys);
        // (b) events を初期 World へ fold した最終射影が オラクルと一致（SimEvent オラクル ≡ legacy オラクル）。
        let initW  = World.syncFromScene(sc, World.empty());
        let folded = List.foldLeft((w, ev) -> World.applyEventToWorld(ev, w), initW, events);
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w),
                         World.hpOf(EntityRef.Player(0), w),
                         World.progressOf(EntityRef.Player(0), w),
                         World.isDyingOf(EntityRef.Enemy(1), w));
        Assert.assertEq(expected = proj(oracleW), proj(folded));
        // 独立 pin: enemy hp=0 / player hp=10 / progress=(Lv2, exp34) / enemy dying。
        Assert.assertEq(expected = (Some(0), Some(10), Some((2, 34)), true), proj(folded))

    /// (B) enemy effectRule を SimEvent で表した frozen オラクル。Damaged→Released→Afflicted。
    /// 新 variant Released（= ClearImmobilized）と Afflicted を含み、fold が legacy の hp/status へ収束する。
    @Test
    def testSimEventOracleEnemyEffectRule(): Unit \ Assert =
        let rule = ruleJson("{\"when\":\"onHit\",\"to\":\"enemy\",\"op\":\"spdDown\",\"amount\":3,\"for\":\"turns\",\"forTurns\":3}");
        let sc = sceneOf(player(0, 10, None, 80), enemy(1, 10, {x = 3, y = 2}, false, Some(0), rule, 200) :: Nil);
        let (_, _, oracleW) = runEnemyAttack(sc, 1);
        let spd = ({effect = StatusSystem.StatusEffect.SpdDown, magnitude = 3, remaining = 3}: StatusSystem.Status);
        let events =
            World.SimEvent.Damaged(EntityRef.Player(0), {newHp = 6, dmg = 4}) ::
            World.SimEvent.Released(EntityRef.Player(0)) ::
            World.SimEvent.Afflicted(EntityRef.Player(0), spd) :: Nil;
        // (a) [SimEvent]→cmdKey が golden（fixture B と完全一致・double-write なし）に一致。
        let cmdKeys = events |> List.flatMap(World.eventToCmds) |> List.map(World.cmdKey);
        let cmdGolden =
            ("SetHp", 0, 6, 0) ::
            ("ClrImmob", 0, 0, 0) ::
            ("Add", 0, 1, 3) :: Nil;
        Assert.assertEq(expected = cmdGolden, cmdKeys);
        // (b) fold した最終射影が オラクルと一致（hp/status へ収束）。
        let initW  = World.syncFromScene(sc, World.empty());
        let folded = List.foldLeft((w, ev) -> World.applyEventToWorld(ev, w), initW, events);
        let proj = w -> (World.hpOf(EntityRef.Player(0), w),
                         World.statusEffectsOf(EntityRef.Player(0), w)
                            |> List.map(s -> (s#effect, s#magnitude, s#remaining)));
        Assert.assertEq(expected = proj(oracleW), proj(folded));
        // 独立 pin: player hp=6 / spdDown(mag3, rem3)。
        Assert.assertEq(expected = (Some(6), (StatusSystem.StatusEffect.SpdDown, 3, 3) :: Nil), proj(folded))

    // ── P1a: プレイヤー finisher（死神のネックレス）kill-flip 等価 ──────────────────
    //
    // NON-VACUOUS fixture: 敵 defense=8 で base ダメージ 0（base では撃破不能）・敵 hp4/maxHp10（40%≦50% 閾値）・
    // プレイヤー crit=0（stray crit が finisher を覆い隠さない）。kill-flip が ring 起因であることを、
    // ring 有り（確殺）と ring 無し（生存）の 2 テストに分けて証明する。

    /// defense=8 の硬い敵（base ダメージ 0 ＝ base では撃破不能）・hp4/maxHp10（瀕死 40%）。finisher fixture 共通敵。
    def finisherEnemy(): EnemyScene.Data =
        let e0 = enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80);
        {resource = {defense = 8 | e0#resource} | e0}

    /// (A) Ring{Finisher,50} 装備 → finisher が硬い敵を確殺。撃破後の (enemy hp, progress) が オラクルと一致。
    @Test
    def testResolveCombatFinisherKillsWithRing(): Unit \ Assert =
        let fp = {rings = testRing(Ring.RingEffect.Finisher, 50) :: Nil, ringEquipped = true | player(0, 10, Some(1), 200)};
        let sc = sceneOf(fp, finisherEnemy() :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evCount) = driveResolve(sc);
        assertNonVacuous(sc, evCount);
        // 等価: finisher 確殺後の (enemy hp, progress) が オラクルと一致。
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w), World.progressOf(EntityRef.Player(0), w));
        Assert.assertEq(expected = proj(oracleW), proj(sysW));
        // 独立 pin: finisher が確かに撃破した（敵 hp=0）＝legacy/sim 同時 no-op で "Kills" が vacuous に通るのを防ぐ。
        Assert.assertEq(expected = Some(0), World.hpOf(EntityRef.Enemy(1), sysW))

    /// (B) CONTROL: 同じ硬い敵に ring 無しで攻撃 → base ダメージ 0 ゆえ enemy は生存。これにより (A) の kill が
    /// 「base strike でなく finisher」起因だと確定する（anti-vacuity gate）。
    @Test
    def testResolveCombatFinisherControlNoRingSurvives(): Unit \ Assert =
        let sc = sceneOf(player(0, 10, Some(1), 200), finisherEnemy() :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evCount) = driveResolve(sc);
        assertNonVacuous(sc, evCount);
        // 等価: ring 無しでは enemy hp が オラクルと一致。
        Assert.assertEq(expected = World.hpOf(EntityRef.Enemy(1), oracleW), World.hpOf(EntityRef.Enemy(1), sysW));
        // 独立 pin: base ダメージ 0 ゆえ enemy は生存（hp4 のまま）＝(A) の kill は finisher 起因。
        Assert.assertEq(expected = Some(4), World.hpOf(EntityRef.Enemy(1), sysW))

    // ── P1b: プレイヤー lifesteal（ring on-kill / weapon per-hit）二相 fold 等価 ─────

    /// (a) ring-lifesteal: hp5/maxHp10、Ring{Lifesteal,power=5}、敵 hp4→撃破→ +5 で hp10。
    @Test
    def testResolveCombatEqualsSimRingLifesteal(): Unit \ Assert =
        let bp = player(0, 5, Some(1), 200);
        let lp = {rings = testRing(Ring.RingEffect.Lifesteal, 5) :: Nil, ringEquipped = true | bp};
        let sc = sceneOf(lp, enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evC) = driveResolve(sc);
        assertNonVacuous(sc, evC);
        // 等価: 撃破時 ring-lifesteal 後の (player hp, enemy hp) が オラクルと一致。
        let proj = w -> (World.hpOf(EntityRef.Player(0), w), World.hpOf(EntityRef.Enemy(1), w));
        Assert.assertEq(expected = proj(oracleW), proj(sysW));
        // 独立 pin: +5 回復で hp5→10・敵は撃破（hp0）。
        Assert.assertEq(expected = (Some(10), Some(0)), proj(sysW))

    /// (b) weapon-lifesteal: hp5、血吸い weapon{Lifesteal,effectValue=50}、敵 hp20 survives、dmg4→ +2 で hp7。
    @Test
    def testResolveCombatEqualsSimWeaponLifesteal(): Unit \ Assert =
        let bp = player(0, 5, Some(1), 200);
        let lp = {weapons = fxWeapon(WeaponCatalog.WeaponEffect.Lifesteal, 50) :: Nil | bp};
        let sc = sceneOf(lp, enemy(1, 20, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evC) = driveResolve(sc);
        assertNonVacuous(sc, evC);
        // 等価: 非撃破での毎ヒット weapon-lifesteal 後の (player hp, enemy hp, alerted) が オラクルと一致。
        let proj = w -> (World.hpOf(EntityRef.Player(0), w), World.hpOf(EntityRef.Enemy(1), w),
                         World.alertedOf(EntityRef.Enemy(1), w));
        Assert.assertEq(expected = proj(oracleW), proj(sysW));
        // 独立 pin: dmg4 の 50% = +2 回復で hp5→7（敵 hp20 survives）。
        Assert.assertEq(expected = Some(7), World.hpOf(EntityRef.Player(0), sysW))

    /// (c) ring+weapon 両 lifesteal の emit 順: hp5/maxHp10、Ring{Lifesteal,5} AND 血吸い weapon{Lifesteal,50}、
    /// 敵 hp4→撃破。ring が hp5→10、その後 weapon が ORIGINAL hp5→7 を SetHp（last-write-wins）→最終 hp7。
    /// emit 順（ring→weapon）と「両者ともオリジナル hp 起点」を同時にピン留め。
    @Test
    def testResolveCombatBothLifestealEmitOrder(): Unit \ Assert =
        let bp = player(0, 5, Some(1), 200);
        let lp = {rings = testRing(Ring.RingEffect.Lifesteal, 5) :: Nil, ringEquipped = true,
                  weapons = fxWeapon(WeaponCatalog.WeaponEffect.Lifesteal, 50) :: Nil | bp};
        let sc = sceneOf(lp, enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evC) = driveResolve(sc);
        assertNonVacuous(sc, evC);
        // 等価: ring→weapon の emit 順（両者オリジナル hp5 起点・weapon が last-write）後の player hp が オラクルと一致。
        Assert.assertEq(expected = World.hpOf(EntityRef.Player(0), oracleW), World.hpOf(EntityRef.Player(0), sysW));
        // 独立 pin: ring(hp5→10)→weapon(original hp5→7・last-write)＝最終 hp7。
        Assert.assertEq(expected = Some(7), World.hpOf(EntityRef.Player(0), sysW))

    /// (d) ring-lifesteal + level-up: hp5/maxHp10、exp99（撃破で 100 跨ぎ Lv2）、growthRates#hp=100（必ず +1）、
    /// Ring{Lifesteal,5}。敵 hp4→撃破→ +5 で hp10、THEN level-up が **post-lifesteal hp(10)** に +1 = hp11。
    /// 二相 fold が必須な唯一の fixture（expEvents が pre-lifesteal `world` を読むと hp=6 になり FAIL する）。
    @Test
    def testResolveCombatRingLifestealLevelUp(): Unit \ Assert =
        let bp = player(99, 5, Some(1), 200);
        let gr = {resource = {growthRates = {hp = 100 | UnitCatalog.zeroGrowthRates()} | bp#resource},
                  rings = testRing(Ring.RingEffect.Lifesteal, 5) :: Nil, ringEquipped = true | bp};
        let sc = sceneOf(gr, enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evC) = driveResolve(sc);
        assertNonVacuous(sc, evC);
        // 等価: 二相 fold（lifesteal で hp10 → level-up が post-lifesteal hp に +1 = hp11）後の (player hp, progress) が オラクルと一致。
        let proj = w -> (World.hpOf(EntityRef.Player(0), w), World.progressOf(EntityRef.Player(0), w));
        Assert.assertEq(expected = proj(oracleW), proj(sysW));
        // 独立 pin: lifesteal で hp10 → post-lifesteal hp に +1 = hp11（二相 fold が必須な証拠：pre-lifesteal hp6 なら 7 になる）。
        Assert.assertEq(expected = Some(11), World.hpOf(EntityRef.Player(0), sysW))

    // ── P1-b: 盗人の剣は ViewFx(Thief) を emit（World 不変・drop は wrapper が引く）─────────────

    /// REAL に発火する thief weapon（rogue ゲート点火）で ViewFx(Thief(敵元セル)) が emit され、かつ World は
    /// draw 消費以外変わらないことを確認（ViewFx は World-identity）。プレイヤー description="ローグ"、
    /// thief weapon{ThiefDrop,effectValue=100}（roll<100 で必ず発火）、敵 hp20 survives（非撃破が発火条件）。
    /// isRogueOf は growth#name（=resource#description）由来ゆえ description="ローグ" で点火する。
    @Test
    def testResolveCombatThiefEmitsViewFx(): Unit \ Assert =
        let bp = player(0, 5, Some(1), 200);
        let tp = {resource = {description = "ローグ" | bp#resource},
                  weapons = fxWeapon(WeaponCatalog.WeaponEffect.ThiefDrop, 100) :: Nil | bp};
        let sc = sceneOf(tp, enemy(1, 20, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evC) = driveResolve(sc);
        assertNonVacuous(sc, evC);
        // P1-b: ViewFx(Thief(敵元セル{3,2})) がちょうど 1 つ emit される（drop 実体は wrapper の applyThiefDrop が引く）。
        Assert.assertEq(expected = (3, 2) :: Nil, thiefCellsT(driveResolveEvs(sc)));
        // 等価: thief 発火しても World 不変＝(enemy hp, player hp, alerted, progress) が全て オラクルと一致（draw 消費のみ）。
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w), World.hpOf(EntityRef.Player(0), w),
                         World.alertedOf(EntityRef.Enemy(1), w), World.progressOf(EntityRef.Player(0), w));
        Assert.assertEq(expected = proj(oracleW), proj(sysW))

    /// 非ローグ（description≠"ローグ"）は同じ thief weapon でも ViewFx(Thief) を emit しない（isRogueOf ゲート）。
    /// これが無いと isRogueOf を握り潰しても testResolveCombatThiefEmitsViewFx が緑のままになりうる（点火条件の負テスト）。
    @Test
    def testResolveCombatNonRogueNoThief(): Unit \ Assert =
        let bp = player(0, 5, Some(1), 200);
        let tp = {resource = {description = "せんし" | bp#resource},
                  weapons = fxWeapon(WeaponCatalog.WeaponEffect.ThiefDrop, 100) :: Nil | bp};
        let sc = sceneOf(tp, enemy(1, 20, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        Assert.assertEq(expected = (Nil: List[(Int32, Int32)]), thiefCellsT(driveResolveEvs(sc)))

    /// P1-b 出荷 seam: `applyAttackHit`（常時 ECS 経路）を記録 ThiefDrop + 記録ロガーで駆動し、
    /// wrapper の `applyThiefDrop` が実際に drop を敵元セル{3,2}へ 1 回引き、『…が アイテムを落とした』
    /// ログを 1 行出すことを pin する。
    /// applyThiefDrop を外す/events フィルタを壊す退行をここで捕捉する。
    def runEcsAttackRecThief(sc: Scene[NodeTag]): (List[(Int32, Int32)], List[String]) =
        region rc {
            let dropRef = Ref.fresh(rc, (Nil: List[(Int32, Int32)]));
            let logRef  = Ref.fresh(rc, (Nil: List[String]));
            let _ =
                TestUnitFixtures.withTracedWorld(rc, seed(), sc, () ->
                TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(sc), () ->
                TestUnitFixtures.withMockGame(() ->
                TestUnitFixtures.withMockAudio(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withNoopTween(() ->
                    run {
                        CombatDriver.applyAttackHit(0, sc)
                    } with handler CustomEffects.ThiefDropRequest {
                        def drop(cell, scene, k) = { Ref.put((cell#x, cell#y) :: Ref.get(dropRef), dropRef); k(scene) }
                    } with handler GameLogger.GameLogger {
                        def playerLog(s, k)   = { Ref.put(s :: Ref.get(logRef), logRef); k() }
                        def enemyLog(s, k)    = { Ref.put(s :: Ref.get(logRef), logRef); k() }
                        def gameOverLog(_, k) = k()
                        def endTurn(k)        = k()
                        def drainEntries(k)   = k(Nil)
                    }))))));
            (List.reverse(Ref.get(dropRef)), List.reverse(Ref.get(logRef)))
        }

    @Test
    def testEcsAttackThiefDropSeam(): Unit \ Assert =
        let bp = player(0, 5, Some(1), 200);
        let tp = {resource = {description = "ローグ" | bp#resource},
                  weapons = fxWeapon(WeaponCatalog.WeaponEffect.ThiefDrop, 100) :: Nil | bp};
        let sc = sceneOf(tp, enemy(1, 20, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (drops, logs) = runEcsAttackRecThief(sc);
        // drop が敵元セル{3,2}へちょうど 1 回。
        Assert.assertEq(expected = (3, 2) :: Nil, drops);
        // 『…が アイテムを落とした』ログがちょうど 1 行含まれる（敵名は fixture 依存ゆえ suffix で pin）。
        let dropLogs = List.filter(s -> String.endsWith(suffix = "が アイテムを落とした", s), logs);
        Assert.assertEq(expected = 1, List.length(dropLogs))

    // ── P1c: ノックバック（敵 survives → 敵 pos を Moved 経由）─────────────────────

    /// Knockback weapon{effectValue=2}、敵 hp20 survives、壁なし floor。敵{3,2}・プレイヤー{2,2}→ +x 方向に
    /// 2 マス押されて {5,2}。oracleW（snapTo→Cmd.Move）の最終 pos/hp と resolveAttack sysW を一致比較。
    @Test
    def testResolveCombatEqualsSimKnockback(): Unit \ Assert =
        let kp = {weapons = fxWeapon(WeaponCatalog.WeaponEffect.Knockback, 2) :: Nil | player(0, 10, Some(1), 200)};
        let sc = sceneOf(kp, enemy(1, 20, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evC) = driveResolve(sc);
        assertNonVacuous(sc, evC);
        // 等価: 敵生存→ +x に 2 マス押された後の (enemy pos, enemy hp) が オラクルと一致。
        let proj = w -> (posT(EntityRef.Enemy(1), w), World.hpOf(EntityRef.Enemy(1), w));
        Assert.assertEq(expected = proj(oracleW), proj(sysW));
        // 独立 pin: 敵{3,2}→{5,2} へ着地（壁なし floor・cap=2）。
        Assert.assertEq(expected = Some((5, 2)), posT(EntityRef.Enemy(1), sysW))

    /// crit + knockback の合成: crit=200 武器に Knockback effect、敵 hp20 を crit dmg12 で 8 まで削り survive →
    /// 押し流す。Damaged→Alerted→Released→knockback の順序を end-to-end でピン（hp/pos/alerted 一致）。
    @Test
    def testResolveCombatCritKnockback(): Unit \ Assert =
        let cw = ({hit = 200, crit = 200, effect = WeaponCatalog.WeaponEffect.Knockback, effectValue = 2 | testWeapon()}: UnitCatalog.WeaponResource);
        let kp = {weapons = cw :: Nil | player(0, 10, Some(1), 200)};
        let sc = sceneOf(kp, enemy(1, 20, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let (_, _, oracleW) = runAttack(sc);
        let (sysW, evC) = driveResolve(sc);
        assertNonVacuous(sc, evC);
        // 等価: crit dmg12 で hp8 に削り→押し流す（Damaged→Alerted→Released→knockback 順）後の (enemy hp, pos, alerted) が オラクルと一致。
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w), posT(EntityRef.Enemy(1), w),
                         World.alertedOf(EntityRef.Enemy(1), w));
        Assert.assertEq(expected = proj(oracleW), proj(sysW))

    // ── P2: 敵攻撃パス（敵→味方・deferred death・effectRule→Afflicted・level-up なし・KNOCKBACK-FREE）──

    /// w0=syncFromScene → resolveEnemyAttack(enemy1 → player0) を seed() で駆動し (最終 World, [SimEvent]) を返す
    /// 共通ドライバ。敵パス等価テスト群の定型 thunk（driveResolve のプレイヤー版）。
    def driveEnemyResolve(sc: Scene[NodeTag]): (World, List[World.SimEvent]) =
        let w0 = World.syncFromScene(sc, World.empty());
        region rc {
            TestUnitFixtures.withSeededRng(rc, seed(), () ->
                CombatSystem.resolveEnemyAttack(w0, {ref = EntityRef.Enemy(1), level = 1}, {ref = EntityRef.Player(0), level = 1}))
        }

    /// Status を Eq 可能な (effect, magnitude, remaining) タプル列へ射影（record は Eq 非自動）。
    def statusT(ref: EntityRef, w: World): List[(StatusSystem.StatusEffect, Int32, Int32)] =
        World.statusEffectsOf(ref, w) |> List.map(s -> (s#effect, s#magnitude, s#remaining))

    /// (a) StatusAt: fixture-B シーン再利用（味方 hp10、敵 hp10 weaponHit=200、spdDown onHit rule）。
    /// runEnemyAttack(legacy) と resolveEnemyAttack(sim) の最終 World（味方 hp + status 射影）を一致比較し、
    /// かつ sim の [SimEvent]→cmdKey 列が fixture-B golden [SetHp(player,6), ClrImmob(player), Add(player,SpdDown,3)]
    /// に一致（Damaged→Released→Afflicted。ViewFx→Nil。emitStatusAdds の StatusAt 写像を逐語固定）。
    @Test
    def testResolveEnemyCombatEqualsSimEffectRule(): Unit \ Assert =
        let rule = ruleJson("{\"when\":\"onHit\",\"to\":\"enemy\",\"op\":\"spdDown\",\"amount\":3,\"for\":\"turns\",\"forTurns\":3}");
        let sc = sceneOf(player(0, 10, None, 80), enemy(1, 10, {x = 3, y = 2}, false, Some(0), rule, 200) :: Nil);
        let (_, _, oracleW) = runEnemyAttack(sc, 1);
        let (sysW, evs) = driveEnemyResolve(sc);
        assertNonVacuous(sc, List.length(evs));
        // 等価: 命中で味方 hp10→6・spdDown 付与後の (player hp, status) が オラクルと一致。
        let proj = w -> (World.hpOf(EntityRef.Player(0), w), statusT(EntityRef.Player(0), w));
        Assert.assertEq(expected = proj(oracleW), proj(sysW));
        // cmd-stream: sim の [SimEvent]→cmdKey が fixture-B golden（Damaged→Released→Afflicted・ViewFx→Nil）に一致。
        let cmdKeys = evs |> List.flatMap(World.eventToCmds) |> List.map(World.cmdKey);
        let cmdGolden =
            ("SetHp", 0, 6, 0) ::
            ("ClrImmob", 0, 0, 0) ::
            ("Add", 0, 1, 3) :: Nil;
        Assert.assertEq(expected = cmdGolden, cmdKeys)

    /// (b) ImmobilizeAt: 敵 immobilize-onHit rule、味方 survives。sim/legacy の味方 status 射影を一致比較し、
    /// かつ非空（Immobilized present）を独立に固定。legacy にピン留め（self-derive しない）。
    @Test
    def testResolveEnemyImmobilize(): Unit \ Assert =
        let rule = ruleJson("{\"when\":\"onHit\",\"to\":\"enemy\",\"op\":\"immobilize\",\"for\":\"turns\",\"forTurns\":2}");
        let sc = sceneOf(player(0, 10, None, 80), enemy(1, 10, {x = 3, y = 2}, false, Some(0), rule, 200) :: Nil);
        let (_, _, oracleW) = runEnemyAttack(sc, 1);
        let (sysW, evs) = driveEnemyResolve(sc);
        assertNonVacuous(sc, List.length(evs));
        // 等価: 命中で immobilize 付与後の status が オラクルと一致。
        Assert.assertEq(expected = statusT(EntityRef.Player(0), oracleW), statusT(EntityRef.Player(0), sysW));
        // 独立 pin: status は非空＝Immobilized が確かに付与された。
        Assert.assertEq(expected = false, List.isEmpty(statusT(EntityRef.Player(0), sysW)))

    /// P1-c: 敵ノックバック（如意棒等・味方生存時）。敵{2,2}が Knockback 武器で味方{3,2}を殴り、味方を攻撃方向
    /// (+x) へ 2 マス押して {5,2}（player-attack 版 testResolveCombatEqualsSimKnockback と対称の幾何）。
    /// legacy applyEnemyAttackHit（applyEnemyKnockback→pushPlayerBack→snapTo）の最終 (player pos, hp) と
    /// resolveEnemyAttack sysW を一致比較し {5,2} を pin。faction-blind な knockbackEvents 再利用の証跡。
    /// （既存敵テストは KNOCKBACK-FREE な testWeapon を使う＝testTestWeaponKnockbackFree の不変条件は保つ。）
    @Test
    def testResolveEnemyKnockback(): Unit \ Assert =
        let kp = {gridPos = {x = 3, y = 2} | player(0, 10, None, 80)};       // 味方を敵の +x 隣へ
        let ke = {weapon = Some(fxWeapon(WeaponCatalog.WeaponEffect.Knockback, 2))
                  | enemy(1, 20, {x = 2, y = 2}, false, Some(0), ruleJson(""), 200)};
        let sc = sceneOf(kp, ke :: Nil);
        let (_, _, oracleW) = runEnemyAttack(sc, 1);
        let (sysW, evs) = driveEnemyResolve(sc);
        assertNonVacuous(sc, List.length(evs));
        // 等価: 味方生存→ +x に 2 マス押された後の (player pos, player hp) が オラクルと一致。
        let proj = w -> (posT(EntityRef.Player(0), w), World.hpOf(EntityRef.Player(0), w));
        Assert.assertEq(expected = proj(oracleW), proj(sysW));
        // 独立 pin: 味方{3,2}→{5,2}（壁なし floor・cap=2）。
        Assert.assertEq(expected = Some((5, 2)), posT(EntityRef.Player(0), sysW))

    /// (c) RAW no-clamp + killing-blow ClearImmobilized: 味方 hp2・かなしばり中、敵 weaponHit=200/crit=0 empty rule →
    /// newHp = 2 - dmg(4) = -2（OVERKILL・hard-0 clamp と区別可能）。撃破は deferred（ViewFx(Died)）で World hp は RAW -2、
    /// Released（無条件）が killing blow でかなしばりを解除する。sim/legacy 一致 + 独立リテラル Some(-2) でピン。
    @Test
    def testResolveEnemyOverkillsPlayer(): Unit \ Assert =
        let imP = {statuses = StatusSystem.immobilizeFor(3) :: Nil | player(0, 2, None, 80)};
        let sc  = sceneOf(imP, enemy(1, 10, {x = 3, y = 2}, false, Some(0), ruleJson(""), 200) :: Nil);
        let w0  = World.syncFromScene(sc, World.empty());
        let (_, _, oracleW) = runEnemyAttack(sc, 1);
        let (sysW, evs) = driveEnemyResolve(sc);
        assertNonVacuous(sc, List.length(evs));
        let cleared = w -> List.isEmpty(statusT(EntityRef.Player(0), w));
        // 前提: 攻撃前の味方はかなしばり中（status 非空）。
        Assert.assertEq(expected = false, cleared(w0));
        // 等価: RAW 被弾＋killing blow の無条件 Released 後の (player hp, かなしばり解除) が オラクルと一致。
        let proj = w -> (World.hpOf(EntityRef.Player(0), w), cleared(w));
        Assert.assertEq(expected = proj(oracleW), proj(sysW));
        // 独立 pin: clamp なし＝hp は RAW -2（hard-0 clamp と区別可能）。
        Assert.assertEq(expected = Some(-2), World.hpOf(EntityRef.Player(0), sysW))

    /// hp/heal op 検査用の dummy PlanCtx（敵 actor・rayUnits 1 体・dealt=4）。出荷 rule を planActions する土台。
    def dummyPlanCtx(): EffectPlan.PlanCtx =
        {selfId = 1, attackerId = 1, actorIsPlayer = false,
         rayUnits = ({id = 0, ally = true, immobilized = false, alive = true}: EffectRule.RayUnit) :: Nil,
         amount = {max = 10, dealt = 4, incoming = 0, magic = 0}}

    /// PlanItem が hp 系（heal/damage/maxHpUp/revive・heal は P2b へ deferred）か（ToString prefix で match 回避）。
    def isHpOrHealItem(item: EffectPlan.PlanItem): Bool =
        let s = "${item}";
        String.startsWith(prefix = "HealAt", s)
            or String.startsWith(prefix = "FullHealAt", s)
            or String.startsWith(prefix = "DamageAt", s)
            or String.startsWith(prefix = "MaxHpUpAt", s)
            or String.startsWith(prefix = "ReviveAt", s)

    /// (d) ガード: enemies.json が**実際に出荷する**全 effectRule のうち hit 契機（OnHit/OnAttack/OnKill）で
    /// 発火するものを実カタログから引き、その planActions が hp 系/heal item を含まないことをロックする。
    /// これにより将来 heal effectRule を出荷データへ足しても sim 経路を黙って迂回（divergence）できない＝
    /// P2b safety claim を出荷データそのもので担保する（ローカル fixture の rule 二つだけを見るのではない）。
    /// 併せて hit-rule を実データから最低 1 件拾えること（vacuous でない）もピン。
    /// （敵 weapon の KNOCKBACK-FREE 不変条件は `testTestWeaponKnockbackFree` が別途ロックする。）
    @Test
    def testEnemyEffectRuleNoHpOps(): Unit \ {Assert, Fs.FileRead} =
        let firesOnHit = t -> t == EffectRule.Trigger.OnHit
                           or t == EffectRule.Trigger.OnAttack
                           or t == EffectRule.Trigger.OnKill;
        let hitRules = EnemyCatalog.enemiesOf(EnemyCatalog.load())
            |> Map.toList
            |> List.filterMap(pair -> (snd(pair))#effectRule)   // effectRule を持つ敵だけ（Option[Json]）
            |> List.filterMap(EffectBridge.fromComposer)        // 生 Json → EffectRule
            |> List.filter(rule -> firesOnHit(rule#trigger));   // hit 契機のみ
        let anyHpOp = List.exists(
            rule -> List.exists(isHpOrHealItem, EffectPlan.planActions(rule, dummyPlanCtx())),
            hitRules);
        // 出荷 hit-rule の plan に hp/heal op が無い（将来 heal effectRule を出荷データへ足すとここで落ちる）。
        Assert.assertEq(expected = false, anyHpOp);
        // 実データから hit-rule を最低 1 件拾えた＝vacuous でない（ガードが実際に何かを検査している）。
        Assert.assertEq(expected = false, List.isEmpty(hitRules))

    /// fixture 健全性: テスト用 `testWeapon()` は Knockback 武器でない。多数の fixture が「敵ノックバックなし」を
    /// 暗黙の前提にするので、その不変条件を出荷 effectRule 検査とは分離して独立にロックする。
    @Test
    def testTestWeaponKnockbackFree(): Unit \ Assert =
        Assert.assertEq(
            expected = None,
            WeaponCatalog.knockbackTiles(testWeapon()#effect, testWeapon()#effectValue))

    // ── P3: counter チェーン合成（resolveAttack(player) THEN resolveEnemyAttack(enemy)）────────
    //
    // sim 側の純粋 COMPOSITION 検証（新 CombatSystem/World コードなし）。1 つの withSeededRng(seed()) の下で
    //   (w1,evs1)=resolveAttack(Player0→Enemy1);  (w2,_)=resolveEnemyAttack(Enemy1→Player0)
    // と畳み、w2 を **新しい合成 legacy oracle**（既存 golden D ではない＝D は敵 hp=10 を pre-set しプレイヤー
    // strike を OMIT する）と final-World 等価でピン留めする。oracle は ONE withTracedWorld(seed()) の下で
    //   s1=applyAttackHit(0,sc) → s2=onLungeDone(Player,0,s1) → applyEnemyAttackHit(1,s2)
    // の 3 seam を順に駆動する（World を共有 worldRef で累積）。
    //
    // PRNG framing は STREAM alignment ではなく VALUE-INDEPENDENCE: レガシー onLungeDone は sim が決して引かない
    // followUp roll を 1 本引くので PRNG stream はプレイヤー攻撃後に DIVERGE する。だがこの fixture は
    // weaponHit=200（常時命中・draw 非依存）/ crit=0（必殺なし・draw 非依存）/ effectRule なし / level-up なし
    // ＝引かれる全 outcome が値非依存ゆえ draw 位置差は World 射影を変えられない。non-brave weapon（testWeapon
    // ＝NoEffect）+ equal speed（両者 speed=3）で EffectFlow.followUpDecision を FAIL させ single strike にする。
    // 比較は hp/alerted/status のみへ射影（attackTarget は orchestration-owned で EXCLUDE・pos は knockback-free で
    // invariant ゆえ EXCLUDE）。
    //
    // 中間ガードは ORACLE にピン留め（self-guess リテラルではない）:
    //   - w1 hpOf(Enemy1) == oracleW hpOf(Enemy1)（敵が single strike を survive・counter 後も敵 hp 不変）
    //   - evCount(evs1)>0（プレイヤー strike が起きた・空 stream ではない）
    //   - progressOf(Player0) sysW==oracleW（exp sub-threshold で level-up なし）
    //   - プレイヤーが counter で DIE（hpOf(Player0) sysW==oracleW・deferred death を end-to-end でピン）
    @Test
    def testResolveCounterChainEqualsSim(): Unit \ Assert =
        let sc = sceneOf(player(0, 4, Some(1), 200), enemy(1, 10, {x = 3, y = 2}, false, None, ruleJson(""), 200) :: Nil);
        // 合成 legacy oracle（3 seam を ONE withTracedWorld で累積駆動）。
        let oracleW = region rc {
            let ((_, _), _, w) =
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
                TestUnitFixtures.withCursor(() ->
                    run {
                        TestUnitFixtures.withPhaseRef(rc, TurnPhase.Phase.PlayerAttackHold, () -> {
                            let s1 = CombatDriver.applyAttackHit(0, sc);
                            let s2 = CombatDriver.onLungeDone(Faction.Player, 0, s1);
                            CombatDriver.applyEnemyAttackHit(1, s2)
                        })
                    } with Pacing.withState(rc)))))))))))));
            w
        };
        // sim: ONE withSeededRng の下で resolveAttack THEN resolveEnemyAttack を thread。
        let w0 = World.syncFromScene(sc, World.empty());
        let (w2, w1EnemyHp, evCount1) = region rc {
            TestUnitFixtures.withSeededRng(rc, seed(), () -> {
                let (w1, evs1) = CombatSystem.resolveAttack(w0,
                    {ref = EntityRef.Player(0), level = 1}, {ref = EntityRef.Enemy(1), level = 1});
                let (wEnd, _) = CombatSystem.resolveEnemyAttack(w1,
                    {ref = EntityRef.Enemy(1), level = 1}, {ref = EntityRef.Player(0), level = 1});
                (wEnd, World.hpOf(EntityRef.Enemy(1), w1), List.length(evs1))
            })
        };
        assertNonVacuous(sc, evCount1);
        // 中間ガード: プレイヤー strike 後の敵 hp を legacy にピン（敵は single strike を survive・以後 hp 不変）。
        Assert.assertEq(expected = World.hpOf(EntityRef.Enemy(1), oracleW), w1EnemyHp);
        // 等価: counter 連鎖後（敵反撃が味方を撃破）の (enemy hp, player hp, alerted, status, progress) が オラクルと一致。
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w), World.hpOf(EntityRef.Player(0), w),
                         World.alertedOf(EntityRef.Enemy(1), w), statusT(EntityRef.Player(0), w),
                         World.progressOf(EntityRef.Player(0), w));
        Assert.assertEq(expected = proj(oracleW), proj(w2))

    // ── view-script 充実（ViewReplay 前段）: resolveCombat のログが view-fx を載せるか ──────────
    //
    // resolveCombat は命中 SE / 魔法着弾爆発 / miss ポップアップを `ViewFx(...)` として emit し、ログを
    // 「完全な view-script」にする（World identity ＝ golden/最終 World 等価は不変）。ここでは ViewFx の内容
    // （SE 名・爆発セル・popup テキスト）を射影ヘルパーで抽出して固定する。ViewFxKind は Eq 非派生なので
    // tag/scalar 射影で比較する（test 本体に直接 match を書かない＝既存方針）。

    /// resolveAttack(player0→enemy1) を seed() で駆動し **event 列**を返す（view-script 検証用）。
    def driveResolveEvs(sc: Scene[NodeTag]): List[World.SimEvent] =
        let w0 = World.syncFromScene(sc, World.empty());
        region rc {
            let (_, evs) = TestUnitFixtures.withSeededRng(rc, seed(), () ->
                CombatSystem.resolveAttack(w0, {ref = EntityRef.Player(0), level = 1}, {ref = EntityRef.Enemy(1), level = 1}));
            evs
        }

    /// ViewFx(Sound) の SE 名を出現順に抽出。
    def soundsOf(events: List[World.SimEvent]): List[String] =
        List.filterMap(ev -> match ev {
            case World.SimEvent.ViewFx(World.ViewFxKind.Sound(n)) => Some(n)
            case _                                                => None
        }, events)

    /// ViewFx(Explosion) のセル座標を抽出。
    def explosionCellsOf(events: List[World.SimEvent]): List[(Int32, Int32)] =
        List.filterMap(ev -> match ev {
            case World.SimEvent.ViewFx(World.ViewFxKind.Explosion(c)) => Some((c#x, c#y))
            case _                                                    => None
        }, events)

    /// ViewFx(FireShot) の (詠唱者セル, 対象セル) を抽出。魔導書攻撃の炎 3 幕。
    def fireShotsOf(events: List[World.SimEvent]): List[((Int32, Int32), (Int32, Int32))] =
        List.filterMap(ev -> match ev {
            case World.SimEvent.ViewFx(World.ViewFxKind.FireShot(f)) =>
                Some(((f#caster#x, f#caster#y), (f#target#x, f#target#y)))
            case _ => None
        }, events)

    /// ViewFx(Popup) の (text, x, y) を抽出。
    def popupsOf(events: List[World.SimEvent]): List[(String, Int32, Int32)] =
        List.filterMap(ev -> match ev {
            case World.SimEvent.ViewFx(World.ViewFxKind.Popup(p)) => Some((p#text, p#x, p#y))
            case _                                                => None
        }, events)

    /// 通常物理命中 → 命中 SE は "damage"（必殺でなく・魔法でなく・dmg>0）。
    @Test
    def testViewScriptNormalHitSound(): Unit \ Assert =
        let sc = sceneOf(player(0, 10, Some(1), 200), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        Assert.assertEq(expected = "damage" :: Nil, soundsOf(driveResolveEvs(sc)))

    /// 必殺命中（crit=100 武器）→ 命中 SE は "critical"。
    @Test
    def testViewScriptCritHitSound(): Unit \ Assert =
        let critWeapon = ({hit = 200, crit = 100 | testWeapon()}: UnitCatalog.WeaponResource);
        let cp = {weapons = critWeapon :: Nil | player(0, 10, Some(1), 200)};
        let sc = sceneOf(cp, enemy(1, 10, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        Assert.assertEq(expected = "critical" :: Nil, soundsOf(driveResolveEvs(sc)))

    /// 0 ダメージ命中（硬い敵・defense=8・ring なし）→ 命中 SE は "guard"。
    @Test
    def testViewScriptGuardHitSound(): Unit \ Assert =
        let sc = sceneOf(player(0, 10, Some(1), 200), finisherEnemy() :: Nil);
        Assert.assertEq(expected = "guard" :: Nil, soundsOf(driveResolveEvs(sc)))

    /// 魔法武器命中 → 詠唱者セル {2,2} から敵セル {3,2} へ炎 3 幕（ViewFx(FireShot)）。命中で発火し dmg 非依存。
    /// 従来のスプライト着弾爆発（ViewFx(Explosion)）は魔導書攻撃では出さず FireShot が置き換える。
    @Test
    def testViewScriptMagicHitExplosion(): Unit \ Assert =
        let magicWeapon = ({weaponType = WeaponCatalog.WeaponType.Magic, hit = 200, crit = 0 | testWeapon()}: UnitCatalog.WeaponResource);
        let mp = {weapons = magicWeapon :: Nil | player(0, 10, Some(1), 200)};
        let sc = sceneOf(mp, enemy(1, 20, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let evs = driveResolveEvs(sc);
        Assert.assertEq(expected = ((2, 2), (3, 2)) :: Nil, fireShotsOf(evs));
        Assert.assertEq(expected = true, List.isEmpty(explosionCellsOf(evs)))

    /// 回避 → 命中 SE は鳴らず（"miss" SE のみ）＋ "miss" テキストポップアップを敵セル {3,2} に浮かす。
    @Test
    def testViewScriptMissFx(): Unit \ Assert =
        let sc = sceneOf(player(0, 10, Some(1), 0), enemy(1, 4, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        let evs = driveResolveEvs(sc);
        Assert.assertEq(expected = "miss" :: Nil, soundsOf(evs));
        Assert.assertEq(expected = ("miss", 3, 2) :: Nil, popupsOf(evs))

    /// 敵攻撃は魔法武器でも **炎 3 幕を出さない**（legacy 敵攻撃は着弾 fx を発火しない＝allowExplosion=false）。
    /// 命中 SE は出す（必ず 1 件・名前は dmg 依存ゆえ件数で固定）。
    @Test
    def testViewScriptEnemyHitNoExplosion(): Unit \ Assert =
        let magicWeapon = ({weaponType = WeaponCatalog.WeaponType.Magic, hit = 200, crit = 0 | testWeapon()}: UnitCatalog.WeaponResource);
        let e  = {weapon = Some(magicWeapon) | enemy(1, 10, {x = 3, y = 2}, false, Some(0), ruleJson(""), 200)};
        let sc = sceneOf(player(0, 10, None, 80), e :: Nil);
        let (_, evs) = driveEnemyResolve(sc);
        Assert.assertEq(expected = true, List.isEmpty(fireShotsOf(evs)));
        Assert.assertEq(expected = 1, List.length(soundsOf(evs)))

    /// 統合: 実 sim ログ（通常命中・敵 hp20 生存）を `ViewReplay.plan` で view-action 化すると 3 件
    /// （Play "damage" → Damage(enemy,4) → HpBar(enemy,16)）になる。sim enrichment と ViewReplay 純粋 dispatch の
    /// 結線を end-to-end で固定（非撃破ゆえ Death なし・Alerted/Released は view なし＝plan で空に落ちる）。
    @Test
    def testViewScriptPlansToActions(): Unit \ Assert =
        let sc = sceneOf(player(0, 10, Some(1), 200), enemy(1, 20, {x = 3, y = 2}, false, None, ruleJson(""), 80) :: Nil);
        Assert.assertEq(expected = 3, List.length(ViewReplay.plan(driveResolveEvs(sc))))
}
