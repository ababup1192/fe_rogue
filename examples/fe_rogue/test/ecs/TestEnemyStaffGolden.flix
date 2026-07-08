// 敵クレリックの Bind / Stopgap 詠唱の frozen pin テスト（player の TestStaffGolden を敵側へミラー）。
//
// caster=Enemy を `StaffSystem.resolveStaffCast` に渡すと player 杖と同じ sim/emit/World-反映 経路を踏む。
// Bind は view fx 0・Moved 無＝World 不変ゆえ `ViewReplay.replay` は呼ばない。
//
// 照合方針（すべて ECS seam 単独を駆動し、凍結リテラルへ pin する）:
//   (A) seam     … `ecsResolveEnemyStaff` を traced harness で駆動し、emit した cmdKey 列と
//                   `applyEcsStaffSceneEffects` 後の味方 #statuses を具体値リテラルで pin。
//   (B) targeting … pub `castableHitPlayer` 直叩きで (id, RayHit) 透過（cell 含む）を pin・停止中味方は None。
//   (C) threading … `enemyTryStaff` の forM 鎖の連結を固定。
//   (D) statuses  … 味方 #statuses（World 権威）を凍結値へ pin。
//   (E) log      … 『かなしばりにした』hit-log をちょうど 1 行へ pin（黙って落ちる/二重化する退行を捕捉）。
// テスト本体に match を書かず worldStatusT / castTargetT の射影ヘルパー経由・期待値は具体値リテラル。
// RayHit は Eq を持たないため (tag, id, x, y) タプルへ射影して比較する。
mod TestEnemyStaffGolden {

    // 固定 seed（Bind は draw 0 ゆえ outcome は seed 非依存。harness の World 種に使うだけ）。
    def seed(): Int64 = 12345i64

    // ── fixtures（World.Cmd 列）───────────────────────────────────────────────

    /// 味方 fixture の spawn Cmd 列。`statuses` で停止中ケースを作り分ける。
    def playerCmds(id: Int32, pos: {x = Int32, y = Int32},
                    statuses: List[StatusSystem.Status]): List[World.Cmd] =
        let ref = World.EntityRef.Player(id);
        List.append(
            TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(id, pos)),
            World.Cmd.Seed(ref, statuses) :: Nil)

    /// 敵 fixture（クレリック詠唱者）の spawn Cmd 列。
    def enemyCmds(id: Int32, pos: {x = Int32, y = Int32}): List[World.Cmd] =
        TestWorldFixtures.enemyCmds(TestWorldFixtures.unitSpec(id, pos))

    /// 13×13 の壁なし floor 地形（`World.mapSnapshot` / mock board 用の値 fixture）。
    def floorTerrain(): MapSnapshot = TestWorldFixtures.floorSnapshot({w = 13, h = 13})

    /// `cmds` を地形付きで World.empty() に適用した World（castableHitPlayer 直叩き用）。
    def worldFor(cmds: List[World.Cmd]): World =
        TestWorldFixtures.worldOf(World.Cmd.SetMapSnapshot(Some(floorTerrain())) :: cmds)

    /// `cmds` から Board を組む（`withMockBoard` 供給用）。harness 内部の World と同じ Cmd 列を
    /// 同じ地形に適用して組むので、trace ハーネスが seed する World と一致する。
    def boardFor(cmds: List[World.Cmd]): Board =
        World.boardOf(worldFor(cmds)) |> Option.getWithDefault({map = floorTerrain(), pieces = Nil})

    // ── harness ───────────────────────────────────────────────────────────────

    /// 出荷 seam `ecsResolveEnemyStaff`（敵 eid → `in#effect` 詠唱）を traced harness + 副作用モックで駆動。
    /// (cmdKey 列, 最終 World)。emit ループ・eventToCmds 配線・World 反映を実踏する。
    /// effect を引数化して Bind/Stopgap 両対応。
    def runEnemyStaffEcs(in: {cmds = List[World.Cmd], eid = Int32, effect = Staff.StaffEffect,
                             dir = {x = Int32, y = Int32}, hit = RayHit}):
            (List[(String, Int32, Int32, Int32)], World) =
        region rc {
            let (_, keys, w) =
                TestUnitFixtures.withTracedBoardWorld(rc, seed(), floorTerrain(), in#cmds, () ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withNoopTween(() ->
                    StaffCast.ecsResolveEnemyStaff(in#eid, in#effect, in#dir, in#hit))));
            (keys, w)
        }


    /// `enemyTryStaff`（forM 鎖）を traced harness で駆動。
    def runEnemyTryStaff(in: {cmds = List[World.Cmd], eid = Int32,
                              origin = {x = Int32, y = Int32}, desc = String}):
            (Bool, World) =
        region rc {
            let (out, _, w) =
                TestUnitFixtures.withTracedBoardWorld(rc, seed(), floorTerrain(), in#cmds, () ->
                TestUnitFixtures.withMockBoard(boardFor(in#cmds), () ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withNoopTween(() ->
                    StaffCast.enemyTryStaff(in#eid, in#origin, in#desc)))));
            (out, w)
        }

    /// 記録ロガー: playerLog/enemyLog の文字列を時系列で集める（hit-log 等価オラクル用）。
    /// `withMockGameLogger` は drop するため、hit-log が本当に出たかを観測できない（TestStaffGolden と同型）。
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

    /// ECS seam `ecsResolveEnemyStaff`（敵 eid → `in#effect`）を記録ロガー付きで駆動し hit-log 列を返す。
    def runEnemyStaffEcsLogged(in: {cmds = List[World.Cmd], eid = Int32, effect = Staff.StaffEffect,
                                 dir = {x = Int32, y = Int32}, hit = RayHit}):
            List[String] =
        region rc {
            let (_, logs) =
                withRecLogger(rc, () ->
                TestUnitFixtures.withTracedBoardWorld(rc, seed(), floorTerrain(), in#cmds, () ->
                TestUnitFixtures.withNoopTween(() ->
                    StaffCast.ecsResolveEnemyStaff(in#eid, in#effect, in#dir, in#hit))));
            logs
        }


    // ── projections（test 本体に match を書かない射影ヘルパー）─────────────────────

    /// World の味方 statusEffects を Eq 可能な (effect, magnitude, remaining) 列へ射影。
    def worldStatusT(id: Int32, w: World): List[(StatusSystem.StatusEffect, Int32, Int32)] =
        World.statusEffectsOf(World.EntityRef.Player(id), w)
            |> List.map(s -> (s#effect, s#magnitude, s#remaining))

    /// RayHit を Eq 可能な (tag, id, x, y) タプルへ射影（RayHit は Eq 非導出）。
    def rayHitT(hit: RayHit): (String, Int32, Int32, Int32) = match hit {
        case RayHit.HitPlayer(id, c) => ("HitPlayer", id, c#x, c#y)
        case RayHit.HitEnemy(id, c)  => ("HitEnemy", id, c#x, c#y)
        case RayHit.HitWall(c)       => ("HitWall", 0, c#x, c#y)
        case RayHit.OutOfRange(c)    => ("OutOfRange", 0, c#x, c#y)
    }

    /// castableHitPlayer の戻りを (id, rayHitT) へ射影して比較可能にする。
    def castTargetT(o: Option[(Int32, RayHit)]): Option[(Int32, (String, Int32, Int32, Int32))] =
        o |> Option.map(pair -> let (id, h) = pair; (id, rayHitT(h)))

    // ── (A) seam: ecsResolveEnemyStaff の emit + World 反映を固定 ─────────────────

    /// 敵(eid=0) → 味方(tid=1) の Bind 詠唱を出荷 seam で駆動。
    ///   ① 単一 Afflicted(Player(1)) → Cmd.Add の cmdKey ("Add",1,5,0)（Immobilized 種別=5・mag=0・uid=1）を pin。
    ///   ② applyEcsStaffSceneEffects 反映後の味方 #statuses == (Immobilized,0,5)::Nil を pin。
    /// bindTurns を 3 へ退行させると ① の remaining(=4th slot は mag ゆえ不変だが World) と ② が落ちる。
    @Test
    def testEnemyStaffEcsSeam(): Unit \ Assert =
        let cmds = List.flatten(playerCmds(1, {x = 5, y = 2}, Nil) :: enemyCmds(0, {x = 2, y = 2}) :: Nil);
        let hit = RayHit.HitPlayer(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        let (ecsKeys, ecsW) = runEnemyStaffEcs({cmds = cmds, eid = 0, effect = Staff.StaffEffect.Bind, dir = dir, hit = hit});
        // ① emit ループの cmdKey 列リテラル（Afflicted→eventToCmds→Cmd.Add の実踏）＋
        //    applyEcsStaffSceneEffects の event 反映後 全置換 Seed（uid=1）。
        Assert.assertEq(expected = ("Add", 1, 5, 0) :: ("Seed", 1, 0, 0) :: Nil, ecsKeys);
        // ② 反映後の味方 statuses リテラル（statuses は World 権威＝World store を読む）。
        Assert.assertEq(expected = (StatusSystem.StatusEffect.Immobilized, 0, 5) :: Nil,
                        worldStatusT(1, ecsW))

    // ── (B) targeting: castableHitPlayer の (id, RayHit) 透過 + 停止中 None ───────────

    /// 敵 origin{2,2} から右レイで味方(id=1,{5,2})を捉える。(id, RayHit) を透過し cell も透過する。
    @Test
    def testCastableHitPlayerTransparent(): Unit \ Assert =
        let cmds = playerCmds(1, {x = 5, y = 2}, Nil);
        let w = worldFor(cmds);
        let board = boardFor(cmds);
        // 停止判定は World statuses を読む＝fixture Cmd で seed した World を渡す。
        let got = TestUnitFixtures.withWorldQuery(w, () ->
            StaffCast.castableHitPlayer({x = 2, y = 2}, Dir4.Right, board));
        // id=1 と RayHit.HitPlayer(1, {5,2}) を両方透過。
        Assert.assertEq(expected = Some((1, ("HitPlayer", 1, 5, 2))), castTargetT(got))

    /// 既に停止中の味方は castableHitPlayer が None（無駄詠唱を避ける gate の温存）。
    @Test
    def testCastableHitPlayerImmobilizedNone(): Unit \ Assert =
        let cmds = playerCmds(1, {x = 5, y = 2}, StatusSystem.immobilizeFor(5) :: Nil);
        let w = worldFor(cmds);
        let board = boardFor(cmds);
        let got = TestUnitFixtures.withWorldQuery(w, () ->
            StaffCast.castableHitPlayer({x = 2, y = 2}, Dir4.Right, board));
        Assert.assertEq(expected = (None: Option[(Int32, (String, Int32, Int32, Int32))]), castTargetT(got))

    // ── (C) threading: enemyTryStaff forM 鎖（ECS 分岐）─────────────────────────

    /// クレリック_T2(=Bind) が直線上の未停止味方(id=1)へ詠唱成立。forM の effect/dir/hit/targetId 連結が
    /// 正しく繋がって味方 #statuses が (Immobilized,0,5) になる（#statuses 値は (D) が pin。
    /// ここは forM 鎖の連結固定が目的）。
    @Test
    def testEnemyTryStaffThreadsToEcs(): Unit \ Assert =
        let cmds = List.flatten(playerCmds(1, {x = 5, y = 2}, Nil) :: enemyCmds(0, {x = 2, y = 2}) :: Nil);
        let (out, w) = runEnemyTryStaff({cmds = cmds, eid = 0, origin = {x = 2, y = 2}, desc = "クレリック_T2"});
        // 詠唱成立 → true・味方 statuses（World 権威）を pin（forM 鎖の連結固定）。
        let statuses = if (out) worldStatusT(1, w) else Nil;
        Assert.assertEq(expected = (StatusSystem.StatusEffect.Immobilized, 0, 5) :: Nil, statuses)

    // ── (D) statuses: 味方 #statuses（World 権威）を凍結値へ pin ──────────

    /// `ecsResolveEnemyStaff` を駆動し、味方(id=1)の statuses（World 権威）を
    /// 凍結値 (Immobilized,0,5) へ pin＝敵 applyEcsStaffSceneEffects の取り違えを敵テスト単独で捕捉。
    @Test
    def testEnemyStaffEcsStatuses(): Unit \ Assert =
        let cmds = List.flatten(playerCmds(1, {x = 5, y = 2}, Nil) :: enemyCmds(0, {x = 2, y = 2}) :: Nil);
        let hit = RayHit.HitPlayer(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        let (_, ecsW)    = runEnemyStaffEcs({cmds = cmds, eid = 0, effect = Staff.StaffEffect.Bind, dir = dir, hit = hit});
        Assert.assertEq(expected = (StatusSystem.StatusEffect.Immobilized, 0, 5) :: Nil,
                        worldStatusT(1, ecsW))

    // ── (E) log: 『かなしばりにした』hit-log をちょうど 1 行へ pin ──────────

    /// `ecsResolveEnemyStaff` を記録ロガーで駆動し『かなしばりにした』hit-log を pin。hit-log は #statuses 契約外
    /// ゆえ別 pin＝log が黙って落ちる退行を捕捉する。「ちょうど 1 行」を pin（0=ドロップ / 2=二重を排除）。
    @Test
    def testEnemyStaffEcsLog(): Unit \ Assert =
        let cmds = List.flatten(playerCmds(1, {x = 5, y = 2}, Nil) :: enemyCmds(0, {x = 2, y = 2}) :: Nil);
        let hit = RayHit.HitPlayer(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        // hit-log をちょうど 1 行で pin（落とさない/二重にしない）。
        let ecsLogs    = runEnemyStaffEcsLogged({cmds = cmds, eid = 0, effect = Staff.StaffEffect.Bind, dir = dir, hit = hit});
        Assert.assertEq(expected = 1, List.length(ecsLogs))

    // ── (Stopgap) 敵詠唱 bind + warp + 2 行ログの pin ──────────────────

    /// player pos を Eq 可能な (x,y) タプルへ射影。
    def posT(id: Int32, w: World): Option[(Int32, Int32)] =
        World.posOf(World.EntityRef.Player(id), w) |> Option.map(p -> (p#x, p#y))

    /// 敵(eid=0) → 味方(tid=1) の Stopgap 詠唱: 完全停止 + 階段{8,8}へワープ。`ecsResolveEnemyStaff` を駆動し
    /// #statuses / pos を凍結値へ pin＝warp 先 {8,8} と (Immobilized,0,5)。
    @Test
    def testEnemyStopgapEcs(): Unit \ Assert =
        let cmds = List.flatten(
            playerCmds(1, {x = 5, y = 2}, Nil)
                :: enemyCmds(0, {x = 2, y = 2})
                :: (World.Cmd.SetStairs(Some({x = 8, y = 8})) :: Nil)
                :: Nil);
        let hit = RayHit.HitPlayer(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        // bind + warp 先 {8,8} を凍結値で pin（statuses は World 権威）。
        let (_, ecsW)    = runEnemyStaffEcs({cmds = cmds, eid = 0, effect = Staff.StaffEffect.Stopgap, dir = dir, hit = hit});
        Assert.assertEq(expected = (StatusSystem.StatusEffect.Immobilized, 0, 5) :: Nil, worldStatusT(1, ecsW));
        Assert.assertEq(expected = Some((8, 8)), posT(1, ecsW))

    /// Stopgap 敵詠唱の hit-log: [かなしばり, 階段の方へ] の 2 行（bindPlayerLog + warpPlayerLog）を pin＝
    /// warp ログが黙って落ちる退行を捕捉。
    @Test
    def testEnemyStopgapLog(): Unit \ Assert =
        let cmds = List.flatten(
            playerCmds(1, {x = 5, y = 2}, Nil)
                :: enemyCmds(0, {x = 2, y = 2})
                :: (World.Cmd.SetStairs(Some({x = 8, y = 8})) :: Nil)
                :: Nil);
        let hit = RayHit.HitPlayer(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        // bind + warp の 2 行を pin（どちらも落とさない）。
        let ecsLogs    = runEnemyStaffEcsLogged({cmds = cmds, eid = 0, effect = Staff.StaffEffect.Stopgap, dir = dir, hit = hit});
        Assert.assertEq(expected = 2, List.length(ecsLogs))

}
