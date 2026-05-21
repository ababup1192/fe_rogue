/// CursorScene のシーン操作と `snapToPlayer` の動作を検証する。
///
/// `add` の最も重要な性質は「**初期位置 = プレイヤーのグリッド位置**」と
/// 「初期 hover 状態 = None」の 2 点。味方ターン開始時にカーソルが味方の上から
/// 始まることで、Z で即座に味方を選んで移動フェーズに入れる UX を保証する。
///
/// `snapToPlayer` は敵ターン終了 / キャンセルのたびに呼ばれ、カーソルを味方に
/// 引き戻す責務を持つ。ホバー状態 (lastHoveredEnemyId) もここでリセットされる。
///
/// `physicsProcess` 経由のキー入力 → 移動 → ホバー検知の経路は `GameEngine.Game`
/// （キー押下） + `BoardQuery` + `GameLogger` + `Tween.Scheduler` の 4 種類の
/// effect が絡む統合シナリオなので、ここでは扱わず実機での動作確認に委ねる。
mod TestCursorScene {

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    def testTileSize(): Float64 = 16.0

    /// セル中心ピクセル座標（CursorScene / PlayerScene と同じ慣習）
    def cellCenter(c: {x = Int32, y = Int32}): Vec2.Vec2 =
        let s = testTileSize();
        let v = Vec2i.toVec2(c);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    /// テスト用 FontAtlas (loadScene が getFontAtlas を呼ばないので実値は使われないが
    /// `withMockGame` ハンドラの戻り値として必要)
    def testFontAtlas(): FontAtlas = {
        textureName = "font_test",
        fontSize    = 16.0,
        textureSize = 256.0,
        ascent      = 0.0,
        descent     = 0.0,
        lineGap     = 0.0,
        glyphs      = Map.empty()
    }

    /// CursorScene.add の {GameEngine.Game, Fs.FileRead} effect を discharge して
    /// pure に見せる test 用ラッパ。`@Test` は `\ Assert` 限定のため unchecked_cast で
    /// IO effect を消す (Fs.FileRead は flix test の CWD = examples/fe_rogue から
    /// 実ファイルを読む)。
    def cursorAddPure(scene: Scene[NodeTag]): Scene[NodeTag] =
        unchecked_cast(
            (run {
                run {
                    CursorScene.add(scene)
                } with handler GameEngine.Game {
                    def renderCommands(_, _, k)     = k(())
                    def initTileBuffer(_, k)        = k((0i32, 0i32))
                    def shouldClose(k)              = k(false)
                    def getDeltaTime(k)             = k(Duration.seconds(0.016))
                    def isKeyPressed(_, k)          = k(false)
                    def getMousePosition(k)         = k({x = 0.0, y = 0.0})
                    def isMouseButtonPressed(_, k)  = k(false)
                    def consumeScrollDelta(k)       = k(0.0)
                    def getFontAtlas(_, k)          = k(testFontAtlas())
                    def getViewportRect(k)          = k({position = Vec2.zero(), size = {x = 128.0, y = 128.0}})
                    def getTextureInfo(_, k)        = k(None)
                    def setCursor(_, k)             = k(())
                }
            } with Fs.FileRead.runWithIO)
            as _ \ {})

    /// Tween.Scheduler のスタブ。schedule / cancel を捨てて何もしない。
    /// snapToPlayer の動作確認時に Tween 実体を立ち上げないために使う。
    def withNoopTween(thunk: Unit -> a \ ef): a \ (ef - Tween.Scheduler) =
        run { thunk() } with handler Tween.Scheduler {
            def schedule(_, k) = k()
            def isActive(_, k) = k(false)
            def cancel(_, k) = k()
            def consumeUpdates(_, k) = k(Nil)
        }

    /// AnimationPlayer.Scheduler のスタブ。snag / 攻撃アニメは流さず、すべて停止扱い。
    def withNoopAnim(thunk: Unit -> a \ ef): a \ (ef - AnimationPlayer.Scheduler) =
        run { thunk() } with handler AnimationPlayer.Scheduler {
            def schedule(_, k) = k()
            def isPlaying(_, k) = k(false)
            def stop(_, k) = k()
            def cancelAll(k) = k()
            def activeOwners(k) = k(Nil)
            def consumeTick(_, k) = k(({propertyUpdates = Nil}: AnimationPlayer.Tick))
            def drainSignals(_, k) = k(({methods = Nil, finished = Nil}: AnimationPlayer.EventBundle))
        }

    /// プレイヤー id=0 1 体だけを (gridPos) に置いた scene を組む。
    /// JSON ロードを介さず Marker2D を直接構築する（PlayerScene.playerPath は
    /// World 配下を指すため、ここでも World Marker2D を挟む）。
    def sceneWithPlayer(gridPos: {x = Int32, y = Int32}): Scene[NodeTag] =
        let pos = cellCenter(gridPos);
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
                        gridPos           = gridPos,
                        moveTiles         = 5,
                        hp                = 10,
                        waited            = false,
                        attackTargetId    = None,
                        resource          = TestUnitFixtures.testResource(5, 10),
                        weapons           = TestUnitFixtures.testWeapon() :: Nil,
                        selectedWeaponIdx = None,
                        moveStepsTaken    = 0
                    })))

    /// SelectedPlayer.State のスタブ handler（未選択を返す）。
    def withNoSelection(thunk: Unit -> a \ ef): a \ (ef - SelectedPlayer.State) =
        run { thunk() } with handler SelectedPlayer.State {
            def get(k) = k(SelectedPlayer.cleared())
            def put(_, k) = k()
        }

    /// `add` 後の (gridPos, lastHoveredEnemyId) を 1 タプルにまとめて取り出す
    def cursorState(scene: Scene[NodeTag]): (Int32, Int32, Option[Int32]) =
        let d = CursorScene.getCursorData(scene);
        (d#gridPos#x, d#gridPos#y, d#lastHoveredEnemyId)

    // ════════════════════════════════════════════════════════
    // add: 初期位置はプレイヤーと同じ、ホバー状態は空
    // ════════════════════════════════════════════════════════

    /// add 直後のカーソルは「プレイヤーと同じグリッド」にあり、
    /// lastHoveredEnemyId は None（味方マスにはどの敵も乗っていない）
    @Test
    def testAddPlacesCursorAtPlayerGrid(): Unit \ Assert =
        let player: {x = Int32, y = Int32} = {x = 5, y = 5};
        let scene = cursorAddPure(sceneWithPlayer(player));
        Assert.assertEq(expected = (5, 5, (None: Option[Int32])),
            cursorState(scene))

    /// add でプレイヤーが (3, 7) にいれば、カーソルも (3, 7) にスポーンする
    /// （プレイヤーの初期セルが 5,5 でない場合の追従を確認）
    @Test
    def testAddFollowsPlayerSpawnPosition(): Unit \ Assert =
        let player: {x = Int32, y = Int32} = {x = 3, y = 7};
        let scene = cursorAddPure(sceneWithPlayer(player));
        Assert.assertEq(expected = (3, 7, (None: Option[Int32])),
            cursorState(scene))

    // ════════════════════════════════════════════════════════
    // snapToPlayer: どこに居ても味方位置に戻り、ホバーもリセット
    // ════════════════════════════════════════════════════════

    /// ホバー対象を持っていたカーソルが、snapToPlayer で味方位置に引き戻される。
    /// ホバー履歴 (lastHoveredEnemyId) も None にリセットされる
    /// （敵ターン明けに「カーソルは味方の上から再開・赤レンジは無し」を保証する）
    @Test
    def testSnapToPlayerResetsCursorAndHover(): Unit \ Assert =
        let player: {x = Int32, y = Int32} = {x = 4, y = 4};
        let result = withNoSelection(() -> withNoopTween(() -> withNoopAnim(() ->
            let scene = cursorAddPure(sceneWithPlayer(player));
            // カーソルを (10, 10) に移し、ホバー履歴も Some(99) に偽装
            let drifted = scene |> CursorScene.mapCursor((m, d) ->
                (m, {gridPos = ({x = 10, y = 10}: {x = Int32, y = Int32}),
                     lastHoveredEnemyId = Some(99) | d}));
            let snapped = CursorScene.snapToPlayer(drifted);
            cursorState(snapped))));
        Assert.assertEq(expected = (4, 4, (None: Option[Int32])), result)
}
