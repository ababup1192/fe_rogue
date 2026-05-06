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
    def cellCenter(c: Vec2.Vec2i): Vec2.Vec2 =
        let s = testTileSize();
        let v = Vec2.fromI(c);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    /// Tween.Scheduler のスタブ。schedule / cancel を捨てて何もしない。
    /// snapToPlayer の動作確認時に Tween 実体を立ち上げないために使う。
    def withNoopTween(thunk: Unit -> a \ ef): a \ (ef - Tween.Scheduler) =
        run { thunk() } with handler Tween.Scheduler {
            def schedule(_, k) = k()
            def isActive(_, k) = k(false)
            def cancel(_, k) = k()
            def consumeUpdates(_, k) = k(Nil)
        }

    /// プレイヤー id=0 1 体だけを (gridPos) に置いた scene を組む。
    /// JSON ロードを介さず Marker2D を直接構築する。
    def sceneWithPlayer(gridPos: Vec2.Vec2i): Scene[NodeTag] =
        let pos = cellCenter(gridPos);
        let marker = Marker2D.make(pos);
        Scene.empty()
            |> Scene.addNode(PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(marker,
                    NodeTag.Player({
                        id        = 0,
                        gridPos   = gridPos,
                        moveTiles = PlayerScene.defaultMoveTiles(),
                        hp        = PlayerScene.defaultHp(),
                        waited    = false,
                        attacking = None
                    })))

    /// SelectedPlayer.State のスタブ handler（未選択を返す）。
    def withNoSelection(thunk: Unit -> a \ ef): a \ (ef - SelectedPlayer.State) =
        run { thunk() } with handler SelectedPlayer.State {
            def get(k) = k(None)
            def put(_, k) = k()
            def getOrigin(k) = k(None)
            def putOrigin(_, k) = k()
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
        let player: Vec2.Vec2i = {x = 5, y = 5};
        let scene = CursorScene.add(sceneWithPlayer(player));
        Assert.assertEq(expected = (5, 5, (None: Option[Int32])),
            cursorState(scene))

    /// add でプレイヤーが (3, 7) にいれば、カーソルも (3, 7) にスポーンする
    /// （プレイヤーの初期セルが 5,5 でない場合の追従を確認）
    @Test
    def testAddFollowsPlayerSpawnPosition(): Unit \ Assert =
        let player: Vec2.Vec2i = {x = 3, y = 7};
        let scene = CursorScene.add(sceneWithPlayer(player));
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
        let player: Vec2.Vec2i = {x = 4, y = 4};
        let result = withNoSelection(() -> withNoopTween(() ->
            let scene = CursorScene.add(sceneWithPlayer(player));
            // カーソルを (10, 10) に移し、ホバー履歴も Some(99) に偽装
            let drifted = scene |> CursorScene.mapCursor((m, d) ->
                (m, {gridPos = ({x = 10, y = 10}: Vec2.Vec2i),
                     lastHoveredEnemyId = Some(99) | d}));
            let snapped = CursorScene.snapToPlayer(drifted);
            cursorState(snapped)));
        Assert.assertEq(expected = (4, 4, (None: Option[Int32])), result)
}
