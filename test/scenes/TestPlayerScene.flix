// PlayerScene のテスト
//
// プレイヤーの移動指示の扱い（pendingMotion）と physicsProcess による移動／衝突の挙動を
// 公開 API（add / requestMove / getPlayerData / physicsProcess）経由で確認する。
//
// 位置はピクセルではなくグリッド座標 (col, row) で表現し、
// gridToWorld 経由で世界座標に変換することで意図を読みやすくする。
// 1 グリッド = 16 ピクセル。初期グリッドは (5, 5)。

mod TestPlayerScene {

    // ========================================================================
    // ヘルパー — テスト共通のシーン構築・取り出し
    // ========================================================================

    /// プレイヤー 1 体だけのシーンを作る
    def emptyPlayerScene(): Scene[NodeTag] =
        PlayerScene.add(Scene.empty())

    /// プレイヤーの右隣セル (col=6, row=5) に 16×16 の壁を置いたシーンを作る（衝突応答の確認用）
    def walledPlayerScene(): Scene[NodeTag] =
        let wallPos = PlayerScene.gridToWorld(6, 5);
        let wall = StaticBody2D.make(wallPos,
            CollisionShape2D.RectShape2D({width = 16.0, height = 16.0}));
        emptyPlayerScene()
            |> Scene.addNode("Wall",
                EngineNode.StaticBody2DWithState(wall, NodeTag.NoTag))

    /// プレイヤーのワールド座標を取り出す
    def playerPos(scene: Scene[NodeTag]): Vec2.Vec2 =
        Scene.globalPositionAt(PlayerScene.playerPath(), scene)

    /// 1 フレーム分の物理処理を進める（delta は値が結果に効かないので適当な 0.016 を渡す）
    def stepOnce(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.physicsProcessAll(0.016, false, scene)

    // ========================================================================
    // requestMove — 入力指示を Player の pendingMotion に積む
    // ========================================================================

    /// 右 1 グリッドの要求 → pendingMotion = (16, 0)
    @Test
    def testRequestMoveStoresGridMotion(): Unit \ Assert =
        let after = PlayerScene.requestMove(1, 0, emptyPlayerScene());
        let m = (PlayerScene.getPlayerData(after))#pendingMotion;
        Assert.assertEq(expected = (16.0, 0.0), (m#x, m#y))

    /// 上 1 グリッドの要求 → pendingMotion = (0, -16)
    @Test
    def testRequestMoveUpward(): Unit \ Assert =
        let after = PlayerScene.requestMove(0, -1, emptyPlayerScene());
        let m = (PlayerScene.getPlayerData(after))#pendingMotion;
        Assert.assertEq(expected = (0.0, -16.0), (m#x, m#y))

    // ========================================================================
    // physicsProcess — 移動指示を消化して位置を更新し、指示は次フレームに残らない
    // ========================================================================

    /// 右へ動かす指示を 1 ステップ進めるとグリッドが (5, 5) → (6, 5) に進み、
    /// 指示は消化されて 0 に戻る。
    @Test
    def testPhysicsProcessMovesAndClears(): Unit \ Assert =
        let scene = emptyPlayerScene() |> PlayerScene.requestMove(1, 0);
        let stepped = stepOnce(scene);
        let pos = playerPos(stepped);
        let m = (PlayerScene.getPlayerData(stepped))#pendingMotion;
        let expected = PlayerScene.gridToWorld(6, 5);
        Assert.assertEq(
            expected = (expected#x, expected#y, 0.0, 0.0),
            (pos#x, pos#y, m#x, m#y))

    /// 移動指示が空のフレームでは physicsProcess を呼んでも位置は初期グリッド (5, 5) のまま
    @Test
    def testPhysicsProcessIsNoOpWhenIdle(): Unit \ Assert =
        let stepped = stepOnce(emptyPlayerScene());
        let pos = playerPos(stepped);
        let expected = PlayerScene.gridToWorld(5, 5);
        Assert.assertEq(expected = (expected#x, expected#y), (pos#x, pos#y))

    // ========================================================================
    // 衝突応答 — 壁にぶつかったら動かず、指示はそれでも消化される
    // ========================================================================

    /// 壁の方向 (右) に進もうとすると、初期グリッド (5, 5) のまま動かず、
    /// pendingMotion は 0 に戻る（次フレームで同じ指示は積まれていないので連射にならない）
    @Test
    def testPhysicsProcessBlockedByWall(): Unit \ Assert =
        let scene = walledPlayerScene() |> PlayerScene.requestMove(1, 0);
        let stepped = stepOnce(scene);
        let pos = playerPos(stepped);
        let m = (PlayerScene.getPlayerData(stepped))#pendingMotion;
        let expected = PlayerScene.gridToWorld(5, 5);
        Assert.assertEq(
            expected = (expected#x, expected#y, 0.0, 0.0),
            (pos#x, pos#y, m#x, m#y))
}
