// 杖 cutover の golden-trace 等価テスト（combat の TestGoldenTrace を 2 周目に縮約コピー）。
//
// legacy 杖（`StaffCastScene.applyStaffEffectLegacy`・pub seam）を traced harness で駆動して **最終 World** を
// オラクルにし、純 sim（`StaffSystem.resolveStaffCast`）の最終 World と一致するかを照合する。
// 杖は命中ロールを引かない（rayCast 結果=hit を引数で受ける）＝seeded RNG 不要・完全決定論。
//
// 照合方針（plan §goldenTrace）:
//   - Heal/Blowback/Swap … World 権威 field（hp/pos/dying）の射影を legacy と sim で assertEq ＋ 具体値リテラル pin。
//   - Bind … legacy は mapPlayer 直書きで Cmd.Add を emit せず legacy World に immobilize が載らない（World 等価不可）ため、
//     ① sim 側 evCount==1 + cmdKey==("Add",uid,5,0) リテラルで Afflicted→eventToCmds→Cmd.Add の新コード経路を実踏、
//     ② applyEcsStaffSceneEffects を駆動した scene #statuses を legacy #statuses と等価比較、③ remaining=5 を tuple で pin。
//   - whiff（壁）… evCount==0 を pin（意図的 vacuity の明示）。
// GameLogger hit-log は equivalence contract 外（sim/ViewReplay とも log を積まない）＝数値状態の等価であり log 等価ではない。
// テスト本体に match を書かず posT/sceneStatusT の射影ヘルパー経由・期待値は具体値リテラル（self-derivation を避ける）。
mod TestStaffGolden {

    use World.EntityRef
    use TestUnitFixtures.{testResource, testEnemyResource}

    // 固定 seed（杖は draw 0 ゆえ outcome は seed 非依存。harness の World 種に使うだけ）。
    def seed(): Int64 = 12345i64

    // ── fixtures ──────────────────────────────────────────────────────────────

    /// 味方フィクスチャ。`mAtk` で回復量源泉（魔力）を、`maxHp` で resource#hp（クランプ上限）を作り分ける。
    def playerAt(id: Int32, gridPos: {x = Int32, y = Int32}, hp: Int32, maxHp: Int32, mAtk: Int32):
            PlayerScene.Data = {
        id                = id,
        classId           = "test_player",
        gridPos           = gridPos,
        moveTiles         = 4,
        hp                = hp,
        waited            = false,
        attackTargetId    = None,
        resource          = {magicAttack = mAtk | testResource(4, maxHp)},
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
        rings             = Nil,
        ringEquipped      = false,
        followUpUsed      = false
    }

    /// 敵フィクスチャ。`maxHp`=resource#hp。
    def enemyAt(id: Int32, gridPos: {x = Int32, y = Int32}, hp: Int32, maxHp: Int32): EnemyScene.Data = {
        id             = id,
        resourceId     = "test_enemy",
        gridPos        = gridPos,
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 3,
        hp             = hp,
        isDying        = false,
        attackTargetId = None,
        resource       = testEnemyResource(3, maxHp),
        weapon         = None,
        acted          = false,
        prevPos        = None,
        statuses       = Nil,
        ring           = None,
        followUpUsed   = false,
        bottleUsed     = false
    }

    /// テスト用の杖（effectRule 無し＝legacy/sim の 4 enum 経路を踏む）。
    def staffOf(effect: Staff.StaffEffect): Staff.StaffResource = {
        name = "test-staff", effect = effect, durability = 5, weight = 0.75,
        sprite = fxSprite(), description = "", effectRule = None
    }

    /// ダミー sprite。
    def fxSprite(): Sprite.SpriteResource = {
        texture = "test-texture", hframes = 1, vframes = 1, frame = 0,
        offset = {x = 0.0, y = 0.0}, scale = {x = 1.0, y = 1.0}, flipForFacing = false
    }

    /// 13×13 の壁なし floor map（toBoard / boardOf が map ノードを要求するため）。TestGoldenTrace 踏襲。
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

    /// World ノード下に player 群 + enemy 群 + floor map を挿した最小 scene。
    def sceneOf(players: List[PlayerScene.Data], enemies: List[EnemyScene.Data]): Scene[NodeTag] =
        let worldM = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        let base = Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(worldM, NodeTag.NoTag))
            |> Scene.addNode("DungeonLevel0",
                EngineNode.TileMapLayerWithState(floorMapLayer(), NodeTag.Map(floorMapData())));
        let withPlayers = List.foldLeft((sc, p) ->
            Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(p#id),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.Player(p)), sc),
            base, players);
        List.foldLeft((sc, e) ->
            Scene.addChildAt(MapScene.worldPath(), EnemyScene.enemyName(e#id),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.Enemy(e)), sc),
            withPlayers, enemies)

    // ── harness ───────────────────────────────────────────────────────────────

    /// legacy 杖（`applyStaffEffectLegacy`・playerId=0 固定の caster）を traced harness + 副作用モックで駆動し、
    /// (後 scene, 最終 World) を返す。dual-write Cmd を ref-backed world へ畳む（runAttack:163 と同型・杖は Audio/Game 不要）。
    /// 多引数ゆえレコード名前渡し（誤順防止）。
    def runStaffLegacy(in: {scene = Scene[NodeTag], player = PlayerScene.Data,
                            staff = Staff.StaffResource, dir = {x = Int32, y = Int32}, hit = RayHit}):
            (Scene[NodeTag], World) =
        region rc {
            let (s, _, w) =
                TestUnitFixtures.withTracedWorld(rc, seed(), in#scene, () ->
                TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(in#scene), () ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withNoopTween(() ->
                    StaffCastScene.applyStaffEffectLegacy(0, in#player, in#staff, in#dir, in#hit, in#scene))))));
            (s, w)
        }

    /// 純 sim 直駆動: `w0=syncFromScene` → `resolveStaffCast(caster=Player(0), ..)` → (World, [SimEvent])。
    /// region/withSeededRng 不要（resolveStaffCast は no effect・決定論）。
    def driveStaffResolve(sc: Scene[NodeTag], effect: Staff.StaffEffect,
                           dir: {x = Int32, y = Int32}, hit: RayHit): (World, List[World.SimEvent]) =
        let w0 = World.syncFromScene(sc, World.empty());
        StaffSystem.resolveStaffCast(w0, EntityRef.Player(0), effect, dir, hit)

    // ── projections（test 本体に match を書かない射影ヘルパー）─────────────────────

    /// posOf を Eq 可能な (x,y) タプルへ射影（record は Eq 非自動）。
    def posT(ref: EntityRef, w: World): Option[(Int32, Int32)] =
        World.posOf(ref, w) |> Option.map(p -> (p#x, p#y))

    /// scene の味方 statuses を Eq 可能な (effect, magnitude, remaining) 列へ射影。
    def sceneStatusT(id: Int32, sc: Scene[NodeTag]): List[(StatusSystem.StatusEffect, Int32, Int32)] =
        PlayerScene.get(id, sc)
            |> Option.map(d -> d#statuses)
            |> Option.getWithDefault(Nil)
            |> List.map(s -> (s#effect, s#magnitude, s#remaining))

    // ── (Heal) World 等価 + 回復量源泉 non-vacuity ─────────────────────────────

    /// 回復: caster 魔力4 → target(味方 hp3/maxHp20)を 3+(4+10)=17 まで回復（クランプなし）。
    /// legacy（applyHealToPlayer→setHp dual-write）の最終 World hp と sim（Healed→SetHp）が一致し、
    /// 17 を具体値で pin して magicAttack 源泉（baseStatsOf=resource verbatim）を固定する（偶然一致を排除）。
    @Test
    def testStaffHealEqualsLegacy(): Unit \ Assert =
        let caster = playerAt(0, {x = 2, y = 2}, 10, 10, 4);
        let target = playerAt(1, {x = 5, y = 2}, 3, 20, 0);
        let sc = sceneOf(caster :: target :: Nil, Nil);
        let hit = RayHit.HitPlayer(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Heal);
        let (_, legacyW) = runStaffLegacy({scene = sc, player = caster, staff = staff, dir = dir, hit = hit});
        let (sysW, evs) = driveStaffResolve(sc, Staff.StaffEffect.Heal, dir, hit);
        Assert.assertEq(expected = true, List.length(evs) > 0);
        // 等価: 回復後の target hp が legacy と一致。
        Assert.assertEq(expected = World.hpOf(EntityRef.Player(1), legacyW),
                        World.hpOf(EntityRef.Player(1), sysW));
        // non-vacuity: 3 + (魔力4 + 10) = 17（maxHp20 でクランプなし）を pin。
        Assert.assertEq(expected = Some(17), World.hpOf(EntityRef.Player(1), sysW))

    // ── (Blowback) World 等価 ──────────────────────────────────────────────────

    /// ふきとばし × 敵(生存): 敵 hp5→4・hitCell{3,2} から右へ knockbackPath で壁手前{12,2}へ着地。
    /// legacy（setHp+snapTo dual-write）と sim（Damaged+Moved）の (敵 hp, pos) が一致し、(4,{12,2}) を pin。
    @Test
    def testStaffBlowbackEnemySurvivesEqualsLegacy(): Unit \ Assert =
        let caster = playerAt(0, {x = 2, y = 2}, 10, 10, 0);
        let target = enemyAt(1, {x = 3, y = 2}, 5, 10);
        let sc = sceneOf(caster :: Nil, target :: Nil);
        let hit = RayHit.HitEnemy(1, {x = 3, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Blowback);
        let (_, legacyW) = runStaffLegacy({scene = sc, player = caster, staff = staff, dir = dir, hit = hit});
        let (sysW, evs) = driveStaffResolve(sc, Staff.StaffEffect.Blowback, dir, hit);
        Assert.assertEq(expected = true, List.length(evs) > 0);
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w), posT(EntityRef.Enemy(1), w));
        // 等価: 1 ダメージ + 着地後の (敵 hp, pos) が legacy と一致。
        Assert.assertEq(expected = proj(legacyW), proj(sysW));
        // 独立 pin: hp5→4・{3,2}→{12,2}（壁なし 13×13・右端手前）。
        Assert.assertEq(expected = (Some(4), Some((12, 2))), proj(sysW))

    /// ふきとばし × 敵(撃破): 敵 hp1→0（hard-0）+ 死亡演出。legacy（startDeathAnimation=SetHp0+SetDying）と
    /// sim（Damaged(0)+Dying+ViewFx(Died)）の (敵 hp, dying) が一致し、(0,true) を pin。
    @Test
    def testStaffBlowbackEnemyKillEqualsLegacy(): Unit \ Assert =
        let caster = playerAt(0, {x = 2, y = 2}, 10, 10, 0);
        let target = enemyAt(1, {x = 3, y = 2}, 1, 10);
        let sc = sceneOf(caster :: Nil, target :: Nil);
        let hit = RayHit.HitEnemy(1, {x = 3, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Blowback);
        let (_, legacyW) = runStaffLegacy({scene = sc, player = caster, staff = staff, dir = dir, hit = hit});
        let (sysW, evs) = driveStaffResolve(sc, Staff.StaffEffect.Blowback, dir, hit);
        Assert.assertEq(expected = true, List.length(evs) > 0);
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w), World.isDyingOf(EntityRef.Enemy(1), w));
        // 等価: 撃破後の (敵 hp, dying) が legacy と一致。
        Assert.assertEq(expected = proj(legacyW), proj(sysW));
        // 独立 pin: hp=0（hard-0 リテラル）・dying=true。
        Assert.assertEq(expected = (Some(0), true), proj(sysW))

    // ── (Swap) World 等価 ──────────────────────────────────────────────────────

    /// いれかえ × 敵: caster{2,2} と敵{5,2} を交換。legacy（snapTo×2 dual-write）と sim（Moved×2・順序保存）の
    /// (caster pos, 敵 pos) が一致し、(({5,2}),({2,2})) を pin。
    @Test
    def testStaffSwapEqualsLegacy(): Unit \ Assert =
        let caster = playerAt(0, {x = 2, y = 2}, 10, 10, 0);
        let target = enemyAt(1, {x = 5, y = 2}, 10, 10);
        let sc = sceneOf(caster :: Nil, target :: Nil);
        let hit = RayHit.HitEnemy(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Swap);
        let (_, legacyW) = runStaffLegacy({scene = sc, player = caster, staff = staff, dir = dir, hit = hit});
        let (sysW, evs) = driveStaffResolve(sc, Staff.StaffEffect.Swap, dir, hit);
        Assert.assertEq(expected = true, List.length(evs) > 0);
        let proj = w -> (posT(EntityRef.Player(0), w), posT(EntityRef.Enemy(1), w));
        // 等価: 交換後の (caster pos, 敵 pos) が legacy と一致。
        Assert.assertEq(expected = proj(legacyW), proj(sysW));
        // 独立 pin: caster{2,2}↔敵{5,2}。
        Assert.assertEq(expected = (Some((5, 2)), Some((2, 2))), proj(sysW))

    // ── (Bind) sim cmdKey + scene-statuses 等価 + remaining literal ─────────────

    /// かなしばり × 味方(id=1): legacy は mapPlayer 直書きで Cmd.Add を emit せず World 等価不可ゆえ 3 段で固定:
    ///   ① sim 側 evCount==1 + cmdKey==("Add",1,5,0)（Immobilized 種別=5・magnitude=0・uid=toUid(Player(1))=1）で
    ///      Afflicted→eventToCmds→Cmd.Add の新コード経路を実踏（無いと emit パスが緑のまま黙って退行しうる）、
    ///   ② applyEcsStaffSceneEffects を駆動した scene #statuses を legacy #statuses と等価比較、
    ///   ③ remaining=5 を (Immobilized,0,5) tuple で pin。bindTurns を 3 へ退行させると ① cmdKey と ③ remaining が落ちる。
    @Test
    def testStaffBindSceneStatusesAndSimCmdKey(): Unit \ Assert =
        let caster = playerAt(0, {x = 2, y = 2}, 10, 10, 0);
        let target = playerAt(1, {x = 5, y = 2}, 10, 10, 0);
        let sc = sceneOf(caster :: target :: Nil, Nil);
        let hit = RayHit.HitPlayer(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Bind);
        let (sysW, evs) = driveStaffResolve(sc, Staff.StaffEffect.Bind, dir, hit);
        // ① sim 側: 単一 Afflicted → Cmd.Add リテラル（新コード経路の実踏）。
        Assert.assertEq(expected = 1, List.length(evs));
        let cmdKeys = evs |> List.flatMap(World.eventToCmds) |> List.map(World.cmdKey);
        Assert.assertEq(expected = ("Add", 1, 5, 0) :: Nil, cmdKeys);
        // ② scene-statuses: legacy #statuses == ECS（applyEcsStaffSceneEffects 駆動）#statuses。
        let (legacyScene, _) = runStaffLegacy({scene = sc, player = caster, staff = staff, dir = dir, hit = hit});
        let ecsScene = StaffCastScene.applyEcsStaffSceneEffects(evs, sc);
        Assert.assertEq(expected = sceneStatusT(1, legacyScene), sceneStatusT(1, ecsScene));
        // ③ remaining=5 を tuple リテラルで pin（immobilizeFor(5) を self-derive しない）。
        Assert.assertEq(expected = (StatusSystem.StatusEffect.Immobilized, 0, 5) :: Nil, sceneStatusT(1, ecsScene));
        // sysW は ① で World へ Cmd.Add 済（read-model 側の sanity）＝immobilize が World にも載る。
        Assert.assertEq(expected = false, List.isEmpty(World.statusEffectsOf(EntityRef.Player(1), sysW)))

    // ── (whiff) 空振り＝意図的 vacuity ─────────────────────────────────────────

    /// 壁ヒット（空振り）は sim が events を 1 つも積まない＝World 不変。evCount==0 を pin（呼び出し側は
    /// legacy へ fallback して『届かなかった』ログを温存する）。
    @Test
    def testStaffWhiffEmptyEvents(): Unit \ Assert =
        let caster = playerAt(0, {x = 2, y = 2}, 10, 10, 4);
        let sc = sceneOf(caster :: Nil, Nil);
        let hit = RayHit.HitWall({x = 4, y = 2});
        let dir = {x = 1, y = 0};
        let (_, evs) = driveStaffResolve(sc, Staff.StaffEffect.Heal, dir, hit);
        Assert.assertEq(expected = 0, List.length(evs))

    // ── 出荷 seam（ecsResolveStaffCast）直駆動ハーネス ────────────────────────────
    //
    // 上の等価テストは `resolveStaffCast`（sim）と `applyEcsStaffSceneEffects`（scene）を分解して
    // 当てるだけで、実際に出荷される cutover seam `StaffCastScene.ecsResolveStaffCast` の
    // emit ループ・Nil-fallback 分岐・ViewReplay 配線は未踏だった。それらを traced harness 内で
    // 駆動して固定する（emit は World.Command effect ゆえ effectful run の defer 対象外）。

    /// 記録ロガー: playerLog/enemyLog の文字列を時系列で集める（whiff fallback の log 等価オラクル用）。
    /// `withMockGameLogger` は drop するため、空振りで『届かなかった』ログが本当に出たか観測できない。
    def withRecLogger(rc: Region[r], thunk: Unit -> a \ ef): (a, List[String]) \ (ef - GameLogger.GameLogger) + r =
        let ref = Ref.fresh(rc, (Nil: List[String]));
        let out = run { thunk() } with handler GameLogger.GameLogger {
            def playerLog(s, k)   = { Ref.put(s :: Ref.get(ref), ref); k() }
            def enemyLog(s, k)    = { Ref.put(s :: Ref.get(ref), ref); k() }
            def gameOverLog(_, k) = k()
            def endTurn(k)        = k()
            def drainEntries(k)   = k(Nil)
        };
        (out, List.reverse(Ref.get(ref)))

    /// 出荷 cutover seam `ecsResolveStaffCast`（playerId=0 固定）を traced harness + recording logger で
    /// 駆動。(後 scene, cmdKey 列, 最終 World, log 列)。emit ループ/Nil-fallback/ViewReplay 配線を実踏する。
    def runStaffEcs(in: {scene = Scene[NodeTag], player = PlayerScene.Data,
                         staff = Staff.StaffResource, dir = {x = Int32, y = Int32}, hit = RayHit}):
            (Scene[NodeTag], List[(String, Int32, Int32, Int32)], World, List[String]) =
        region rc {
            let ((s, logs), keys, w) =
                TestUnitFixtures.withTracedWorld(rc, seed(), in#scene, () ->
                TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(in#scene), () ->
                TestUnitFixtures.withMockGame(() ->
                TestUnitFixtures.withMockAudio(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withNoopTween(() ->
                    withRecLogger(rc, () ->
                        StaffCastScene.ecsResolveStaffCast(0, in#player, in#staff, in#dir, in#hit, in#scene))))))));
            (s, keys, w, logs)
        }

    /// legacy 杖 seam を traced harness + recording logger で駆動（whiff fallback の log/cmds オラクル）。
    def runStaffLegacyLogged(in: {scene = Scene[NodeTag], player = PlayerScene.Data,
                                  staff = Staff.StaffResource, dir = {x = Int32, y = Int32}, hit = RayHit}):
            (Scene[NodeTag], List[(String, Int32, Int32, Int32)], World, List[String]) =
        region rc {
            let ((s, logs), keys, w) =
                TestUnitFixtures.withTracedWorld(rc, seed(), in#scene, () ->
                TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(in#scene), () ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withNoopTween(() ->
                    withRecLogger(rc, () ->
                        StaffCastScene.applyStaffEffectLegacy(0, in#player, in#staff, in#dir, in#hit, in#scene))))));
            (s, keys, w, logs)
        }

    // ── (seam-a) whiff → legacy fallback の log 等価 ───────────────────────────────

    /// 空振り（壁 hit）で `ecsResolveStaffCast` は events=Nil を見て `applyStaffEffectLegacy` へ fallback する。
    /// 出荷 seam の log/cmds が直 legacy whiff 呼びと一致することを固定。else 分岐（empty events を replay）が
    /// 誤って走ると『届かなかった』ログが 0 行になり legLogs と乖離して落ちる＝Nil-fallback を非 vacuous に pin。
    @Test
    def testStaffEcsSeamWhiffFallsBackToLegacy(): Unit \ Assert =
        let caster = playerAt(0, {x = 2, y = 2}, 10, 10, 4);
        let target = playerAt(1, {x = 5, y = 2}, 3, 20, 0);
        let sc = sceneOf(caster :: target :: Nil, Nil);
        let hit = RayHit.HitWall({x = 4, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Heal);
        let args = {scene = sc, player = caster, staff = staff, dir = dir, hit = hit};
        let (_, ecsKeys, ecsW, ecsLogs) = runStaffEcs(args);
        let (_, legKeys, _, legLogs)    = runStaffLegacyLogged(args);
        // fallback 等価: ecs seam の log/cmds が直 legacy whiff 呼びと一致。
        Assert.assertEq(expected = legLogs, ecsLogs);
        Assert.assertEq(expected = legKeys, ecsKeys);
        // 非 vacuity: whiff は Cmd を積まず（World 不変）、"届かなかった" を 1 行だけログる。
        Assert.assertEq(expected = (Nil: List[(String, Int32, Int32, Int32)]), ecsKeys);
        Assert.assertEq(expected = 1, List.length(ecsLogs));
        // target hp は不変（heal が起きていない＝空振り）。
        Assert.assertEq(expected = Some(3), World.hpOf(EntityRef.Player(1), ecsW))

    // ── (seam-b) hit → emit ループが eventToCmds と一致 + 最終 World 等価 ────────────

    /// ヒット時、出荷 seam が World へ積む Cmd **集合** が sim events の `eventToCmds` と一致し、最終 World が
    /// `driveStaffResolve` の World と一致する（emit ループ・applyCmd 経路の固定）。fixture は blowback×敵生存
    /// （Damaged+Moved）。
    ///
    /// 注: seam は `Move` を 2 度積む — 明示 emit ループ（`eventToCmds`）と `ViewReplay.replay` の
    /// `Snap`→`snapRefTo`（scene 権威 snap が World へ dual-write）の二経路から。`Cmd.Move` は絶対座標で
    /// 冪等ゆえ最終 World は不変（combat seam では Moved event を出さず未顕在だった）。よって契約は **集合** 一致で
    /// 表し（重複 Move を許容）、最終 World 等価を本丸の保証とする。raw list 長=3 も pin して二経路 emit の形を固定する。
    @Test
    def testStaffEcsSeamEmitsEventToCmds(): Unit \ Assert =
        let caster = playerAt(0, {x = 2, y = 2}, 10, 10, 0);
        let target = enemyAt(1, {x = 3, y = 2}, 5, 10);
        let sc = sceneOf(caster :: Nil, target :: Nil);
        let hit = RayHit.HitEnemy(1, {x = 3, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Blowback);
        let (_, ecsKeys, ecsW, _) = runStaffEcs({scene = sc, player = caster, staff = staff, dir = dir, hit = hit});
        let (simW, evs) = driveStaffResolve(sc, Staff.StaffEffect.Blowback, dir, hit);
        // cross-check: 出荷 seam が積んだ cmdKey 集合 == sim events の eventToCmds 集合（emit 配線の固定）。
        let simKeys = evs |> List.flatMap(World.eventToCmds) |> List.map(World.cmdKey);
        Assert.assertEq(expected = List.toSet(simKeys), List.toSet(ecsKeys));
        // golden pin: 集合 = {Damaged(enemy,4)→SetHp, Moved(enemy,{12,2})→Move}（literal で固定）。
        Assert.assertEq(expected = Set#{("SetHp", 1000001, 4, 0), ("Move", 1000001, 12, 2)}, List.toSet(ecsKeys));
        // 二経路 emit の形: SetHp×1 + Move×2（replay snapRefTo の冪等 dual-write）= raw 3 件。
        Assert.assertEq(expected = 3, List.length(ecsKeys));
        // 最終 World 等価: seam の applyCmd 経路 == driveStaffResolve の applyEventToWorld 経路（敵 hp/pos）。
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w), posT(EntityRef.Enemy(1), w));
        Assert.assertEq(expected = proj(simW), proj(ecsW));
        Assert.assertEq(expected = (Some(4), Some((12, 2))), proj(ecsW))

    // ── (Blowback × 味方) ally 分岐の等価 pin（生存・撃破）─────────────────────────

    /// ふきとばし × 味方(生存): 味方 hp5→4・hitCell{3,2} から右へ knockbackPath で壁手前{12,2}へ着地。
    /// legacy `applyBlowbackToPlayer`（setHp+snapTo）と sim（Damaged+Moved）の (味方 hp, pos) が一致し、
    /// (4,{12,2}) を pin（ally 生存分岐＝Damaged raw :: Moved を踏む）。
    @Test
    def testStaffBlowbackAllySurvivesEqualsLegacy(): Unit \ Assert =
        let caster = playerAt(0, {x = 2, y = 2}, 10, 10, 0);
        let target = playerAt(1, {x = 3, y = 2}, 5, 10, 0);
        let sc = sceneOf(caster :: target :: Nil, Nil);
        let hit = RayHit.HitPlayer(1, {x = 3, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Blowback);
        let (_, legacyW) = runStaffLegacy({scene = sc, player = caster, staff = staff, dir = dir, hit = hit});
        let (sysW, evs) = driveStaffResolve(sc, Staff.StaffEffect.Blowback, dir, hit);
        Assert.assertEq(expected = true, List.length(evs) > 0);
        let proj = w -> (World.hpOf(EntityRef.Player(1), w), posT(EntityRef.Player(1), w));
        // 等価: 1 ダメージ + 着地後の (味方 hp, pos) が legacy と一致。
        Assert.assertEq(expected = proj(legacyW), proj(sysW));
        // 独立 pin: hp5→4・{3,2}→{12,2}。
        Assert.assertEq(expected = (Some(4), Some((12, 2))), proj(sysW))

    /// ふきとばし × 味方(撃破): 味方 hp1→0。sim の ally 撃破分岐（StaffSystem.flix:93-94 の `else if dmgRes#isDead`）は
    /// **Damaged raw のみ**＝Dying/ViewFx を出さない（敵撃破は hard-0+Dying ゆえ対称性の取り違えが起きやすい）。
    /// legacy `applyBlowbackToPlayer`（isDead→setHp のみ・死亡演出なし）と (味方 hp, dying) が一致し、(0,false) を pin。
    /// ally に Dying を誤発火させると dying=true に転んでここが落ちる。evCount=1（Moved も無い）も pin。
    @Test
    def testStaffBlowbackAllyKillEqualsLegacy(): Unit \ Assert =
        let caster = playerAt(0, {x = 2, y = 2}, 10, 10, 0);
        let target = playerAt(1, {x = 3, y = 2}, 1, 10, 0);
        let sc = sceneOf(caster :: target :: Nil, Nil);
        let hit = RayHit.HitPlayer(1, {x = 3, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Blowback);
        let (_, legacyW) = runStaffLegacy({scene = sc, player = caster, staff = staff, dir = dir, hit = hit});
        let (sysW, evs) = driveStaffResolve(sc, Staff.StaffEffect.Blowback, dir, hit);
        Assert.assertEq(expected = true, List.length(evs) > 0);
        let proj = w -> (World.hpOf(EntityRef.Player(1), w), World.isDyingOf(EntityRef.Player(1), w));
        // 等価: 味方撃破後の (hp, dying) が legacy と一致（ally は Dying/Died を出さない）。
        Assert.assertEq(expected = proj(legacyW), proj(sysW));
        // 独立 pin: hp=0・dying=false（ally に Dying 無し）・evCount=1（Damaged のみ・Moved 無し）。
        Assert.assertEq(expected = (Some(0), false), proj(sysW));
        Assert.assertEq(expected = 1, List.length(evs))

}
