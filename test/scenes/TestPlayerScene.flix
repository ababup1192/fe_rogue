// PlayerScene のテスト
//
// PlayerScene は moveTo(target) で gridPos を即更新し、見た目の補間は engine の
// `Tween` モジュールに委ねる。壁判定は BoardLogic の責務なので PlayerScene 自身は考えない。
//
// 検証する観点:
//   - moveTo が gridPos を即更新する（world 座標は tween がまだ進めていないので元のまま）
//   - moveTo が Tween をスケジュールし、tickAll で target の world 座標に snap する
//   - tween 進行中は isMoving が true、snap 後は false（Tween.Scheduler.isActive の委譲）
//
// 個々の tween の advance/snap の正しさ自体は engine 層の TestTween で検証済みなので、
// ここでは「moveTo → tickAll で実際に target に到達する」という end-to-end の繋がりのみ確認する。
//
// テスト用 tileSize は 16、初期グリッドは PlayerScene.initialGrid() = (5, 5)。

mod TestPlayerScene {

    // ========================================================================
    // ヘルパー — テスト共通のシーン構築・取り出し
    // ========================================================================

    /// テスト用 tileSize（PlayerScene.scene.json と整合）
    def testTileSize(): Float64 = 16.0

    /// テスト用ワールド座標換算（マップ globalPos が原点なので local == world）
    def testGridToWorld(coords: Vec2.Vec2i): Vec2.Vec2 =
        let s = testTileSize();
        let v = Vec2.fromI(coords);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    /// テスト用 MapSnapshot — 床のみ・13×13 サイズ・grid↔world は testGridToWorld で固定
    def testSnapshot(): MapSnapshot =
        {
            tileSize    = testTileSize(),
            usedRect    = {position = Vec2.zeroI(), size = ({x = 13, y = 13}: Vec2.Vec2i)},
            isWall      = _ -> false,
            isFloor     = _ -> true,
            mapToLocal  = c -> testGridToWorld(c),
            gridToWorld = c -> testGridToWorld(c)
        }

    /// Tween.Scheduler のスタブ handler。schedule の登録を捨てて何もしない。
    /// PlayerScene.moveTo の gridPos 更新だけを検証したいテスト用。
    def withNoopTween(thunk: Unit -> a \ ef): a \ (ef - Tween.Scheduler) =
        run { thunk() } with handler Tween.Scheduler {
            def schedule(_, k) = k()
            def isActive(_, k) = k(false)
            def cancel(_, k) = k()
            def consumeUpdates(_, k) = k(Nil)
        }

    /// プレイヤー 1 体だけのシーンを作る（JSON ロードを介さず Marker2D を直接構築）。
    /// 初期 gridPos は PlayerScene.initialGrid()、pos はそれと整合する pixel 座標。
    def emptyPlayerScene(): Scene[NodeTag] =
        let initial = PlayerScene.initialGrid();
        let pos = testGridToWorld(initial);
        let marker = Marker2D.make(pos);
        Scene.empty()
            |> Scene.addNode("Player",
                EngineNode.Marker2DWithState(marker,
                    NodeTag.Player({gridPos = initial})))

    /// プレイヤーのワールド座標を取り出す
    def playerWorldPos(scene: Scene[NodeTag]): Vec2.Vec2 =
        Scene.globalPositionAt(PlayerScene.playerPath(), scene)

    /// scene 内 Player の (marker, data) を moveTo に渡し、 戻り値で scene を更新する。
    /// 直接 PlayerScene.moveTo を呼ぶと (marker, data) の取り出し / scene 書き戻しが
    /// 各テストに散らばるため、 1 か所に閉じ込める薄いラッパ。
    def applyMove(map: MapSnapshot, target: Vec2.Vec2i, scene: Scene[NodeTag]):
            Scene[NodeTag] \ Tween.Scheduler =
        match Scene.getEngineNode(PlayerScene.playerPath(), scene) {
            case Some(EngineNode.Marker2DWithState(marker, NodeTag.Player(data))) =>
                let (newMarker, newData) =
                    PlayerScene.moveTo(map, target, marker, data, scene);
                Scene.setEngineNode(PlayerScene.playerPath(),
                    EngineNode.Marker2DWithState(newMarker, NodeTag.Player(newData)),
                    scene)
            case _ => bug!("applyMove: expected Player at playerPath")
        }

    // ========================================================================
    // moveTo — gridPos を即更新、tween は engine に委譲
    // ========================================================================

    /// moveTo 直後: gridPos は target に更新される。world 座標は tween がまだ進んでいないので
    /// 元の位置のまま（noop tween で確認）
    @Test
    def testMoveToUpdatesGridPosImmediately(): Unit \ Assert =
        let target: Vec2.Vec2i = {x = 6, y = 5};
        let initialPos = testGridToWorld(PlayerScene.initialGrid());
        let after = withNoopTween(() ->
            applyMove(testSnapshot(), target, emptyPlayerScene()));
        let data = PlayerScene.getPlayerData(after);
        let pos = playerWorldPos(after);
        Assert.assertEq(
            expected = (6, 5, initialPos#x, initialPos#y),
            (data#gridPos#x, data#gridPos#y, pos#x, pos#y))

    /// moveTo 後の流れを実 Tween で end-to-end 検証する。
    ///
    ///   moveTo 直後:        world は initial のまま、isMoving = true（tween アクティブ）
    ///   tickAll(1.0) 後:    world は target に snap、isMoving = false（tween 終了）
    ///
    /// 1.0 秒は slideDuration (= 16/120 ≈ 0.133 秒) より十分大きいので必ず snap する。
    /// Player(5,5) → (6,5) なので initial = (88, 88), target = (104, 88)
    /// （16 × 5 + 8 = 88、16 × 6 + 8 = 104）。
    @Test
    def testMoveToSchedulesTweenAndSnaps(): Unit \ Assert =
        region rc {
            let target: Vec2.Vec2i = {x = 6, y = 5};
            let initialWorld = testGridToWorld(PlayerScene.initialGrid());
            let targetWorld = testGridToWorld(target);
            let result = run {
                let scene1 = applyMove(testSnapshot(), target, emptyPlayerScene());
                let posBefore = playerWorldPos(scene1);
                let activeBefore = PlayerScene.isMoving();
                let scene2 = Tween.tickAll(1.0, scene1);
                let posAfter = playerWorldPos(scene2);
                let activeAfter = PlayerScene.isMoving();
                (posBefore#x, posBefore#y, activeBefore,
                 posAfter#x, posAfter#y, activeAfter)
            } with Tween.withScheduler(rc);
            Assert.assertEq(
                expected = (initialWorld#x, initialWorld#y, true,
                             targetWorld#x, targetWorld#y, false),
                result)
        }
}
