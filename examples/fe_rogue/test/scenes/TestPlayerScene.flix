// PlayerScene のテスト（multi-player 版）
//
// PlayerScene は moveTo(id, target, ...) で gridPos を即更新し、見た目の補間は engine の
// `Tween` モジュールに委ねる。壁判定は Board の責務なので PlayerScene 自身は考えない。
//
// 検証する観点:
//   - moveTo が gridPos を即更新する
//   - moveTo が Tween をスケジュールし、tickAll で target の world 座標に snap する
//   - tween 進行中は isMoving が true、snap 後は false
//
// テスト用 tileSize は 16。`PlayerScene.add` を介さず Marker2D を直接構築する。

mod TestPlayerScene {

    /// テスト用 tileSize
    def testTileSize(): Float64 = 16.0

    /// テスト用ワールド座標換算
    def testGridToWorld(coords: {x = Int32, y = Int32}): Vec2.Vec2 =
        let s = testTileSize();
        let v = Vec2i.toVec2(coords);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    /// テスト用 MapSnapshot — 床のみ・13×13・grid↔world は testGridToWorld
    def testSnapshot(): MapSnapshot =
        {
            tileSize     = testTileSize(),
            usedRect     = {position = Vec2i.zero(), size = ({x = 13, y = 13}: {x = Int32, y = Int32})},
            isWall       = _ -> false,
            isFloor      = _ -> true,
            mapToLocal   = c -> testGridToWorld(c),
            gridToWorld  = c -> testGridToWorld(c),
            moduleOfCell = _ -> None
        }

    /// Tween.Scheduler のスタブ handler。schedule の登録を捨てて何もしない。
    def withNoopTween(thunk: Unit -> a \ ef): a \ (ef - Tween.Scheduler) =
        run { thunk() } with handler Tween.Scheduler {
            def schedule(_, k) = k()
            def isActive(_, k) = k(false)
            def cancel(_, k) = k()
            def consumeUpdates(_, k) = k(Nil)
        }

    /// テスト用初期グリッド（PlayerScene.add の経由を回避）。
    def initialGrid(): {x = Int32, y = Int32} = {x = 5, y = 5}

    /// id=0 のプレイヤー 1 体だけのシーンを作る（JSON ロードを介さず Marker2D を直接構築）。
    /// PlayerScene.playerPath が World 配下を指すので、ここでも World Marker2D を挟む
    def emptyPlayerScene(): Scene[NodeTag] =
        let initial = initialGrid();
        let pos = testGridToWorld(initial);
        let marker = Marker2D.make(pos);
        let world = Marker2D.make(Vec2.zero())
            |> CanvasItem.setYSortEnabled(true);
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(marker,
                    NodeTag.Player({
                        id                = 0,
                        gridPos           = initial,
                        moveTiles         = 5,
                        hp                = 10,
                        waited            = false,
                        attackTargetId    = None,
                        resource          = TestUnitFixtures.testResource(5, 10),
                        weapons           = TestUnitFixtures.testWeapon() :: Nil,
                        selectedWeaponIdx = None
                    })))

    /// プレイヤー id のワールド座標を取り出す
    def playerWorldPos(id: Int32, scene: Scene[NodeTag]): Vec2.Vec2 =
        Scene.globalPositionAt(PlayerScene.playerPath(id), scene)

    /// scene 内 Player(id) の (marker, data) を moveTo に渡し、戻り値で scene を更新する。
    def applyMove(id: Int32, map: MapSnapshot, target: {x = Int32, y = Int32},
                   scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        match Scene.getEngineNode(PlayerScene.playerPath(id), scene) {
            case Some(EngineNode.Marker2DWithState(marker, NodeTag.Player(data))) =>
                let (newMarker, newData) =
                    PlayerScene.moveTo(id, map, target, marker, data, scene);
                Scene.setEngineNode(PlayerScene.playerPath(id),
                    EngineNode.Marker2DWithState(newMarker, NodeTag.Player(newData)),
                    scene)
            case _ => bug!("applyMove: expected Player at playerPath(${id})")
        }

    // ========================================================================
    // moveTo — gridPos を即更新、tween は engine に委譲
    // ========================================================================

    /// moveTo 直後: gridPos は target に更新される。world 座標は tween がまだ進んでいないので
    /// 元の位置のまま（noop tween で確認）
    @Test
    def testMoveToUpdatesGridPosImmediately(): Unit \ Assert =
        let target: {x = Int32, y = Int32} = {x = 6, y = 5};
        let initialPos = testGridToWorld(initialGrid());
        let after = withNoopTween(() ->
            applyMove(0, testSnapshot(), target, emptyPlayerScene()));
        let pos = playerWorldPos(0, after);
        let gridX = PlayerScene.getGridPos(0, after)#x;
        let gridY = PlayerScene.getGridPos(0, after)#y;
        Assert.assertEq(
            expected = (6, 5, initialPos#x, initialPos#y),
            (gridX, gridY, pos#x, pos#y))

    /// moveTo 後の流れを実 Tween で end-to-end 検証する。
    ///   moveTo 直後:        world は initial のまま、isMoving(0) = true
    ///   tickAll(1.0) 後:    world は target に snap、isMoving(0) = false
    @Test
    def testMoveToSchedulesTweenAndSnaps(): Unit \ Assert =
        region rc {
            let target: {x = Int32, y = Int32} = {x = 6, y = 5};
            let initialWorld = testGridToWorld(initialGrid());
            let targetWorld = testGridToWorld(target);
            let result = run {
                let scene1 = applyMove(0, testSnapshot(), target, emptyPlayerScene());
                let posBefore = playerWorldPos(0, scene1);
                let activeBefore = PlayerScene.isMoving(0);
                let scene2 = Tween.tickAll(1.0 |> Duration.seconds, scene1);
                let posAfter = playerWorldPos(0, scene2);
                let activeAfter = PlayerScene.isMoving(0);
                (posBefore#x, posBefore#y, activeBefore,
                 posAfter#x, posAfter#y, activeAfter)
            } with Tween.withScheduler(rc);
            Assert.assertEq(
                expected = (initialWorld#x, initialWorld#y, true,
                             targetWorld#x, targetWorld#y, false),
                result)
        }
}
