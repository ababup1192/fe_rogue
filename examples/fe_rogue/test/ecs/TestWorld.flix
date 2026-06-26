// World（S0 足場）のテスト — scene→World 一方向 sync が id 集合と tick を正しく写すか。
// 最小 scene は TestCombatScene.battleScene と同じ「World ノード＋直接 addChildAt」パターン。

mod TestWorld {

    def playerData(id: Int32): PlayerScene.Data = playerDataS(id, Nil)

    def playerDataS(id: Int32, statuses: List[StatusSystem.Status]): PlayerScene.Data = {
        id                = id,
        statuses          = statuses,
        classId           = "test_player",
        gridPos           = {x = 2, y = 2},
        moveTiles         = 4,
        hp                = 10,
        waited            = false,
        attackTargetId    = None,
        resource          = TestUnitFixtures.testResource(4, 10),
        weapons           = TestUnitFixtures.testWeapon() :: Nil,
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
        rings             = Nil,
        ringEquipped      = false,
        followUpUsed      = false
    }

    def enemyData(id: Int32): EnemyScene.Data = {
        id             = id,
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

    /// World 配下に player 2 体（id 0,1）＋ enemy 1 体（id 5）を直接挿した最小 scene。
    def sampleScene(): Scene[NodeTag] =
        let worldM = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        let mk = () -> Marker2D.make(Vec2.zero());
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(worldM, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(mk(), NodeTag.Player(playerData(0))))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(1),
                EngineNode.Marker2DWithState(mk(), NodeTag.Player(playerData(1))))
            |> Scene.addChildAt(MapScene.worldPath(), EnemyScene.enemyName(5),
                EngineNode.Marker2DWithState(mk(), NodeTag.Enemy(enemyData(5))))

    /// syncFromScene が player/enemy の id 集合を写し、tick を 1 進める。
    @Test
    def testSyncFromScene(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(sampleScene(), World.empty());
        Assert.assertEq(
            expected = (2, 1, 1),
            (Set.size(w#playerIds), Set.size(w#enemyIds), w#tick))

    /// id の実値も検証（player/enemy の取り違えを直接捕捉）。
    @Test
    def testSyncFromSceneIds(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(sampleScene(), World.empty());
        Assert.assertEq(expected = (Set#{0, 1}, Set#{5}), (w#playerIds, w#enemyIds))

    /// 空 scene なら id 集合は空、tick は進む。
    @Test
    def testSyncFromEmptyScene(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(Scene.empty(), World.empty());
        Assert.assertEq(
            expected = (0, 0, 1),
            (Set.size(w#playerIds), Set.size(w#enemyIds), w#tick))

    // ── S1a: statuses store ──

    /// player 0 に immobilize(残3) を持たせた scene を World に mirror する。
    def sceneWithStatus(): Scene[NodeTag] =
        let worldM = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(), EngineNode.Marker2DWithState(worldM, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()),
                    NodeTag.Player(playerDataS(0, StatusSystem.immobilizeFor(3) :: Nil))))

    def firstRemaining(m: Map[EntityId, List[StatusSystem.Status]], id: EntityId): Int32 =
        Map.get(id, m) |> Option.flatMap(List.head) |> Option.map(s -> s#remaining) |> Option.getWithDefault(-1)

    /// syncFromScene が statuses を player store に写す（残3 がそのまま）。
    @Test
    def testSyncMirrorsStatuses(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(sceneWithStatus(), World.empty());
        Assert.assertEq(expected = 3, firstRemaining(w#playerStatuses, 0))

    /// tickStatuses（StatusSystem.tick 再利用）で残ターンが 1 減る（残3→2）。
    @Test
    def testTickStatuses(): Unit \ Assert =
        let synced = World.syncFromScene(sceneWithStatus(), World.empty());
        let World.World(w) = World.tickStatuses(synced);
        Assert.assertEq(expected = 2, firstRemaining(w#playerStatuses, 0))

    // ── S1b: World→scene write-back（逆向き矢印）と parallel-run 同値実証 ──

    /// scene の player 0 の Data#statuses を読む（write-back の検証用）。
    def sceneFirstRemaining(scene: Scene[NodeTag], id: Int32): Int32 =
        PlayerScene.getAll(scene)
            |> List.find(d -> d#id == id)
            |> Option.flatMap(d -> List.head(d#statuses))
            |> Option.map(s -> s#remaining)
            |> Option.getWithDefault(-1)

    /// syncStatusesToScene が World の statuses を scene の Data#statuses へ書き戻す（残3 が往復で保たれる）。
    @Test
    def testSyncStatusesToSceneRoundTrip(): Unit \ Assert =
        let scene  = sceneWithStatus();
        let synced = World.syncFromScene(scene, World.empty());
        let back   = World.syncStatusesToScene(synced, scene);
        Assert.assertEq(expected = 3, sceneFirstRemaining(back, 0))

    /// parallel-run 同値実証: 「World 経路（tickStatuses→write-back で scene を更新）」と
    /// 「現行 scene 経路（StatusSystem.tick を直接 Data#statuses に畳む）」が同じ残ターンを与える。
    /// これが一致する限り、turn 開始 tick を World へ flip しても挙動は不変（S1b 後段の前提）。
    @Test
    def testTickParallelRunMatchesScenePath(): Unit \ Assert =
        let scene = sceneWithStatus();
        // World 経路: sync → tickStatuses → scene へ write-back → scene から読む。
        let worldPath =
            World.syncStatusesToScene(World.tickStatuses(World.syncFromScene(scene, World.empty())), scene)
                |> (s -> sceneFirstRemaining(s, 0));
        // scene 経路: 既存と同じく Data#statuses に StatusSystem.tick を直接畳む。
        let scenePath =
            PlayerScene.mapPlayer(0, d -> {statuses = StatusSystem.tick(d#statuses) | d}, scene)
                |> (s -> sceneFirstRemaining(s, 0));
        Assert.assertEq(expected = scenePath, worldPath)

    // ── S2: hp の read-model mirror ──

    /// syncFromScene が hp を World store へ mirror する（player 0,1／enemy 5 とも scene の hp と一致）。
    /// 権威は scene のまま＝この mirror は query/セーブ用の read-model。
    @Test
    def testSyncMirrorsHp(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(sampleScene(), World.empty());
        // sampleScene の fixture は player/enemy とも hp=10。
        Assert.assertEq(
            expected = (Some(10), Some(10), Some(10)),
            (Map.get(0, w#playerHp), Map.get(1, w#playerHp), Map.get(5, w#enemyHp)))

    /// hp mirror が scene の各 Data#hp と完全一致する（parallel-run 同値：World hp == scene hp）。
    @Test
    def testHpMirrorEqualsScene(): Unit \ Assert =
        let scene = sampleScene();
        let World.World(w) = World.syncFromScene(scene, World.empty());
        let scenePlayerHp = PlayerScene.getAll(scene)
            |> List.foldLeft((m, d) -> Map.insert(d#id, d#hp, m), Map.empty());
        Assert.assertEq(expected = scenePlayerHp, w#playerHp)
}
