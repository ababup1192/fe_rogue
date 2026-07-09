// 杖 cutover の golden-trace 等価テスト（combat の TestGoldenTrace を 2 周目に縮約コピー）。
//
// live orchestrator（`StaffCast.ecsResolveStaffCast`・pub seam）を traced harness で駆動して **最終 World** を
// オラクルにし、純 sim（`StaffSystem.resolveStaffCast`）の最終 World と一致するかを照合する（wrapper↔system 整合 pin）。
// 杖は命中ロールを引かない（rayCast 結果=hit を引数で受ける）＝seeded RNG 不要・完全決定論。
//
// 照合方針（plan §goldenTrace）:
//   - Heal/Blowback/Swap … World 権威 field（hp/pos/dying）の射影をオラクルと sim で assertEq ＋ 具体値リテラル pin。
//   - Bind … sim 側 evCount==1 + cmdKey==("Add",uid,5,0) リテラルで Afflicted→eventToCmds→Cmd.Add の
//     コード経路を実踏し、①`applyEcsStaffSceneEffects` を駆動した World #statuses をオラクル #statuses と
//     等価比較、②remaining=5 を tuple で pin。
//   - whiff（壁）… evCount==0 を pin（意図的 vacuity の明示）。
// GameLogger hit-log は equivalence contract 外（sim/ViewReplay とも log を積まない）＝数値状態の等価であり log 等価ではない。
// テスト本体に match を書かず posT/worldStatusT の射影ヘルパー経由・期待値は具体値リテラル（self-derivation を避ける）。
mod TestStaffGolden {

    use World.EntityRef
    use TestUnitFixtures.testResource

    // 固定 seed（杖は draw 0 ゆえ outcome は seed 非依存。harness の World 種に使うだけ）。
    def seed(): Int64 = 12345i64

    // ── fixtures（World.Cmd 列）───────────────────────────────────────────────

    /// 味方 fixture の spawn Cmd 列。`mAtk` で回復量源泉（魔力）を、`maxHp` で resource#hp（クランプ上限）を、
    /// `hp` で現在 hp を作り分ける（`TestWorldFixtures.playerCmds` を土台に hp/resource/baseStats を上書きする）。
    def playerCmds(id: Int32, pos: {x = Int32, y = Int32}, hp: Int32, maxHp: Int32, mAtk: Int32): List[World.Cmd] =
        let ref  = EntityRef.Player(id);
        let spec = TestWorldFixtures.unitSpec(id, pos);
        let res  = {magicAttack = mAtk | testResource(spec#moveTiles, maxHp)};
        List.flatten(
            TestWorldFixtures.playerCmds({hp = maxHp | spec})
                :: (World.Cmd.SetHp(ref, hp)
                    :: World.Cmd.SetPlayerResource(id, res)
                    :: World.Cmd.SetBaseStats(ref, Combat.baseStatsFrom(res))
                    :: Nil)
                :: Nil)

    /// 敵 fixture の spawn Cmd 列。`maxHp`=resource#hp・`hp`=現在 hp。
    def enemyCmds(id: Int32, pos: {x = Int32, y = Int32}, hp: Int32, maxHp: Int32): List[World.Cmd] =
        let ref  = EntityRef.Enemy(id);
        let spec = TestWorldFixtures.unitSpec(id, pos);
        List.append(TestWorldFixtures.enemyCmds({hp = maxHp | spec}), World.Cmd.SetHp(ref, hp) :: Nil)

    /// `ecsResolveStaffCast` の `player` 引数は本体で未参照（駒の状態は World 権威で読む）ため、
    /// 型を満たすだけのダミー値。値そのものはテスト結果に影響しない。
    def dummyPlayer(): PlayerDriver.Data = {
        id                = 0,
        classId           = "dummy",
        gridPos           = {x = 0, y = 0},
        moveTiles         = 4,
        hp                = 10,
        waited            = false,
        attackTargetId    = None,
        resource          = testResource(4, 10),
        weapons           = Nil,
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
        rings             = Nil,
        ringEquipped      = false,
        followUpUsed      = false
    }

    /// テスト用の杖（effectRule 無し＝legacy/sim の 4 enum 経路を踏む）。
    def staffOf(effect: Staff.StaffEffect): Staff.StaffResource = {
        name = "test-staff", effect = effect, durability = 5, weight = 0.75,
        sprite = fxSprite(), description = "", effectRule = None
    }

    /// ダミー sprite。
    def fxSprite(): SpriteRes.SpriteResource = {
        texture = "test-texture", hframes = 1, vframes = 1, frame = 0,
        offset = {x = 0.0, y = 0.0}, scale = {x = 1.0, y = 1.0}, flipForFacing = false
    }

    /// 13×13 の壁なし floor 地形（`World.mapSnapshot` / mock board 用の値 fixture）。
    def floorTerrain(): MapSnapshot = TestWorldFixtures.floorSnapshot({w = 13, h = 13})

    /// `cmds` から Board を組む（`withMockBoard` 供給用）。harness 内部の World と同じ Cmd 列を
    /// 同じ地形に適用して組むので、trace ハーネスが seed する World と一致する。
    def boardFor(cmds: List[World.Cmd]): Board =
        let w = TestWorldFixtures.worldOf(World.Cmd.SetMapSnapshot(Some(floorTerrain())) :: cmds);
        World.boardOf(w) |> Option.getWithDefault({map = floorTerrain(), pieces = Nil})

    // ── harness ───────────────────────────────────────────────────────────────

    /// live orchestrator（`ecsResolveStaffCast`・playerId=0 固定の caster）を traced harness + 副作用モックで駆動し、
    /// 最終 World をオラクルとして返す（cross-compare は「wrapper↔system 整合」の pin）。多引数ゆえレコード名前渡し。
    def runStaffOracle(in: {cmds = List[World.Cmd], staff = Staff.StaffResource,
                            dir = {x = Int32, y = Int32}, hit = RayHit}): World =
        region rc {
            let (_, _, w) =
                TestUnitFixtures.withTracedBoardWorld(rc, seed(), floorTerrain(), in#cmds, () ->
                TestUnitFixtures.withMockBoard(boardFor(in#cmds), () ->
                TestUnitFixtures.withMockAudio(() ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withNoopTween(() ->
                    StaffCast.ecsResolveStaffCast(0, dummyPlayer(), in#staff, in#dir, in#hit)))))));
            w
        }

    /// 純 sim 直駆動: `w0`（地形 + fixture Cmd 列を World.empty() に適用したもの）→
    /// `resolveStaffCast(caster=Player(0), ..)` → (World, [SimEvent])。
    /// region/withSeededRng 不要（resolveStaffCast は no effect・決定論）。
    def driveStaffResolve(cmds: List[World.Cmd], effect: Staff.StaffEffect,
                           dir: {x = Int32, y = Int32}, hit: RayHit): (World, List[World.SimEvent]) =
        let w0 = TestWorldFixtures.worldOf(World.Cmd.SetMapSnapshot(Some(floorTerrain())) :: cmds);
        StaffSystem.resolveStaffCast(w0, EntityRef.Player(0), effect, dir, hit)

    // ── projections（test 本体に match を書かない射影ヘルパー）─────────────────────

    /// posOf を Eq 可能な (x,y) タプルへ射影（record は Eq 非自動）。
    def posT(ref: EntityRef, w: World): Option[(Int32, Int32)] =
        World.posOf(ref, w) |> Option.map(p -> (p#x, p#y))

    /// World 権威の味方 statuses を Eq 可能な (effect, magnitude, remaining) 列へ射影。
    def worldStatusT(id: Int32, w: World): List[(StatusSystem.StatusEffect, Int32, Int32)] =
        World.statusEffectsOf(EntityRef.Player(id), w)
            |> List.map(st -> (st#effect, st#magnitude, st#remaining))


    // ── (Heal) World 等価 + 回復量源泉 non-vacuity ─────────────────────────────

    /// 回復: caster 魔力4 → target(味方 hp3/maxHp20)を 3+(4+10)=17 まで回復（クランプなし）。
    /// orchestrator（`ecsResolveStaffCast`）の最終 World hp と sim（Healed→SetHp）が一致し、
    /// 17 を具体値で pin して magicAttack 源泉（baseStatsOf=resource verbatim）を固定する（偶然一致を排除）。
    @Test
    def testStaffHealEqualsSim(): Unit \ Assert =
        let cmds = List.flatten(
            playerCmds(0, {x = 2, y = 2}, 10, 10, 4) :: playerCmds(1, {x = 5, y = 2}, 3, 20, 0) :: Nil);
        let hit = RayHit.HitPlayer(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Heal);
        let oracleW = runStaffOracle({cmds = cmds, staff = staff, dir = dir, hit = hit});
        let (sysW, evs) = driveStaffResolve(cmds, Staff.StaffEffect.Heal, dir, hit);
        Assert.assertEq(expected = true, List.length(evs) > 0);
        // 等価: 回復後の target hp が オラクルと一致。
        Assert.assertEq(expected = World.hpOf(EntityRef.Player(1), oracleW),
                        World.hpOf(EntityRef.Player(1), sysW));
        // non-vacuity: 3 + (魔力4 + 10) = 17（maxHp20 でクランプなし）を pin。
        Assert.assertEq(expected = Some(17), World.hpOf(EntityRef.Player(1), sysW))

    // ── (Blowback) World 等価 ──────────────────────────────────────────────────

    /// ふきとばし × 敵(生存): 敵 hp5→4・hitCell{3,2} から右へ knockbackPath で壁手前{12,2}へ着地。
    /// orchestrator（Damaged+Moved）と sim（Damaged+Moved）の (敵 hp, pos) が一致し、(4,{12,2}) を pin。
    @Test
    def testStaffBlowbackEnemySurvivesEqualsSim(): Unit \ Assert =
        let cmds = List.flatten(
            playerCmds(0, {x = 2, y = 2}, 10, 10, 0) :: enemyCmds(1, {x = 3, y = 2}, 5, 10) :: Nil);
        let hit = RayHit.HitEnemy(1, {x = 3, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Blowback);
        let oracleW = runStaffOracle({cmds = cmds, staff = staff, dir = dir, hit = hit});
        let (sysW, evs) = driveStaffResolve(cmds, Staff.StaffEffect.Blowback, dir, hit);
        Assert.assertEq(expected = true, List.length(evs) > 0);
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w), posT(EntityRef.Enemy(1), w));
        // 等価: 1 ダメージ + 着地後の (敵 hp, pos) が オラクルと一致。
        Assert.assertEq(expected = proj(oracleW), proj(sysW));
        // 独立 pin: hp5→4・{3,2}→{12,2}（壁なし 13×13・右端手前）。
        Assert.assertEq(expected = (Some(4), Some((12, 2))), proj(sysW))

    /// ふきとばし × 敵(撃破): 敵 hp1→0（hard-0）+ 死亡演出。orchestrator（Damaged(0)+Dying+ViewFx(Died) 反映後の
    /// World）と sim（同）の (敵 hp, dying) が一致し、(0,true) を pin。
    @Test
    def testStaffBlowbackEnemyKillEqualsSim(): Unit \ Assert =
        let cmds = List.flatten(
            playerCmds(0, {x = 2, y = 2}, 10, 10, 0) :: enemyCmds(1, {x = 3, y = 2}, 1, 10) :: Nil);
        let hit = RayHit.HitEnemy(1, {x = 3, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Blowback);
        let oracleW = runStaffOracle({cmds = cmds, staff = staff, dir = dir, hit = hit});
        let (sysW, evs) = driveStaffResolve(cmds, Staff.StaffEffect.Blowback, dir, hit);
        Assert.assertEq(expected = true, List.length(evs) > 0);
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w), World.isDyingOf(EntityRef.Enemy(1), w));
        // 等価: 撃破後の (敵 hp, dying) が オラクルと一致。
        Assert.assertEq(expected = proj(oracleW), proj(sysW));
        // 独立 pin: hp=0（hard-0 リテラル）・dying=true。
        Assert.assertEq(expected = (Some(0), true), proj(sysW))

    // ── (Swap) World 等価 ──────────────────────────────────────────────────────

    /// いれかえ × 敵: caster{2,2} と敵{5,2} を交換。orchestrator（Moved×2）と sim（Moved×2・順序保存）の
    /// (caster pos, 敵 pos) が一致し、(({5,2}),({2,2})) を pin。
    @Test
    def testStaffSwapEqualsSim(): Unit \ Assert =
        let cmds = List.flatten(
            playerCmds(0, {x = 2, y = 2}, 10, 10, 0) :: enemyCmds(1, {x = 5, y = 2}, 10, 10) :: Nil);
        let hit = RayHit.HitEnemy(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Swap);
        let oracleW = runStaffOracle({cmds = cmds, staff = staff, dir = dir, hit = hit});
        let (sysW, evs) = driveStaffResolve(cmds, Staff.StaffEffect.Swap, dir, hit);
        Assert.assertEq(expected = true, List.length(evs) > 0);
        let proj = w -> (posT(EntityRef.Player(0), w), posT(EntityRef.Enemy(1), w));
        // 等価: 交換後の (caster pos, 敵 pos) が オラクルと一致。
        Assert.assertEq(expected = proj(oracleW), proj(sysW));
        // 独立 pin: caster{2,2}↔敵{5,2}。
        Assert.assertEq(expected = (Some((5, 2)), Some((2, 2))), proj(sysW))

    // ── (Bind) sim cmdKey + World-statuses 等価 + remaining literal ─────────────

    /// かなしばり × 味方(id=1): 3 段で固定:
    ///   ① sim 側 evCount==1 + cmdKey==("Add",1,5,0)（Immobilized 種別=5・magnitude=0・uid=toUid(Player(1))=1）で
    ///      Afflicted→eventToCmds→Cmd.Add のコード経路を実踏（無いと emit パスが緑のまま黙って退行しうる）、
    ///   ② `applyEcsStaffSceneEffects` を駆動した World #statuses を orchestrator の #statuses と等価比較、
    ///   ③ remaining=5 を (Immobilized,0,5) tuple で pin。bindTurns を 3 へ退行させると ① cmdKey と ③ remaining が落ちる。
    @Test
    def testStaffBindSceneStatusesAndSimCmdKey(): Unit \ Assert =
        let cmds = List.flatten(
            playerCmds(0, {x = 2, y = 2}, 10, 10, 0) :: playerCmds(1, {x = 5, y = 2}, 10, 10, 0) :: Nil);
        let hit = RayHit.HitPlayer(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Bind);
        let (sysW, evs) = driveStaffResolve(cmds, Staff.StaffEffect.Bind, dir, hit);
        // ① sim 側: 単一 Afflicted → Cmd.Add リテラル（新コード経路の実踏）。
        Assert.assertEq(expected = 1, List.length(evs));
        let cmdKeys = evs |> List.flatMap(World.eventToCmds) |> List.map(World.cmdKey);
        Assert.assertEq(expected = ("Add", 1, 5, 0) :: Nil, cmdKeys);
        // ② statuses は World 権威: orchestrator の最終 World == ECS（sim 適用後 World＋applyEcsStaffSceneEffects の
        //    Seed 再確認）の statuses。
        let oracleW = runStaffOracle({cmds = cmds, staff = staff, dir = dir, hit = hit});
        let ecsW = region rc {
            snd(TestUnitFixtures.withWorldAppliedSeeded(rc, sysW, () ->
                StaffCast.applyEcsStaffSceneEffects(evs)))
        };
        Assert.assertEq(expected = worldStatusT(1, oracleW), worldStatusT(1, ecsW));
        // ③ remaining=5 を tuple リテラルで pin（immobilizeFor(5) を self-derive しない）。
        Assert.assertEq(expected = (StatusSystem.StatusEffect.Immobilized, 0, 5) :: Nil, worldStatusT(1, ecsW));
        // sysW は ① で World へ Cmd.Add 済（read-model 側の sanity）＝immobilize が World にも載る。
        Assert.assertEq(expected = false, List.isEmpty(World.statusEffectsOf(EntityRef.Player(1), sysW)))

    // ── (Stopgap) bind + warp 等価（P1-a）────────────────────────────────────────

    /// 一時しのぎ × 味方(id=1): 完全停止 + 階段{8,8}へワープ。orchestrator（bind→warp dual-write）と
    /// sim `stopgapEvents`（Afflicted :: Moved）を突き合わせる:
    ///   ① evCount==2 + cmdKeys==("Add",1,5,0)::("Move",1,8,8)（bind→warp の順序・新コード経路の実踏）、
    ///   ② warp 後 pos が オラクルと一致し {8,8} を pin（stairsPosOf read-model が warpCellFor に届いている証跡）、
    ///   ③ World #statuses が orchestrator と等価で (Immobilized,0,5) を pin（bind 部の parity）。
    @Test
    def testStaffStopgapWarpsToStairsEqualsSim(): Unit \ Assert =
        let cmds = List.flatten(
            playerCmds(0, {x = 2, y = 2}, 10, 10, 0)
                :: playerCmds(1, {x = 5, y = 2}, 10, 10, 0)
                :: (World.Cmd.SetStairs(Some({x = 8, y = 8})) :: Nil)
                :: Nil);
        let hit = RayHit.HitPlayer(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Stopgap);
        let (sysW, evs) = driveStaffResolve(cmds, Staff.StaffEffect.Stopgap, dir, hit);
        // ① bind(Afflicted→Add) → warp(Moved→Move) の順序と cmdKey リテラル。
        Assert.assertEq(expected = 2, List.length(evs));
        let cmdKeys = evs |> List.flatMap(World.eventToCmds) |> List.map(World.cmdKey);
        Assert.assertEq(expected = ("Add", 1, 5, 0) :: ("Move", 1, 8, 8) :: Nil, cmdKeys);
        // ② pos: orchestrator の warp と一致 + {8,8} を pin。
        let oracleW = runStaffOracle({cmds = cmds, staff = staff, dir = dir, hit = hit});
        Assert.assertEq(expected = posT(EntityRef.Player(1), oracleW), posT(EntityRef.Player(1), sysW));
        Assert.assertEq(expected = Some((8, 8)), posT(EntityRef.Player(1), sysW));
        // ③ statuses（World 権威）等価 + (Immobilized,0,5) pin。
        let ecsW = region rc {
            snd(TestUnitFixtures.withWorldAppliedSeeded(rc, sysW, () ->
                StaffCast.applyEcsStaffSceneEffects(evs)))
        };
        Assert.assertEq(expected = worldStatusT(1, oracleW), worldStatusT(1, ecsW));
        Assert.assertEq(expected = (StatusSystem.StatusEffect.Immobilized, 0, 5) :: Nil, worldStatusT(1, ecsW))

    /// 一時しのぎ × 味方(id=1)・階段なし: warpCellFor(None)=None ゆえ warp せず bind のみ。`stairsPosOf`=None
    /// のとき『ワープ先がなかった』＝停止だけ。sim は Moved を出さず evCount==1・pos 不変を pin。
    @Test
    def testStaffStopgapNoStairsBindOnly(): Unit \ Assert =
        let cmds = List.flatten(
            playerCmds(0, {x = 2, y = 2}, 10, 10, 0) :: playerCmds(1, {x = 5, y = 2}, 10, 10, 0) :: Nil);
        let hit = RayHit.HitPlayer(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        let (sysW, evs) = driveStaffResolve(cmds, Staff.StaffEffect.Stopgap, dir, hit);
        // Afflicted のみ（Moved なし）。
        Assert.assertEq(expected = 1, List.length(evs));
        let cmdKeys = evs |> List.flatMap(World.eventToCmds) |> List.map(World.cmdKey);
        Assert.assertEq(expected = ("Add", 1, 5, 0) :: Nil, cmdKeys);
        // pos 不変（bind は動かさない）＝{5,2} のまま。
        Assert.assertEq(expected = Some((5, 2)), posT(EntityRef.Player(1), sysW))

    // ── (whiff) 空振り＝意図的 vacuity ─────────────────────────────────────────

    /// 壁ヒット（空振り）は sim が events を 1 つも積まない＝World 不変。evCount==0 を pin（呼び出し側は
    /// フィードバックログを出すだけで emit/replay をしない）。
    @Test
    def testStaffWhiffEmptyEvents(): Unit \ Assert =
        let cmds = playerCmds(0, {x = 2, y = 2}, 10, 10, 4);
        let hit = RayHit.HitWall({x = 4, y = 2});
        let dir = {x = 1, y = 0};
        let (_, evs) = driveStaffResolve(cmds, Staff.StaffEffect.Heal, dir, hit);
        Assert.assertEq(expected = 0, List.length(evs))

    // ── 出荷 seam（ecsResolveStaffCast）直駆動ハーネス ────────────────────────────
    //
    // 上の等価テストは `resolveStaffCast`（sim）と `applyEcsStaffSceneEffects`（World 反映）を分解して
    // 当てるだけで、実際に出荷される cutover seam `StaffCast.ecsResolveStaffCast` の
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
    /// 駆動。(cmdKey 列, 最終 World, log 列)。emit ループ/Nil-fallback/ViewReplay 配線を実踏する。
    def runStaffEcs(in: {cmds = List[World.Cmd], staff = Staff.StaffResource,
                         dir = {x = Int32, y = Int32}, hit = RayHit}):
            (List[(String, Int32, Int32, Int32)], World, List[String]) =
        region rc {
            let ((_, logs), keys, w) =
                TestUnitFixtures.withTracedBoardWorld(rc, seed(), floorTerrain(), in#cmds, () ->
                TestUnitFixtures.withMockBoard(boardFor(in#cmds), () ->
                TestUnitFixtures.withMockGame(() ->
                TestUnitFixtures.withMockAudio(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withNoopTween(() ->
                    withRecLogger(rc, () ->
                        StaffCast.ecsResolveStaffCast(0, dummyPlayer(), in#staff, in#dir, in#hit))))))));
            (keys, w, logs)
        }

    /// live orchestrator seam を traced harness + recording logger で駆動（whiff fallback の log/cmds オラクル）。
    def runStaffOracleLogged(in: {cmds = List[World.Cmd], staff = Staff.StaffResource,
                                  dir = {x = Int32, y = Int32}, hit = RayHit}):
            (List[(String, Int32, Int32, Int32)], World, List[String]) =
        region rc {
            let ((_, logs), keys, w) =
                TestUnitFixtures.withTracedBoardWorld(rc, seed(), floorTerrain(), in#cmds, () ->
                TestUnitFixtures.withMockBoard(boardFor(in#cmds), () ->
                TestUnitFixtures.withMockAudio(() ->
                TestUnitFixtures.withNoopAnim(() ->
                TestUnitFixtures.withNoopTween(() ->
                    withRecLogger(rc, () ->
                        StaffCast.ecsResolveStaffCast(0, dummyPlayer(), in#staff, in#dir, in#hit)))))));
            (keys, w, logs)
        }

    // ── (seam-a) whiff → World fallback の log 等価 ───────────────────────────────

    /// 空振り（壁 hit）で `ecsResolveStaffCast` は events=Nil を見て内包した whiff 処理（『届かなかった』ログ）へ fallback する。
    /// 出荷 seam の log/cmds がオラクル harness の whiff 駆動と一致することを固定。else 分岐（empty events を replay）が
    /// 誤って走ると『届かなかった』ログが 0 行になり oracleLogs と乖離して落ちる＝Nil-fallback を非 vacuous に pin。
    @Test
    def testStaffEcsSeamWhiffFallsBackToScene(): Unit \ Assert =
        let cmds = List.flatten(
            playerCmds(0, {x = 2, y = 2}, 10, 10, 4) :: playerCmds(1, {x = 5, y = 2}, 3, 20, 0) :: Nil);
        let hit = RayHit.HitWall({x = 4, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Heal);
        let args = {cmds = cmds, staff = staff, dir = dir, hit = hit};
        let (ecsKeys, ecsW, ecsLogs) = runStaffEcs(args);
        let (oracleKeys, _, oracleLogs) = runStaffOracleLogged(args);
        // fallback 等価: ecs seam の log/cmds がオラクル harness の whiff 駆動と一致。
        Assert.assertEq(expected = oracleLogs, ecsLogs);
        Assert.assertEq(expected = oracleKeys, ecsKeys);
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
    /// `Snap`→`snapRefTo`（World 権威 snap の dual-write）の二経路から。さらに `snapTo` は engine tween
    /// 退役後、描画位置スナップの `Cmd.SetRenderPos`（view 権威）も積む。`Cmd.Move` は絶対座標で冪等・RenderPos は
    /// 描画専用ゆえ最終 World（hp/pos）は不変。よって logical 契約は RenderPos を除いた **集合** 一致で表し
    /// （重複 Move を許容）、最終 World 等価を本丸の保証とする。raw list 長=4 も pin して emit の形を固定する。
    @Test
    def testStaffEcsSeamEmitsEventToCmds(): Unit \ Assert =
        let cmds = List.flatten(
            playerCmds(0, {x = 2, y = 2}, 10, 10, 0) :: enemyCmds(1, {x = 3, y = 2}, 5, 10) :: Nil);
        let hit = RayHit.HitEnemy(1, {x = 3, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Blowback);
        let (ecsKeys, ecsW, _) = runStaffEcs({cmds = cmds, staff = staff, dir = dir, hit = hit});
        let (simW, evs) = driveStaffResolve(cmds, Staff.StaffEffect.Blowback, dir, hit);
        // cross-check: 出荷 seam が積んだ cmdKey 集合 == sim events の eventToCmds 集合（emit 配線の固定）。
        let simKeys = evs |> List.flatMap(World.eventToCmds) |> List.map(World.cmdKey);
        // seam は sim の logical cmds に加え、view 権威の render snap（`snapTo` の `SetRenderPos`＝engine tween
        // 退役後の描画位置スナップ）も積む。sim event 代数（eventToCmds）は logical のみゆえ、RenderPos を
        // 除いた集合で eventToCmds 一致を見る。
        let ecsLogicalKeys = ecsKeys |> List.filter(k -> { let (name, _, _, _) = k; name != "RenderPos" });
        Assert.assertEq(expected = List.toSet(simKeys), List.toSet(ecsLogicalKeys));
        // golden pin: seam の集合 = {Damaged(enemy,4)→SetHp, Moved(enemy,{12,2})→Move, snapTo→RenderPos}（literal で固定）。
        Assert.assertEq(expected = Set#{("SetHp", 1000001, 4, 0), ("Move", 1000001, 12, 2), ("RenderPos", 1000001, 0, 0)}, List.toSet(ecsKeys));
        // 三経路 emit の形: SetHp×1 + Move×2（replay snapRefTo の冪等 dual-write）+ RenderPos×1（snapTo）= raw 4 件。
        Assert.assertEq(expected = 4, List.length(ecsKeys));
        // 最終 World 等価: seam の applyCmd 経路 == driveStaffResolve の applyEventToWorld 経路（敵 hp/pos）。
        let proj = w -> (World.hpOf(EntityRef.Enemy(1), w), posT(EntityRef.Enemy(1), w));
        Assert.assertEq(expected = proj(simW), proj(ecsW));
        Assert.assertEq(expected = (Some(4), Some((12, 2))), proj(ecsW))

    // ── (Blowback × 味方) ally 分岐の等価 pin（生存・撃破）─────────────────────────

    /// ふきとばし × 味方(生存): 味方 hp5→4・hitCell{3,2} から右へ knockbackPath で壁手前{12,2}へ着地。
    /// orchestrator（Damaged+Moved）と sim（Damaged+Moved）の (味方 hp, pos) が一致し、
    /// (4,{12,2}) を pin（ally 生存分岐＝Damaged raw :: Moved を踏む）。
    @Test
    def testStaffBlowbackAllySurvivesEqualsSim(): Unit \ Assert =
        let cmds = List.flatten(
            playerCmds(0, {x = 2, y = 2}, 10, 10, 0) :: playerCmds(1, {x = 3, y = 2}, 5, 10, 0) :: Nil);
        let hit = RayHit.HitPlayer(1, {x = 3, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Blowback);
        let oracleW = runStaffOracle({cmds = cmds, staff = staff, dir = dir, hit = hit});
        let (sysW, evs) = driveStaffResolve(cmds, Staff.StaffEffect.Blowback, dir, hit);
        Assert.assertEq(expected = true, List.length(evs) > 0);
        let proj = w -> (World.hpOf(EntityRef.Player(1), w), posT(EntityRef.Player(1), w));
        // 等価: 1 ダメージ + 着地後の (味方 hp, pos) が オラクルと一致。
        Assert.assertEq(expected = proj(oracleW), proj(sysW));
        // 独立 pin: hp5→4・{3,2}→{12,2}。
        Assert.assertEq(expected = (Some(4), Some((12, 2))), proj(sysW))

    /// ふきとばし × 味方(撃破): 味方 hp1→0。sim の ally 撃破分岐（StaffSystem.flix:93-94 の `else if dmgRes#isDead`）は
    /// **Damaged raw のみ**＝Dying/ViewFx を出さない（敵撃破は hard-0+Dying ゆえ対称性の取り違えが起きやすい）。
    /// orchestrator（死亡演出なし）と (味方 hp, dying) が一致し、(0,false) を pin。
    /// ally に Dying を誤発火させると dying=true に転んでここが落ちる。evCount=1（Moved も無い）も pin。
    @Test
    def testStaffBlowbackAllyKillEqualsSim(): Unit \ Assert =
        let cmds = List.flatten(
            playerCmds(0, {x = 2, y = 2}, 10, 10, 0) :: playerCmds(1, {x = 3, y = 2}, 1, 10, 0) :: Nil);
        let hit = RayHit.HitPlayer(1, {x = 3, y = 2});
        let dir = {x = 1, y = 0};
        let staff = staffOf(Staff.StaffEffect.Blowback);
        let oracleW = runStaffOracle({cmds = cmds, staff = staff, dir = dir, hit = hit});
        let (sysW, evs) = driveStaffResolve(cmds, Staff.StaffEffect.Blowback, dir, hit);
        Assert.assertEq(expected = true, List.length(evs) > 0);
        let proj = w -> (World.hpOf(EntityRef.Player(1), w), World.isDyingOf(EntityRef.Player(1), w));
        // 等価: 味方撃破後の (hp, dying) が オラクルと一致（ally は Dying/Died を出さない）。
        Assert.assertEq(expected = proj(oracleW), proj(sysW));
        // 独立 pin: hp=0・dying=false（ally に Dying 無し）・evCount=1（Damaged のみ・Moved 無し）。
        Assert.assertEq(expected = (Some(0), false), proj(sysW));
        Assert.assertEq(expected = 1, List.length(evs))

}
