// 実マップ（World_Level_0.ldtkl の Walls レイヤ）統合テスト
//
// 目的:
//   ユーザ報告のバグ
//     ① 矢印と違う方向にたまに行く（単発押下なのに）
//     ② 壁がないのにとまる（特定マスでだけ毎回）
//   が「コードロジックのバグ」か「ユーザの空間認識との齟齬」かを切り分ける。
//
//   実装は変更せず、World_Level_0 の Walls intGridCsv を Python で抽出した
//   壁セル List[Vec2.Vec2] を Flix リテラルで埋め込み、その壁配置で
//   TileMapLayer / MapSnapshot / Board を構築して各種クエリを実機データで
//   検証する。テストが pass すればコードは正しく動いている = ユーザの認識
//   との齟齬。fail すれば fail 内容から修正対象が特定できる。
//
// 検証する観点:
//   - TileMapLayer.isFloor / isWall が ASCII マップの真値と一致
//   - BoardLogic.tryMove が初期 (5,5) からの 4 方向で期待値を返す
//     （特に Down は壁で None — 「壁がないのにとまる」の真相確認）
//   - PlayerScene.moveTo の targetWorld がタイル中心ピクセル座標に一致
//     （「矢印と違う方向」の Vec2 マッピング検証）

mod TestMapIntegration {

    // ========================================================================
    // 実マップ定義 — World_Level_0.ldtkl の Walls レイヤ
    // ========================================================================

    // ASCII map (# = wall, . = floor, Y は下方向に増加・LDTK / Godot 準拠)
    //  y= 0: #############
    //  y= 1: ##.......#..#
    //  y= 2: #..#####.#..#
    //  y= 3: #....##..#..#
    //  y= 4: #.#...#....##
    //  y= 5: #.#......####     ← Player 初期 (5,5) のある row
    //  y= 6: #...##......#
    //  y= 7: #...##......#
    //  y= 8: #...##......#
    //  y= 9: ##..##......#
    //  y=10: ##..##......#
    //  y=11: ######..###.#
    //  y=12: #############

    /// テスト用 tileSize（実機と同じ 16px 正方形）
    def realTileSize(): Float64 = 16.0

    /// 実マップのグリッド寸法（13×13）
    def realGridSize(): Vec2.Vec2i = {x = 13, y = 13}

    /// World_Level_0 の Walls intGridCsv から抽出した壁セル（86 個）。
    /// LDTKLoader.extractCollisionCells と同じ row-major 規約:
    ///   col = i % cWid, row = i / cWid
    /// ASCII マップ上で '#' のセル位置と一対一対応する。
    def realWallCells(): List[Vec2.Vec2] =
        {x =  0.0, y =  0.0} :: {x =  1.0, y =  0.0} :: {x =  2.0, y =  0.0} :: {x =  3.0, y =  0.0} ::
        {x =  4.0, y =  0.0} :: {x =  5.0, y =  0.0} :: {x =  6.0, y =  0.0} :: {x =  7.0, y =  0.0} ::
        {x =  8.0, y =  0.0} :: {x =  9.0, y =  0.0} :: {x = 10.0, y =  0.0} :: {x = 11.0, y =  0.0} ::
        {x = 12.0, y =  0.0} :: {x =  0.0, y =  1.0} :: {x =  1.0, y =  1.0} :: {x =  9.0, y =  1.0} ::
        {x = 12.0, y =  1.0} :: {x =  0.0, y =  2.0} :: {x =  3.0, y =  2.0} :: {x =  4.0, y =  2.0} ::
        {x =  5.0, y =  2.0} :: {x =  6.0, y =  2.0} :: {x =  7.0, y =  2.0} :: {x =  9.0, y =  2.0} ::
        {x = 12.0, y =  2.0} :: {x =  0.0, y =  3.0} :: {x =  5.0, y =  3.0} :: {x =  6.0, y =  3.0} ::
        {x =  9.0, y =  3.0} :: {x = 12.0, y =  3.0} :: {x =  0.0, y =  4.0} :: {x =  2.0, y =  4.0} ::
        {x =  6.0, y =  4.0} :: {x = 11.0, y =  4.0} :: {x = 12.0, y =  4.0} :: {x =  0.0, y =  5.0} ::
        {x =  2.0, y =  5.0} :: {x =  9.0, y =  5.0} :: {x = 10.0, y =  5.0} :: {x = 11.0, y =  5.0} ::
        {x = 12.0, y =  5.0} :: {x =  0.0, y =  6.0} :: {x =  4.0, y =  6.0} :: {x =  5.0, y =  6.0} ::
        {x = 12.0, y =  6.0} :: {x =  0.0, y =  7.0} :: {x =  4.0, y =  7.0} :: {x =  5.0, y =  7.0} ::
        {x = 12.0, y =  7.0} :: {x =  0.0, y =  8.0} :: {x =  4.0, y =  8.0} :: {x =  5.0, y =  8.0} ::
        {x = 12.0, y =  8.0} :: {x =  0.0, y =  9.0} :: {x =  1.0, y =  9.0} :: {x =  4.0, y =  9.0} ::
        {x =  5.0, y =  9.0} :: {x = 12.0, y =  9.0} :: {x =  0.0, y = 10.0} :: {x =  1.0, y = 10.0} ::
        {x =  4.0, y = 10.0} :: {x =  5.0, y = 10.0} :: {x = 12.0, y = 10.0} :: {x =  0.0, y = 11.0} ::
        {x =  1.0, y = 11.0} :: {x =  2.0, y = 11.0} :: {x =  3.0, y = 11.0} :: {x =  4.0, y = 11.0} ::
        {x =  5.0, y = 11.0} :: {x =  8.0, y = 11.0} :: {x =  9.0, y = 11.0} :: {x = 10.0, y = 11.0} ::
        {x = 12.0, y = 11.0} :: {x =  0.0, y = 12.0} :: {x =  1.0, y = 12.0} :: {x =  2.0, y = 12.0} ::
        {x =  3.0, y = 12.0} :: {x =  4.0, y = 12.0} :: {x =  5.0, y = 12.0} :: {x =  6.0, y = 12.0} ::
        {x =  7.0, y = 12.0} :: {x =  8.0, y = 12.0} :: {x =  9.0, y = 12.0} :: {x = 10.0, y = 12.0} ::
        {x = 11.0, y = 12.0} :: {x = 12.0, y = 12.0} :: Nil

    // ========================================================================
    // 構築ヘルパー — TileMapLayer / MapSnapshot / Board
    // ========================================================================

    /// 実 LDTK と同じ collisionCells を持つ TileMapLayer を構築する。
    /// テクスチャ・タイル描画は使わないので tiles は空、texWidth/texHeight も 0。
    def realTileMapLayer(): TileMapLayer =
        let atlas: TileSetAtlasSource = {
            textureName = "test",
            texWidth    = 0.0,
            texHeight   = 0.0,
            tileSize    = realTileSize(),
            marginX     = 0.0,
            marginY     = 0.0,
            spacingX    = 0.0,
            spacingY    = 0.0
        };
        TileMapLayer.make({
            tileSet        = TileSet.make(atlas),
            tiles          = Nil,
            collisionCells = realWallCells(),
            gridSize       = realGridSize()
        })

    /// 実 TileMapLayer をラップした MapSnapshot。
    /// Map ノードのワールド原点は (0,0) と仮定（gridToWorld == mapToLocal）。
    def realMapSnapshot(): MapSnapshot =
        let layer = realTileMapLayer();
        {
            tileSize     = TileMapLayer.tileSize(layer),
            usedRect     = TileMapLayer.getUsedRect(layer),
            isWall       = c -> TileMapLayer.isWall(c, layer),
            isFloor      = c -> TileMapLayer.isFloor(c, layer),
            mapToLocal   = c -> TileMapLayer.mapToLocal(c, layer),
            gridToWorld  = c -> TileMapLayer.mapToLocal(c, layer),
            moduleOfCell = _ -> None
        }

    /// 指定位置に Player 駒だけがある盤面
    def realBoardWithPlayerAt(playerPos: Vec2.Vec2i): Board =
        {
            map    = realMapSnapshot(),
            pieces = (Piece.Player, playerPos) :: Nil
        }

    /// Option[Vec2i] を assertEq 用の tuple に変換
    /// (None → (false, 0, 0)、Some → (true, x, y))
    def unpackOption(o: Option[Vec2.Vec2i]): (Bool, Int32, Int32) =
        match o {
            case Some(v) => (true, v#x, v#y)
            case None    => (false, 0, 0)
        }

    // ========================================================================
    // (1) TileMapLayer の壁/床判定が ASCII マップと一致するか
    // ========================================================================

    /// Player 初期位置 (5,5) は床、その真下 (5,6) は壁、左右と真上は床。
    /// ASCII マップ y=5 行 "#.#......####" / y=6 行 "#...##......#" 参照。
    @Test
    def testFloorWallAroundInitial(): Unit \ Assert =
        let layer = realTileMapLayer();
        let result = (
            TileMapLayer.isFloor(({x = 5, y = 5}: Vec2.Vec2i), layer),  // 自分（床）
            TileMapLayer.isFloor(({x = 5, y = 4}: Vec2.Vec2i), layer),  // up   （床）
            TileMapLayer.isFloor(({x = 5, y = 6}: Vec2.Vec2i), layer),  // down （壁！）
            TileMapLayer.isFloor(({x = 4, y = 5}: Vec2.Vec2i), layer),  // left （床）
            TileMapLayer.isFloor(({x = 6, y = 5}: Vec2.Vec2i), layer)   // right（床）
        );
        Assert.assertEq(
            expected = (true, true, false, true, true),
            result)

    /// マップの四隅は全て壁（外周）。範囲外も壁扱い。
    @Test
    def testCornersAndOutOfBoundsAreWall(): Unit \ Assert =
        let layer = realTileMapLayer();
        let result = (
            TileMapLayer.isWall(({x =  0, y =  0}: Vec2.Vec2i), layer),  // 左上
            TileMapLayer.isWall(({x = 12, y =  0}: Vec2.Vec2i), layer),  // 右上
            TileMapLayer.isWall(({x =  0, y = 12}: Vec2.Vec2i), layer),  // 左下
            TileMapLayer.isWall(({x = 12, y = 12}: Vec2.Vec2i), layer),  // 右下
            TileMapLayer.isFloor(({x = -1, y = 5}: Vec2.Vec2i), layer),  // 範囲外左
            TileMapLayer.isFloor(({x = 13, y = 5}: Vec2.Vec2i), layer)   // 範囲外右
        );
        Assert.assertEq(
            expected = (true, true, true, true, false, false),
            result)

    // ========================================================================
    // (2) BoardLogic.tryMove が実マップの初期 (5,5) で期待方向を返すか
    // ========================================================================

    /// ★最重要★ Player(5,5) からの 4 方向 tryMove 結果。
    /// 期待:
    ///   up    → Some(5, 4)   床
    ///   down  → None         壁 (5,6) で停止 — 「壁がないのにとまる」の真相
    ///   left  → Some(4, 5)   床
    ///   right → Some(6, 5)   床
    @Test
    def testTryMoveFromInitialPosition(): Unit \ Assert =
        let board = realBoardWithPlayerAt({x = 5, y = 5});
        let up    = BoardLogic.tryMove(board, Vec2.upI())    |> unpackOption;
        let down  = BoardLogic.tryMove(board, Vec2.downI())  |> unpackOption;
        let left  = BoardLogic.tryMove(board, Vec2.leftI())  |> unpackOption;
        let right = BoardLogic.tryMove(board, Vec2.rightI()) |> unpackOption;
        Assert.assertEq(
            expected = ((true,  5, 4),    // up    → 床
                        (false, 0, 0),    // down  → 壁
                        (true,  4, 5),    // left  → 床
                        (true,  6, 5)),   // right → 床
            (up, down, left, right))

    /// ユーザ目線の確認: 「真下」を押したら壁判定になる位置を網羅する。
    /// 初期 (5,5) のほか、壁が真下にある別マスでも同様に止まる。
    /// y=4 列 "#.#...#....##" / y=5 列 "#.#......####" を見比べると
    /// (1,3) → down (1,4) は床、(7,3) → down (7,4) は床、
    /// (5,4) → down (5,5) は床、(8,4) → down (8,5) は床、
    /// (5,5) → down (5,6) は壁 ← これが報告された症状。
    @Test
    def testDownBlockedAtFiveFive(): Unit \ Assert =
        let board = realBoardWithPlayerAt({x = 5, y = 5});
        let result = BoardLogic.tryMove(board, Vec2.downI());
        Assert.assertEq(expected = (false, 0, 0), unpackOption(result))

    // ========================================================================
    // (3) mapToLocal / gridToWorld の座標変換が想定どおりか
    // ========================================================================

    /// グリッド座標 → タイル中心ピクセル座標。
    /// (5,5) → (5*16+8, 5*16+8) = (88, 88)
    /// (6,5) → (6*16+8, 5*16+8) = (104, 88)  ← 右に 16px（D 押下後の target）
    /// (5,4) → (5*16+8, 4*16+8) = (88, 72)   ← 上に -16px（W 押下後の target）
    /// (5,6) → (5*16+8, 6*16+8) = (88, 104)  ← 下に +16px（S 押下後の target、壁）
    @Test
    def testMapToLocalAroundInitial(): Unit \ Assert =
        let layer = realTileMapLayer();
        let center = TileMapLayer.mapToLocal(({x = 5, y = 5}: Vec2.Vec2i), layer);
        let right  = TileMapLayer.mapToLocal(({x = 6, y = 5}: Vec2.Vec2i), layer);
        let up     = TileMapLayer.mapToLocal(({x = 5, y = 4}: Vec2.Vec2i), layer);
        let down   = TileMapLayer.mapToLocal(({x = 5, y = 6}: Vec2.Vec2i), layer);
        Assert.assertEq(
            expected = ( 88.0,  88.0,
                        104.0,  88.0,
                         88.0,  72.0,
                         88.0, 104.0),
            (center#x, center#y,
             right#x,  right#y,
             up#x,     up#y,
             down#x,   down#y))

    // ========================================================================
    // (4) PlayerScene.moveTo end-to-end — 単発入力で正しい方向にtweenが向くか
    // ========================================================================

    /// プレイヤーシーン構築（JSON ロード回避、Marker2D 直接生成）。
    /// world 位置は initialGrid のタイル中心 = (88, 88)。
    def emptyPlayerScene(): Scene[NodeTag] =
        let initial = PlayerScene.initialGrid();
        let initialWorld = TileMapLayer.mapToLocal(initial, realTileMapLayer());
        let marker = Marker2D.make(initialWorld);
        Scene.empty()
            |> Scene.addNode("Player",
                EngineNode.Marker2DWithState(marker,
                    NodeTag.Player({
                        gridPos   = initial,
                        moveTiles = PlayerScene.defaultMoveTiles()
                    })))

    /// プレイヤー world 座標
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

    /// 4 方向それぞれの単発 moveTo を end-to-end で検証する。
    /// moveTo + tickAll(1.0) で必ず target world にスナップする
    /// （slideDuration = 16/120 ≈ 0.133 秒なので 1.0 秒で確実に完了）。
    ///
    /// 期待:
    ///   right (6,5) → ( 104.0,  88.0)
    ///   up    (5,4) → (  88.0,  72.0)
    ///   left  (4,5) → (  72.0,  88.0)
    ///   ※ down は壁なので moveTo を呼ばない。BoardLogic.tryMove で None。
    @Test
    def testMoveToEndsAtCorrectWorldPos(): Unit \ Assert =
        region rc {
            let snapshot = realMapSnapshot();
            let result = run {
                // right
                let scene1 = applyMove(snapshot, {x = 6, y = 5}, emptyPlayerScene());
                let posR = playerWorldPos(Tween.tickAll(1.0, scene1));
                // up
                let scene2 = applyMove(snapshot, {x = 5, y = 4}, emptyPlayerScene());
                let posU = playerWorldPos(Tween.tickAll(1.0, scene2));
                // left
                let scene3 = applyMove(snapshot, {x = 4, y = 5}, emptyPlayerScene());
                let posL = playerWorldPos(Tween.tickAll(1.0, scene3));
                (posR#x, posR#y, posU#x, posU#y, posL#x, posL#y)
            } with Tween.withScheduler(rc);
            Assert.assertEq(
                expected = (104.0, 88.0,    // right
                             88.0, 72.0,    // up
                             72.0, 88.0),   // left
                result)
        }

    // ========================================================================
    // (5) ユーザ報告の症状再現テスト
    //
    //   観察された症状:
    //     a) 「初期 (5,5) から左に 1 マスしか進まない」
    //          → 期待: (5,5)→(4,5)→(3,5) と 2 マス進めるはず（(2,5) が壁）
    //     b) 「初期 (5,5) から右を押すと 2 マス一気に進んでとまる」
    //          → 期待: 1 入力で 1 マスのみ進むはず（(6,5)）
    //     c) 「一番左 (1,5) から上を押すと斜め右上に進む」
    //          → 期待: (1,5)→(1,4) のみ。x 座標は変わらない
    //
    //   これらをコードロジック（BoardLogic + PlayerScene + Tween）で再現できるか。
    //   再現できなければ、バグは入力 handler（GameEngine.Game.isKeyPressed）または
    //   レンダリング層（Camera2D / TileMapLayer 描画）にある。
    // ========================================================================

    /// 連続入力シミュレータ: gridPos を起点に dir 方向への moveTo を「壁にぶつかるまで」
    /// 繰り返す。各ステップで moveTo + tickAll(1.0) を回し、最終的な gridPos と
    /// 移動マス数を返す。実機での「キーを押し続けた連続移動」相当。
    def simulateHoldDirection(start: Vec2.Vec2i, dir: Vec2.Vec2i,
                                snapshot: MapSnapshot, scene0: Scene[NodeTag]):
            (Int32, Vec2.Vec2i, Vec2.Vec2) \ Tween.Scheduler =
        // 高々マップ寸法分しか動かない。13×13 なので 20 回も回せば十分
        def loop(steps: Int32, scene: Scene[NodeTag]): (Int32, Scene[NodeTag]) =
            if (steps >= 20) (steps, scene)
            else {
                let player = PlayerScene.getGridPos(scene);
                let board: Board = {
                    map    = snapshot,
                    pieces = (Piece.Player, player) :: Nil
                };
                match BoardLogic.tryMove(board, dir) {
                    case None         => (steps, scene)   // 壁で停止
                    case Some(target) =>
                        let scene1 = applyMove(snapshot, target, scene);
                        let scene2 = Tween.tickAll(1.0, scene1);
                        loop(steps + 1, scene2)
                }
            };
        let (count, finalScene) = loop(0, scene0 |> placeAt(start, snapshot));
        let finalGrid = PlayerScene.getGridPos(finalScene);
        let finalWorld = playerWorldPos(finalScene);
        (count, finalGrid, finalWorld)

    /// 指定グリッドに Player を配置した scene を返す（gridPos と world を整合させる）
    def placeAt(grid: Vec2.Vec2i, snapshot: MapSnapshot): Scene[NodeTag] -> Scene[NodeTag] =
        scene -> {
            let world = snapshot#mapToLocal(grid);
            scene
                |> Scene.setGlobalPositionAt(PlayerScene.playerPath(), world)
                |> Scene.mapEngineNode(PlayerScene.playerPath(), engineNode -> match engineNode {
                    case EngineNode.Marker2DWithState(marker, NodeTag.Player(data)) =>
                        EngineNode.Marker2DWithState(marker,
                            NodeTag.Player({gridPos = grid | data}))
                    case other => other
                })
        }

    /// 症状 a) 再現: 初期 (5,5) から左を押し続けたら、 何マス進むか?
    /// ASCII y=5 行 "#.#......####" より、 左方向の床は (4,5),(3,5) の 2 マス、
    /// (2,5) は壁。 期待: 2 マス進んで (3,5) で停止、 world (56, 88)。
    @Test
    def testHoldLeftFromInitialMovesTwoCells(): Unit \ Assert =
        region rc {
            let snapshot = realMapSnapshot();
            let result = run {
                simulateHoldDirection({x = 5, y = 5}, Vec2.leftI(),
                                        snapshot, emptyPlayerScene())
            } with Tween.withScheduler(rc);
            let (count, grid, world) = result;
            Assert.assertEq(
                expected = (2, 3, 5, 56.0, 88.0),
                (count, grid#x, grid#y, world#x, world#y))
        }

    /// 症状 b) 再現: 初期 (5,5) から右を押し続けたら何マス進むか?
    /// ASCII y=5 行 より、 右方向の床は (6,5),(7,5),(8,5) の 3 マス、 (9,5) は壁。
    /// 期待: 3 マス進んで (8,5) で停止、 world (136, 88)。
    /// もし「右で2マス一気」 がコードロジック側のバグなら、 この期待値が実際と
    /// 食い違うはず（例えば count = 2 で gridPos=(7,5) など）。
    @Test
    def testHoldRightFromInitialMovesThreeCells(): Unit \ Assert =
        region rc {
            let snapshot = realMapSnapshot();
            let result = run {
                simulateHoldDirection({x = 5, y = 5}, Vec2.rightI(),
                                        snapshot, emptyPlayerScene())
            } with Tween.withScheduler(rc);
            let (count, grid, world) = result;
            Assert.assertEq(
                expected = (3, 8, 5, 136.0, 88.0),
                (count, grid#x, grid#y, world#x, world#y))
        }

    /// 症状 c) 再現: 一番左 (1,5) から上 1 回押下で gridPos と world はどうなる?
    /// 期待: (1,5)→(1,4)、 world (24, 72)。 x 座標は変わらず y のみ -16。
    /// もし「斜め右上」 がコードロジック側のバグなら gridPos.x が +1 されているはず。
    @Test
    def testUpFromLeftEdgeMovesStraightUp(): Unit \ Assert =
        region rc {
            let snapshot = realMapSnapshot();
            let result = run {
                let scene0 = emptyPlayerScene() |> placeAt({x = 1, y = 5}, snapshot);
                let board: Board = {
                    map    = snapshot,
                    pieces = (Piece.Player, ({x = 1, y = 5}: Vec2.Vec2i)) :: Nil
                };
                let dir = Vec2.upI();
                let target = match BoardLogic.tryMove(board, dir) {
                    case Some(t) => t
                    case None    => bug!("(1,5) up should be open")
                };
                let scene1 = applyMove(snapshot, target, scene0);
                let scene2 = Tween.tickAll(1.0, scene1);
                let grid = PlayerScene.getGridPos(scene2);
                let world = playerWorldPos(scene2);
                (target#x, target#y, grid#x, grid#y, world#x, world#y)
            } with Tween.withScheduler(rc);
            Assert.assertEq(
                expected = (1, 4,     // tryMove の target も x 不変
                            1, 4,     // 移動後 gridPos も x 不変
                           24.0, 72.0),  // world も x = 24 のまま、y のみ -16
                result)
        }
}
