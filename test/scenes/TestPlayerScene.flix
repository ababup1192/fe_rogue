// PlayerScene のテスト
//
// プレイヤーの移動指示の扱い（pendingMotion）と physicsProcess による移動／衝突の挙動を
// 公開 API（requestMove / getPlayerData / physicsProcess）経由で確認する。
//
// 位置はピクセルではなくグリッド座標 (col, row) で表現し、
// gridPos 経由でワールド座標に変換することで意図を読みやすくする。
// テスト用 tileSize は 16。初期グリッドは (5, 5)。
//
// PlayerScene.requestMove は MapQuery effect で tileSize を要求するので、
// テストでは withTestTileSize でモックハンドラを注入する。MapScene の存在も
// TileMapLayer の構築も不要。

mod TestPlayerScene {

    // ========================================================================
    // ヘルパー — テスト共通のシーン構築・取り出し
    // ========================================================================

    /// テスト用 tileSize（PlayerScene.scene.json と整合）
    def testTileSize(): Float64 = 16.0

    /// MapQuery effect を tileSize 固定で解決するハンドラ。
    /// PlayerScene.requestMove を呼ぶテストはこれで包む。
    def withTestTileSize(thunk: Unit -> a \ ef): a \ (ef - MapQuery) =
        run { thunk() } with handler MapQuery {
            def tileSize(k)             = k(testTileSize())
            def getUsedRect(k)          = k({position = Vec2.zeroI(), size = {x = 13, y = 13}})
            def isWall(_coords, k)      = k(false)
            def isFloor(_coords, k)     = k(true)
            def mapToLocal(coords, k)   =
                let s = testTileSize();
                let v = Vec2.fromI(coords);
                k({x = v#x * s + s / 2.0, y = v#y * s + s / 2.0})
        }

    /// グリッド座標 → ワールド座標（マップが原点にあるのでローカル＝ワールド）
    def gridPos(col: Int32, row: Int32): Vec2.Vec2 =
        let s = testTileSize();
        {x = Int32.toFloat64(col) * s + s / 2.0,
         y = Int32.toFloat64(row) * s + s / 2.0}

    /// プレイヤー 1 体だけのシーンを作る（JSON ロードを介さず CharacterBody2D を直接構築）。
    /// 値は PlayerScene.scene.json と整合させること。
    /// MapQuery が tileSize を返すだけなので、TileMapLayer は登録不要。
    def emptyPlayerScene(): Scene[NodeTag] =
        let pos = gridPos(5, 5);
        let body = CharacterBody2D.make(pos, {moveSpeed = 0.0})
            |> CharacterBody2D.setCollisionShape(
                Some(CollisionShape2D.RectShape2D({width = 14.0, height = 14.0})));
        Scene.empty()
            |> Scene.addNode("Player",
                EngineNode.Body2DWithState(body,
                    NodeTag.Player({pendingMotion = Vec2.zero()})))

    /// プレイヤーの右隣セル (col=6, row=5) に 16×16 の壁を置いたシーンを作る（衝突応答の確認用）
    def walledPlayerScene(): Scene[NodeTag] =
        let wallPos = gridPos(6, 5);
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
        let after = withTestTileSize(() ->
            PlayerScene.requestMove(Vec2.rightI(), emptyPlayerScene()));
        let m = (PlayerScene.getPlayerData(after))#pendingMotion;
        Assert.assertEq(expected = (16.0, 0.0), (m#x, m#y))

    /// 上 1 グリッドの要求 → pendingMotion = (0, -16)
    @Test
    def testRequestMoveUpward(): Unit \ Assert =
        let after = withTestTileSize(() ->
            PlayerScene.requestMove(Vec2.upI(), emptyPlayerScene()));
        let m = (PlayerScene.getPlayerData(after))#pendingMotion;
        Assert.assertEq(expected = (0.0, -16.0), (m#x, m#y))

    // ========================================================================
    // physicsProcess — 移動指示を消化して位置を更新し、指示は次フレームに残らない
    // ========================================================================

    /// 右へ動かす指示を 1 ステップ進めるとグリッドが (5, 5) → (6, 5) に進み、
    /// 指示は消化されて 0 に戻る。
    @Test
    def testPhysicsProcessMovesAndClears(): Unit \ Assert =
        let scene = withTestTileSize(() ->
            emptyPlayerScene() |> PlayerScene.requestMove(Vec2.rightI()));
        let stepped = stepOnce(scene);
        let pos = playerPos(stepped);
        let m = (PlayerScene.getPlayerData(stepped))#pendingMotion;
        let expected = gridPos(6, 5);
        Assert.assertEq(
            expected = (expected#x, expected#y, 0.0, 0.0),
            (pos#x, pos#y, m#x, m#y))

    /// 移動指示が空のフレームでは physicsProcess を呼んでも位置は初期グリッド (5, 5) のまま
    @Test
    def testPhysicsProcessIsNoOpWhenIdle(): Unit \ Assert =
        let stepped = stepOnce(emptyPlayerScene());
        let pos = playerPos(stepped);
        let expected = gridPos(5, 5);
        Assert.assertEq(expected = (expected#x, expected#y), (pos#x, pos#y))

    // ========================================================================
    // 衝突応答 — 壁にぶつかったら動かず、指示はそれでも消化される
    // ========================================================================

    /// 壁の方向 (右) に進もうとすると、初期グリッド (5, 5) のまま動かず、
    /// pendingMotion は 0 に戻る（次フレームで同じ指示は積まれていないので連射にならない）
    @Test
    def testPhysicsProcessBlockedByWall(): Unit \ Assert =
        let scene = withTestTileSize(() ->
            walledPlayerScene() |> PlayerScene.requestMove(Vec2.rightI()));
        let stepped = stepOnce(scene);
        let pos = playerPos(stepped);
        let m = (PlayerScene.getPlayerData(stepped))#pendingMotion;
        let expected = gridPos(5, 5);
        Assert.assertEq(
            expected = (expected#x, expected#y, 0.0, 0.0),
            (pos#x, pos#y, m#x, m#y))
}
