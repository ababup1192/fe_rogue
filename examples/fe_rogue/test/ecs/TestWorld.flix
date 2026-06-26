// World（S0 足場）のテスト — scene→World 一方向 sync が id 集合と tick を正しく写すか。
// 最小 scene は TestCombatScene.battleScene と同じ「World ノード＋直接 addChildAt」パターン。

mod TestWorld {

    def playerData(id: Int32): PlayerScene.Data = {
        id                = id,
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
        statuses          = Nil,
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
}
