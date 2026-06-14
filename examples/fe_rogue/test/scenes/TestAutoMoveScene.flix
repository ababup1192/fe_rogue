// AutoMoveScene のテスト — 追従移動(FollowMove)の純粋ロジック `followTargetFor`
//
// 追従者の「次の 1 マス」を決める純粋関数だけを検証する。盤面(Board)と
// ロード始点の距離フィールドを直接合成し、effect なしで挙動を確かめる。
//   - ロードへ近づく降下先を選ぶ
//   - 既に隣接していれば動かない（ロードのマスへは踏み込まず隣で停止 = 重ならない）
//   - 降下先が他駒に占有されていれば動かない（追従者同士のスタックを防ぐ）
//   - 斜め位置からは決定的順序(up→down→left→right)で 1 軸へ寄る
//
// 駆動側(followTick / followStep)・解散(endFollow)は effect を伴うのでここでは扱わない。

mod TestAutoMoveScene {

    /// テスト用 tileSize（実機と同じ 16px 正方形）
    def testTileSize(): Float64 = 16.0

    /// w×h サイズの盤面で、全マス床。範囲外は壁扱い。
    def emptySnapshot(w: Int32, h: Int32): MapSnapshot =
        {
            tileSize     = testTileSize(),
            usedRect     = {position = {x = 0, y = 0}, size = ({x = w, y = h}: {x = Int32, y = Int32})},
            wallCells    = (Set#{}: Set[(Int32, Int32)]),
            mapGlobal    = {x = 0.0, y = 0.0},
            placements   = Nil
        }

    /// 7×7 全床盤面に与えられた駒を置いた Board を組む。
    def boardWith(pieces: List[(Piece, {x = Int32, y = Int32})]): Board =
        {
            map    = emptySnapshot(7, 7),
            pieces = pieces
        }

    /// ロード位置始点の距離フィールド（壁のみ通行不可・全床なので全面に広がる）。
    def fieldFrom(lordPos: {x = Int32, y = Int32}, map: MapSnapshot): Map[(Int32, Int32), Int32] =
        Board.distanceField(c -> MapSnapshot.isFloor(c, map), lordPos :: Nil, 4096)

    /// Option[Vec2i] を assertEq 用の tuple に変換 (None → (false,0,0) / Some → (true,x,y))
    def unpack(o: Option[{x = Int32, y = Int32}]): (Bool, Int32, Int32) =
        match o {
            case Some(v) => (true, v#x, v#y)
            case None    => (false, 0, 0)
        }

    def cell(x: Int32, y: Int32): {x = Int32, y = Int32} = {x = x, y = y}

    /// 直線で 2 マス離れた追従者は、ロード側の隣マスへ 1 歩寄る。
    @Test
    def testFollowerStepsTowardLord(): Unit \ Assert =
        let lord  = cell(3, 3);
        let board = boardWith((Piece.Player(0), lord) :: (Piece.Player(1), cell(5, 3)) :: Nil);
        let field = fieldFrom(lord, board#map);
        let result = AutoMoveScene.followTargetFor(lord, cell(5, 3), field, board);
        Assert.assertEq(expected = (true, 4, 3), unpack(result))

    /// 既にロードに隣接している追従者は動かない（ロードのマスへ踏み込まず隣で停止）。
    @Test
    def testAdjacentFollowerStaysPut(): Unit \ Assert =
        let lord  = cell(3, 3);
        let board = boardWith((Piece.Player(0), lord) :: (Piece.Player(1), cell(4, 3)) :: Nil);
        let field = fieldFrom(lord, board#map);
        let result = AutoMoveScene.followTargetFor(lord, cell(4, 3), field, board);
        Assert.assertEq(expected = (false, 0, 0), unpack(result))

    /// 降下先が他の追従者に占有されていれば動かない（スタック回避。次のリーダー歩で解ける）。
    @Test
    def testFollowerWaitsWhenDownhillOccupied(): Unit \ Assert =
        let lord  = cell(3, 3);
        // 追従者A(5,3) の唯一の降下先(4,3)を追従者B が塞いでいる。
        let board = boardWith(
            (Piece.Player(0), lord) ::
            (Piece.Player(1), cell(5, 3)) ::
            (Piece.Player(2), cell(4, 3)) :: Nil);
        let field = fieldFrom(lord, board#map);
        let result = AutoMoveScene.followTargetFor(lord, cell(5, 3), field, board);
        Assert.assertEq(expected = (false, 0, 0), unpack(result))

    /// 斜め位置からは決定的順序(up→down→left→right)で先勝ち → up 側へ寄る。
    @Test
    def testDiagonalFollowerPicksDeterministicAxis(): Unit \ Assert =
        let lord  = cell(3, 3);
        let board = boardWith((Piece.Player(0), lord) :: (Piece.Player(1), cell(5, 5)) :: Nil);
        let field = fieldFrom(lord, board#map);
        let result = AutoMoveScene.followTargetFor(lord, cell(5, 5), field, board);
        Assert.assertEq(expected = (true, 5, 4), unpack(result))
}
