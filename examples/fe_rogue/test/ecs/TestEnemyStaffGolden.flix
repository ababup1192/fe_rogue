// 敵クレリックの Bind 詠唱 cutover の golden 等価テスト（player の TestStaffGolden を敵側へミラー）。
//
// 対象は **敵 → 味方** の Bind 詠唱のみ（Stopgap は legacy 温存・ECS 化対象外）。caster=Enemy を
// `StaffSystem.resolveStaffCast` に渡すだけで player 杖と同じ sim/emit/scene-反映 経路を踏む。
// Bind は view fx 0・Moved 無＝World/scene 不変ゆえ `ViewReplay.replay` は呼ばない。
//
// 照合方針:
//   (A) seam     … 出荷 seam `ecsResolveEnemyStaff` を traced harness で駆動し、emit した cmdKey 列と
//                   `applyEcsStaffSceneEffects` 後の味方 #statuses を具体値リテラルで pin。
//   (B) targeting … pub `castableHitPlayer` 直叩きで (id, RayHit) 透過（cell 含む）を pin・停止中味方は None。
//   (C) threading … `enemyTryStaff`（useEcsEnemyStaff=false ゆえ legacy 分岐）で forM 鎖の連結を固定。
//   (D) cross    … 単一 scene で legacy と ECS を駆動し、味方 #statuses を **直接** 突き合わせ（self-derive せず）。
// テスト本体に match を書かず sceneStatusT / castTargetT の射影ヘルパー経由・期待値は具体値リテラル。
// RayHit は Eq を持たないため (tag, id, x, y) タプルへ射影して比較する。
mod TestEnemyStaffGolden {

    use TestUnitFixtures.{testResource, testEnemyResource}

    // 固定 seed（Bind は draw 0 ゆえ outcome は seed 非依存。harness の World 種に使うだけ）。
    def seed(): Int64 = 12345i64

    // ── fixtures（TestStaffGolden を敵詠唱向けに縮約コピー）──────────────────────────

    /// 味方フィクスチャ（Bind の対象）。`statuses` で停止中ケースを作り分ける。
    def playerAt(id: Int32, gridPos: {x = Int32, y = Int32},
                  statuses: List[StatusSystem.Status]): PlayerScene.Data = {
        id                = id,
        classId           = "test_player",
        gridPos           = gridPos,
        moveTiles         = 4,
        hp                = 10,
        waited            = false,
        attackTargetId    = None,
        resource          = {magicAttack = 0 | testResource(4, 10)},
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
        statuses          = statuses,
        rings             = Nil,
        ringEquipped      = false,
        followUpUsed      = false
    }

    /// 敵フィクスチャ（クレリック詠唱者）。
    def enemyAt(id: Int32, gridPos: {x = Int32, y = Int32}): EnemyScene.Data = {
        id             = id,
        resourceId     = "test_enemy",
        gridPos        = gridPos,
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 3,
        hp             = 10,
        isDying        = false,
        attackTargetId = None,
        resource       = testEnemyResource(3, 10),
        weapon         = None,
        acted          = false,
        prevPos        = None,
        statuses       = Nil,
        ring           = None,
        followUpUsed   = false,
        bottleUsed     = false
    }

    /// 13×13 の壁なし floor map。
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

    def floorMapData(): MapScene.Data = {
        anchorOffset = {x = 0, y = 0},
        spawnGrid    = {x = 5, y = 5},
        placements   = RoomLayout.singleRoom(13, 13),
        roomCount    = 1,
        plan         = ({modulePaths = Nil, sideConnections = Nil, roomCount = 1}: DungeonGenerator.Plan)
    }

    // ── harness ───────────────────────────────────────────────────────────────

    /// 出荷 seam `ecsResolveEnemyStaff`（敵 eid → Bind）を traced harness + 副作用モックで駆動。
    /// (後 scene, cmdKey 列, 最終 World)。emit ループ・eventToCmds 配線・scene 反映を実踏する。
    def runEnemyStaffEcs(in: {scene = Scene[NodeTag], eid = Int32,
                             dir = {x = Int32, y = Int32}, hit = RayHit}):
            (Scene[NodeTag], List[(String, Int32, Int32, Int32)], World) =
        region rc {
            let (s, keys, w) =
                TestUnitFixtures.withTracedWorld(rc, seed(), in#scene, () ->
                TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(in#scene), () ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withNoopTween(() ->
                    StaffCastScene.ecsResolveEnemyStaff(in#eid, Staff.StaffEffect.Bind, in#dir, in#hit, in#scene)))));
            (s, keys, w)
        }

    /// legacy seam `enemyCastStaffLegacy`（敵 eid → tid へ Bind）を traced harness + 副作用モックで駆動。
    /// (後 scene, 最終 World)。cross-compare のオラクル。
    def runEnemyStaffLegacy(in: {scene = Scene[NodeTag], eid = Int32, tid = Int32}):
            (Scene[NodeTag], World) =
        region rc {
            let (s, _, w) =
                TestUnitFixtures.withTracedWorld(rc, seed(), in#scene, () ->
                TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(in#scene), () ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withNoopTween(() ->
                    StaffCastScene.enemyCastStaffLegacy(in#eid, Staff.StaffEffect.Bind, in#tid, in#scene)))));
            (s, w)
        }

    /// `enemyTryStaff`（forM 鎖。useEcsEnemyStaff=false ゆえ legacy 分岐）を traced harness で駆動。
    def runEnemyTryStaff(in: {scene = Scene[NodeTag], eid = Int32,
                              origin = {x = Int32, y = Int32}, desc = String}):
            Option[Scene[NodeTag]] =
        region rc {
            let (s, _, _) =
                TestUnitFixtures.withTracedWorld(rc, seed(), in#scene, () ->
                TestUnitFixtures.withMockBoard(BoardSnapshot.fromScene(in#scene), () ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withNoopTween(() ->
                    StaffCastScene.enemyTryStaff(in#eid, in#origin, in#desc, in#scene)))));
            s
        }

    // ── projections（test 本体に match を書かない射影ヘルパー）─────────────────────

    /// scene の味方 statuses を Eq 可能な (effect, magnitude, remaining) 列へ射影。
    def sceneStatusT(id: Int32, sc: Scene[NodeTag]): List[(StatusSystem.StatusEffect, Int32, Int32)] =
        PlayerScene.get(id, sc)
            |> Option.map(d -> d#statuses)
            |> Option.getWithDefault(Nil)
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

    // ── (A) seam: ecsResolveEnemyStaff の emit + scene 反映を固定 ─────────────────

    /// 敵(eid=0) → 味方(tid=1) の Bind 詠唱を出荷 seam で駆動。
    ///   ① 単一 Afflicted(Player(1)) → Cmd.Add の cmdKey ("Add",1,5,0)（Immobilized 種別=5・mag=0・uid=1）を pin。
    ///   ② applyEcsStaffSceneEffects 反映後の味方 #statuses == (Immobilized,0,5)::Nil を pin。
    /// bindTurns を 3 へ退行させると ① の remaining(=4th slot は mag ゆえ不変だが World) と ② が落ちる。
    @Test
    def testEnemyStaffEcsSeam(): Unit \ Assert =
        let caster = enemyAt(0, {x = 2, y = 2});
        let target = playerAt(1, {x = 5, y = 2}, Nil);
        let sc = sceneOf(target :: Nil, caster :: Nil);
        let hit = RayHit.HitPlayer(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        let (ecsScene, ecsKeys, _) = runEnemyStaffEcs({scene = sc, eid = 0, dir = dir, hit = hit});
        // ① emit ループの cmdKey 列リテラル（Afflicted→eventToCmds→Cmd.Add の実踏）＋
        //    S3: applyEcsStaffSceneEffects の post-mutation 全置換 Seed（uid=1）。
        Assert.assertEq(expected = ("Add", 1, 5, 0) :: ("Seed", 1, 0, 0) :: Nil, ecsKeys);
        // ② scene 反映後の味方 #statuses リテラル（applyEcsStaffSceneEffects Afflicted(Player) arm 共用）。
        Assert.assertEq(expected = (StatusSystem.StatusEffect.Immobilized, 0, 5) :: Nil,
                        sceneStatusT(1, ecsScene))

    // ── (B) targeting: castableHitPlayer の (id, RayHit) 透過 + 停止中 None ───────────

    /// 敵 origin{2,2} から右レイで味方(id=1,{5,2})を捉える。(id, RayHit) を透過し cell も透過する。
    @Test
    def testCastableHitPlayerTransparent(): Unit \ Assert =
        let target = playerAt(1, {x = 5, y = 2}, Nil);
        let sc = sceneOf(target :: Nil, Nil);
        let board = BoardSnapshot.fromScene(sc);
        let got = StaffCastScene.castableHitPlayer({x = 2, y = 2}, Staff.Direction.Right, board, sc);
        // id=1 と RayHit.HitPlayer(1, {5,2}) を両方透過。
        Assert.assertEq(expected = Some((1, ("HitPlayer", 1, 5, 2))), castTargetT(got))

    /// 既に停止中の味方は castableHitPlayer が None（無駄詠唱を避ける gate の温存）。
    @Test
    def testCastableHitPlayerImmobilizedNone(): Unit \ Assert =
        let target = playerAt(1, {x = 5, y = 2}, StatusSystem.immobilizeFor(5) :: Nil);
        let sc = sceneOf(target :: Nil, Nil);
        let board = BoardSnapshot.fromScene(sc);
        let got = StaffCastScene.castableHitPlayer({x = 2, y = 2}, Staff.Direction.Right, board, sc);
        Assert.assertEq(expected = (None: Option[(Int32, (String, Int32, Int32, Int32))]), castTargetT(got))

    // ── (C) threading: enemyTryStaff forM 鎖（legacy 分岐）─────────────────────────

    /// クレリック_T2(=Bind) が直線上の未停止味方(id=1)へ詠唱成立。useEcsEnemyStaff=false ゆえ legacy 分岐を
    /// 通り、forM の effect/dir/hit/targetId 連結が正しく繋がって味方 #statuses が (Immobilized,0,5) になる。
    @Test
    def testEnemyTryStaffThreadsToLegacy(): Unit \ Assert =
        let caster = enemyAt(0, {x = 2, y = 2});
        let target = playerAt(1, {x = 5, y = 2}, Nil);
        let sc = sceneOf(target :: Nil, caster :: Nil);
        let out = runEnemyTryStaff({scene = sc, eid = 0, origin = {x = 2, y = 2}, desc = "クレリック_T2"});
        // 詠唱成立 → Some(scene)・その scene の味方 #statuses を pin（forM 鎖の連結固定）。
        let statuses = out |> Option.map(s -> sceneStatusT(1, s)) |> Option.getWithDefault(Nil);
        Assert.assertEq(expected = (StatusSystem.StatusEffect.Immobilized, 0, 5) :: Nil, statuses)

    // ── (D) cross-compare: legacy #statuses == ECS #statuses（直接突き合わせ）──────────

    /// 単一 scene 上で legacy(`enemyCastStaffLegacy`) と ECS(`ecsResolveEnemyStaff`) を駆動し、味方(id=1)の
    /// #statuses を **直接** assertEq（self-derive せず）＝敵 applyEcsStaffSceneEffects / scene-threading の
    /// 取り違えを敵テスト単独で捕捉。加えて (Immobilized,0,5) を独立 pin して両者の偶然一致を排除。
    @Test
    def testEnemyStaffEcsEqualsLegacy(): Unit \ Assert =
        let caster = enemyAt(0, {x = 2, y = 2});
        let target = playerAt(1, {x = 5, y = 2}, Nil);
        let sc = sceneOf(target :: Nil, caster :: Nil);
        let hit = RayHit.HitPlayer(1, {x = 5, y = 2});
        let dir = {x = 1, y = 0};
        let (legacyScene, _) = runEnemyStaffLegacy({scene = sc, eid = 0, tid = 1});
        let (ecsScene, _, _) = runEnemyStaffEcs({scene = sc, eid = 0, dir = dir, hit = hit});
        // 直接突き合わせ: legacy #statuses == ECS #statuses。
        Assert.assertEq(expected = sceneStatusT(1, legacyScene), sceneStatusT(1, ecsScene));
        // 独立 pin: (Immobilized,0,5)（両者の偶然一致を排除）。
        Assert.assertEq(expected = (StatusSystem.StatusEffect.Immobilized, 0, 5) :: Nil,
                        sceneStatusT(1, ecsScene))

}
