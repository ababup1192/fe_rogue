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
//   TileLayer / MapSnapshot / Board を構築して各種クエリを実機データで
//   検証する。テストが pass すればコードは正しく動いている = ユーザの認識
//   との齟齬。fail すれば fail 内容から修正対象が特定できる。
//
// 検証する観点:
//   - TileLayer.isFloor / isWall が ASCII マップの真値と一致
//   - Board.tryMove が初期 (5,5) からの 4 方向で期待値を返す
//     （特に Down は壁で None — 「壁がないのにとまる」の真相確認）
//   - PlayerDriver.moveToById の targetWorld がタイル中心ピクセル座標に一致
//     （「矢印と違う方向」の Vec2 マッピング検証）

mod TestMapIntegration {

    // ========================================================================
    // 実マップ定義 — World_Level_0.ldtkl の Walls レイヤ
    // ========================================================================

    // ASCII map (# = wall, . = floor, Y は下方向に増加)
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
    def realGridSize(): {x = Int32, y = Int32} = {x = 13, y = 13}

    /// World_Level_0 の Walls intGridCsv から抽出した壁セル（86 個）。
    /// `MapLoader` の collisionCells 抽出と同じ row-major 規約:
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
    // 構築ヘルパー — TileLayer / MapSnapshot / Board
    // ========================================================================

    /// 実 LDTK と同じ collisionCells を持つ TileLayer を構築する。
    /// テクスチャ・タイル描画は使わないので tiles は空、texWidth/texHeight も 0。
    def realTileMapLayer(): TileLayer =
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
        TileLayer.make({
            tileSet        = Tileset.make(atlas),
            tiles          = Nil,
            collisionCells = realWallCells(),
            gridSize       = realGridSize()
        })

    /// 実 TileLayer をラップした MapSnapshot。
    /// Map ノードのワールド原点は (0,0) と仮定（gridToWorld == mapToLocal）。
    def realMapSnapshot(): MapSnapshot =
        MapSetup.snapshotOf(realTileMapLayer(), Vec2.zero(), Nil)

    /// 指定位置に Player(0) 駒だけがある盤面
    def realBoardWithPlayerAt(playerPos: {x = Int32, y = Int32}): Board =
        {
            map    = realMapSnapshot(),
            pieces = (Piece.Player(0), playerPos) :: Nil
        }

    /// Option[Vec2i] を assertEq 用の tuple に変換
    /// (None → (false, 0, 0)、Some → (true, x, y))
    def unpackOption(o: Option[{x = Int32, y = Int32}]): (Bool, Int32, Int32) =
        match o {
            case Some(v) => (true, v#x, v#y)
            case None    => (false, 0, 0)
        }

    // ========================================================================
    // (1) TileLayer の壁/床判定が ASCII マップと一致するか
    // ========================================================================

    /// Player 初期位置 (5,5) は床、その真下 (5,6) は壁、左右と真上は床。
    /// ASCII マップ y=5 行 "#.#......####" / y=6 行 "#...##......#" 参照。
    @Test
    def testFloorWallAroundInitial(): Unit \ Assert =
        let layer = realTileMapLayer();
        let result = (
            TileLayer.isFloor(({x = 5, y = 5}: {x = Int32, y = Int32}), layer),  // 自分（床）
            TileLayer.isFloor(({x = 5, y = 4}: {x = Int32, y = Int32}), layer),  // up   （床）
            TileLayer.isFloor(({x = 5, y = 6}: {x = Int32, y = Int32}), layer),  // down （壁！）
            TileLayer.isFloor(({x = 4, y = 5}: {x = Int32, y = Int32}), layer),  // left （床）
            TileLayer.isFloor(({x = 6, y = 5}: {x = Int32, y = Int32}), layer)   // right（床）
        );
        Assert.assertEq(
            expected = (true, true, false, true, true),
            result)

    /// マップの四隅は全て壁（外周）。範囲外も壁扱い。
    @Test
    def testCornersAndOutOfBoundsAreWall(): Unit \ Assert =
        let layer = realTileMapLayer();
        let result = (
            TileLayer.isWall(({x =  0, y =  0}: {x = Int32, y = Int32}), layer),  // 左上
            TileLayer.isWall(({x = 12, y =  0}: {x = Int32, y = Int32}), layer),  // 右上
            TileLayer.isWall(({x =  0, y = 12}: {x = Int32, y = Int32}), layer),  // 左下
            TileLayer.isWall(({x = 12, y = 12}: {x = Int32, y = Int32}), layer),  // 右下
            TileLayer.isFloor(({x = -1, y = 5}: {x = Int32, y = Int32}), layer),  // 範囲外左
            TileLayer.isFloor(({x = 13, y = 5}: {x = Int32, y = Int32}), layer)   // 範囲外右
        );
        Assert.assertEq(
            expected = (true, true, true, true, false, false),
            result)

    // ========================================================================
    // (2) Board.tryMove が実マップの初期 (5,5) で期待方向を返すか
    // ========================================================================

    /// ★最重要★ Player(5,5) からの 4 方向 tryMove 結果。
    /// 期待:
    ///   up    → Some(5, 4)   床
    ///   down  → None         壁 (5,6) で停止 — 「壁がないのにとまる」の真相
    ///   left  → Some(4, 5)   床
    ///   right → Some(6, 5)   床
    @Test
    def testTryMoveFromInitialPosition(): Unit \ Assert =
        let source: {x = Int32, y = Int32} = {x = 5, y = 5};
        let board = realBoardWithPlayerAt(source);
        let up    = Board.tryMove(board, source, Vec2i.up())    |> unpackOption;
        let down  = Board.tryMove(board, source, Vec2i.down())  |> unpackOption;
        let left  = Board.tryMove(board, source, Vec2i.left())  |> unpackOption;
        let right = Board.tryMove(board, source, Vec2i.right()) |> unpackOption;
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
        let source: {x = Int32, y = Int32} = {x = 5, y = 5};
        let board = realBoardWithPlayerAt(source);
        let result = Board.tryMove(board, source, Vec2i.down());
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
        let center = TileLayer.cellCenterOf(({x = 5, y = 5}: {x = Int32, y = Int32}), layer);
        let right  = TileLayer.cellCenterOf(({x = 6, y = 5}: {x = Int32, y = Int32}), layer);
        let up     = TileLayer.cellCenterOf(({x = 5, y = 4}: {x = Int32, y = Int32}), layer);
        let down   = TileLayer.cellCenterOf(({x = 5, y = 6}: {x = Int32, y = Int32}), layer);
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
    // (4) PlayerDriver.moveToById end-to-end — 単発入力で正しい方向にtweenが向くか
    // ========================================================================

    /// テスト用初期グリッド（PlayerDriver.add の経由を回避）。
    def initialGrid(): {x = Int32, y = Int32} = {x = 5, y = 5}

    /// Player(0) を `pos` に置いた World を組む（moveTiles=5・hp=10 は本テスト群の実機値に揃える）。
    def worldWithPlayerAt(pos: {x = Int32, y = Int32}): World =
        TestWorldFixtures.worldOf(
            TestWorldFixtures.playerCmds({moveTiles = 5 | TestWorldFixtures.unitSpec(0, pos)}))

    /// Player(0) を moveToById で `target` へ 1 マス動かし、**実ゲームの描画パイプライン相当**で
    /// 着地後の描画位置を観測する。moveToById が emit する `Cmd.Move`（位置権威）＋描画 tween を
    /// `world` に積み、`stepWorld` で tween を完了まで進め、World の renderPos（＝着地セル中心）を
    /// `landed` として返す。
    def applyMove(world: World, map: MapSnapshot, target: {x = Int32, y = Int32}):
            {world = World, landed = Vec2.Vec2} =
        region rc {
            let (_, world1) = TestUnitFixtures.withWorldAppliedSeeded(rc, world, () ->
                PlayerDriver.moveToById(0, target, map, Duration.frames(count = 16, fps = 120)));
            // slide ≈ 16/120 秒ゆえ 1 秒進めれば tween は必ず完了し renderPos=着地セル中心。
            let (world2, _moved) = World.stepWorld(world1, 1.0);
            let landed = World.renderPosOf(World.EntityRef.Player(0), world2)
                |> Option.getWithDefault(Vec2.zero());
            {world = world2, landed = landed}
        }

    /// 4 方向それぞれの単発 moveToById を end-to-end で検証する。
    /// moveToById + stepWorld(1.0) で必ず target world にスナップする
    /// （slideDuration = 16/120 ≈ 0.133 秒なので 1.0 秒で確実に完了）。
    ///
    /// 期待:
    ///   right (6,5) → ( 104.0,  88.0)
    ///   up    (5,4) → (  88.0,  72.0)
    ///   left  (4,5) → (  72.0,  88.0)
    ///   ※ down は壁なので moveToById を呼ばない。Board.tryMove で None。
    @Test
    def testMoveToEndsAtCorrectWorldPos(): Unit \ Assert =
        let snapshot = realMapSnapshot();
        // applyMove が World tween を完了まで進め renderPos を着地セルへ載せる。
        let posR = (applyMove(worldWithPlayerAt(initialGrid()), snapshot, {x = 6, y = 5}))#landed; // right
        let posU = (applyMove(worldWithPlayerAt(initialGrid()), snapshot, {x = 5, y = 4}))#landed; // up
        let posL = (applyMove(worldWithPlayerAt(initialGrid()), snapshot, {x = 4, y = 5}))#landed; // left
        Assert.assertEq(
            expected = (104.0, 88.0,    // right
                         88.0, 72.0,    // up
                         72.0, 88.0),   // left
            (posR#x, posR#y, posU#x, posU#y, posL#x, posL#y))

    /// フロア再構築直後（ゲーム開始・階段降下・中断明け）の「最初の 1 歩」が滑走 tween に
    /// なることを pin する。本番 spawn は renderPos を seed しないため、fixture の
    /// `playerCmds`（SetRenderPos 込み）は使わず Spawn + Move だけの最小 seed で再現する。
    ///
    ///   (5,5) ──右へ 1 歩──▶ (6,5)
    ///   ↑ tween 起点 = 移動前セル (5,5) の中心であるべき。renderPos 未 seed の静止駒は
    ///     `World.visualPosOf` がグローバル tileSize()=26 の `MapSnapshot.cellCenter` で
    ///     描かれるため、起点も同じ (5×26+13, 5×26+13) = (143,143) で一致する。
    ///     着地セル中心 (169,143) になっていたら起点=終点＝瞬間移動して見えるバグ。
    ///
    /// 観測窓: `Cmd.StartTween` は起点を即 renderPos にスナップするので、
    /// moveToById 直後（stepWorld 前）の renderPos が tween 起点そのもの。
    @Test
    def testFirstMoveAfterRebuildTweensFromPreMoveCell(): Unit \ Assert =
        region rc {
            let bare = TestWorldFixtures.worldOf(
                World.Cmd.Spawn(World.EntityRef.Player(0))
                    :: World.Cmd.Move(World.EntityRef.Player(0), initialGrid()) :: Nil);
            let (_, world1) = TestUnitFixtures.withWorldAppliedSeeded(rc, bare, () ->
                PlayerDriver.moveToById(0, {x = 6, y = 5}, realMapSnapshot(),
                                        Duration.frames(count = 16, fps = 120)));
            let start = World.renderPosOf(World.EntityRef.Player(0), world1)
                |> Option.getWithDefault(Vec2.zero());
            Assert.assertEq(expected = (143.0, 143.0), (start#x, start#y))
        }

    /// 1 歩移動の view 再生が facing を進行方向へ更新することを pin する（右へ 1 歩 → Right）。
    /// 移動前セルは `Cmd.Move` が自動記録する prevPos から導く＝World 再構築直後でも正しく向く。
    @Test
    def testMoveReplayUpdatesFacing(): Unit \ Assert =
        let moved = (applyMove(worldWithPlayerAt(initialGrid()), realMapSnapshot(), {x = 6, y = 5}))#world;
        Assert.assertEq(expected = Some(Dir4.Right),
                        World.facingOf(World.EntityRef.Player(0), moved))

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
    //   これらをコードロジック（Board + PlayerDriver + Tween）で再現できるか。
    //   再現できなければ、バグは入力 handler（GameEngine.Game.isKeyPressed）または
    //   レンダリング層（Camera / TileLayer 描画）にある。
    // ========================================================================

    /// 連続入力シミュレータ: `start` に置いた Player(0) を、dir 方向への moveToById で
    /// 「壁にぶつかるまで」繰り返す。各ステップで moveToById + stepWorld(1.0) を回し、
    /// 最終的な gridPos と移動マス数を返す。実機での「キーを押し続けた連続移動」相当。
    def simulateHoldDirection(start: {x = Int32, y = Int32}, dir: {x = Int32, y = Int32},
                                snapshot: MapSnapshot):
            (Int32, {x = Int32, y = Int32}, Vec2.Vec2) =
        // 高々マップ寸法分しか動かない。13×13 なので 20 回も回せば十分
        def loop(steps: Int32, world: World, pos: Vec2.Vec2): (Int32, World, Vec2.Vec2) =
            if (steps >= 20) (steps, world, pos)
            else {
                let player = World.posOf(World.EntityRef.Player(0), world) |> Option.getWithDefault(start);
                let board: Board = {
                    map    = snapshot,
                    pieces = (Piece.Player(0), player) :: Nil
                };
                match Board.tryMove(board, player, dir) {
                    case None         => (steps, world, pos)   // 壁で停止
                    case Some(target) =>
                        // applyMove が World tween 完了まで進め renderPos を着地セルへ載せる。
                        let moved = applyMove(world, snapshot, target);
                        loop(steps + 1, moved#world, moved#landed)
                }
            };
        let (count, finalWorld, finalPos) =
            loop(0, worldWithPlayerAt(start), MapSnapshot.mapToLocal(start, snapshot));
        let finalGrid = World.posOf(World.EntityRef.Player(0), finalWorld) |> Option.getWithDefault(start);
        (count, finalGrid, finalPos)

    /// 症状 a) 再現: 初期 (5,5) から左を押し続けたら、 何マス進むか?
    /// ASCII y=5 行 "#.#......####" より、 左方向の床は (4,5),(3,5) の 2 マス、
    /// (2,5) は壁。 期待: 2 マス進んで (3,5) で停止、 world (56, 88)。
    @Test
    def testHoldLeftFromInitialMovesTwoCells(): Unit \ Assert =
        let snapshot = realMapSnapshot();
        let (count, grid, world) =
            simulateHoldDirection({x = 5, y = 5}, Vec2i.left(), snapshot);
        Assert.assertEq(
            expected = (2, 3, 5, 56.0, 88.0),
            (count, grid#x, grid#y, world#x, world#y))

    /// 症状 b) 再現: 初期 (5,5) から右を押し続けたら何マス進むか?
    /// ASCII y=5 行 より、 右方向の床は (6,5),(7,5),(8,5) の 3 マス、 (9,5) は壁。
    /// 期待: 3 マス進んで (8,5) で停止、 world (136, 88)。
    /// もし「右で2マス一気」 がコードロジック側のバグなら、 この期待値が実際と
    /// 食い違うはず（例えば count = 2 で gridPos=(7,5) など）。
    @Test
    def testHoldRightFromInitialMovesThreeCells(): Unit \ Assert =
        let snapshot = realMapSnapshot();
        let (count, grid, world) =
            simulateHoldDirection({x = 5, y = 5}, Vec2i.right(), snapshot);
        Assert.assertEq(
            expected = (3, 8, 5, 136.0, 88.0),
            (count, grid#x, grid#y, world#x, world#y))

    /// 症状 c) 再現: 一番左 (1,5) から上 1 回押下で gridPos と world はどうなる?
    /// 期待: (1,5)→(1,4)、 world (24, 72)。 x 座標は変わらず y のみ -16。
    /// もし「斜め右上」 がコードロジック側のバグなら gridPos.x が +1 されているはず。
    @Test
    def testUpFromLeftEdgeMovesStraightUp(): Unit \ Assert =
        let snapshot = realMapSnapshot();
        let source: {x = Int32, y = Int32} = {x = 1, y = 5};
        let world0 = worldWithPlayerAt(source);
        let board: Board = {
            map    = snapshot,
            pieces = (Piece.Player(0), source) :: Nil
        };
        // (1,5) 上は床が保証されている前提。壊れていれば下の assertEq が (-1,-1) 側で必ず落ちる。
        let target = Board.tryMove(board, source, Vec2i.up()) |> Option.getWithDefault({x = -1, y = -1});
        // applyMove が World tween 完了まで進め renderPos を着地セルへ載せる。
        let moved = applyMove(world0, snapshot, target);
        let grid = World.posOf(World.EntityRef.Player(0), moved#world) |> Option.getWithDefault(source);
        let world = moved#landed;
        Assert.assertEq(
            expected = (1, 4,     // tryMove の target も x 不変
                        1, 4,     // 移動後 gridPos も x 不変
                       24.0, 72.0),  // world も x = 24 のまま、y のみ -16
            (target#x, target#y, grid#x, grid#y, world#x, world#y))
}
