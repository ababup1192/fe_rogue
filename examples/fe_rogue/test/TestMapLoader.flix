/// MapLoader の自動壁計算（純粋ロジック）テスト。
///
/// `.map.json` の床マスから「自動壁セル」「タイル選択キー」「IntGrid」を導出する純粋関数群。
/// 全マップの壁描画 + 当たり判定の土台で、`DungeonComposer.buildWallsLayer` も再利用する。
/// 引数は `Set[(Int32, Int32)]` と Int32 のみ＝scene/engine 非依存で純粋値だけで検証できる。
mod TestMapLoader {

    // ── computeWallCells: 床に隣接する非床セルが自動壁になる ──

    /// 単一床 (1,1) の周囲 8 セルがすべて壁になる（床自身は壁にしない）。
    @Test
    def testWallCellsRingAroundSingleFloor(): Unit \ Assert =
        let walls = MapLoader.computeWallCells(Set#{(1, 1)}, 3, 3);
        Assert.assertEq(
            expected = (8, false, true),
            (Set.size(walls),
             Set.memberOf((1, 1), walls),     // 床自身は壁でない
             Set.memberOf((0, 0), walls)))    // 周囲は壁

    /// 床が 1 つも無ければ自動壁も無い（境界）。
    @Test
    def testWallCellsNoFloorIsEmpty(): Unit \ Assert =
        let walls = MapLoader.computeWallCells((Set#{}: Set[(Int32, Int32)]), 3, 3);
        Assert.assertEq(expected = true, Set.isEmpty(walls))

    // ── trblTritKeyAt: 上右下左の壁/床/空キー（オートタイル選択の要） ──

    /// 部屋の上辺中央 (1,0) のキー: 上=空(E) 右=壁(W) 下=床(F) 左=壁(W) → "EWFW"。
    /// floorMask=(1,1) のとき computeWallCells で周囲8セルが壁になる構成で trit 順を pin。
    @Test
    def testTritKeyTopEdgeOfRoom(): Unit \ Assert =
        let floorMask = Set#{(1, 1)};
        let wallCells = MapLoader.computeWallCells(floorMask, 3, 3);
        Assert.assertEq(
            expected = "EWFW",
            MapLoader.trblTritKeyAt(wallCells, floorMask, 1, 0))

    // ── buildIntGrid: 0=空 / 1=床 / 2=壁（AutoRule 入力） ──

    /// 床セル=1・自動壁セル=2 でエンコードされる。index = row*width + col。
    /// (1,1)=床 → index 4 が 1、(0,0)=壁 → index 0 が 2。
    @Test
    def testIntGridEncoding(): Unit \ Assert =
        let floorMask = Set#{(1, 1)};
        let wallCells = MapLoader.computeWallCells(floorMask, 3, 3);
        let grid = MapLoader.buildIntGrid(floorMask, wallCells, 3, 3);
        Assert.assertEq(
            expected = (1, 2),
            (Vector.get(4, grid), Vector.get(0, grid)))

    // ── autoRules「左/右通路合流の壁角」: 通路の天井が部屋の壁に合流する短い L 字の角 ──
    //
    // 部屋の左壁に左から通路の天井が合流し、縦壁が合流角の直上（部屋の上辺）で終わる構成。
    // 合流角 T=(4,4) の TRBL trit キーは平らな左壁と同じ "WFWE" になるため wallMap では
    // 専用チップを選べず、黒い箱ピース (5,1) に落ちる。縦壁が 2 セル以上続く「長い L」は
    // 既存ルール（上出口凸左 等）が先勝ちで担当するので、新ルールは上上=void の短 L 限定。
    //
    //        col: 1   2   3   4   5   6   7
    //   row 3:    ,   ,   ,   W   W   W   W     部屋の上辺の壁
    //   row 4:    ,   ,   ,  [T]  F   F   F     T=合流角 / F=部屋床
    //   row 5:    W   W   W   W   F   F   F     通路の天井
    //   row 6:    F   F   F   F   F   F   F     row6 cols1..4 = 通路床
    //
    // 右壁版はこの左右鏡像（チップは (4,1)=(104,26) ↔ (3,1)=(78,26)）。

    /// 部屋床 (cols5..7 × rows4..6) + 左から合流する通路床 (row6 cols1..4)。短 L 左のミニ盤面。
    def shortJunctionLeftFloorMask(): Set[(Int32, Int32)] =
        let roomFloor = List.range(5, 8)
            |> List.flatMap(col -> List.range(4, 7) |> List.map(row -> (col, row)))
            |> List.toSet;
        List.range(1, 5) |> List.map(col -> (col, 6)) |> List.toSet |> Set.union(roomFloor)

    /// 左右反転した右壁版のミニ盤面（部屋床 cols1..3、通路床 row6 cols4..7）。
    def shortJunctionRightFloorMask(): Set[(Int32, Int32)] =
        shortJunctionLeftFloorMask() |> Set.map(cell -> {let (col, row) = cell; (8 - col, row)})

    /// room_*.material.json の「左通路合流の左壁角」と同じ AutoRule 値。
    /// 条件: 上上=空・上=壁・左=空・中央=壁・右=床・左下=壁・下=壁・左下の下=床。
    /// 出力はタイルセット (4,1) = (104, 26)（通路天井の帯が右上へ曲がる ┘ ピース）。
    def junctionLeftRule(): MapResource.AutoRule =
        let a = MapResource.PatternCell.Unspecified;
        let w = MapResource.PatternCell.Value(2);
        let f = MapResource.PatternCell.Value(1);
        let e = MapResource.PatternCell.Nothing;
        {
            name    = "左通路合流の左壁角",
            size    = 5,
            pattern = Vector#{a, a, e, a, a,
                              a, a, w, a, a,
                              a, e, w, f, a,
                              a, w, w, a, a,
                              a, f, a, a, a},
            srcX    = 104,
            srcY    = 26
        }

    /// 「右通路合流の右壁角」= 左版の左右鏡像。出力は (3,1) = (78, 26)（└ ピース）。
    def junctionRightRule(): MapResource.AutoRule =
        let a = MapResource.PatternCell.Unspecified;
        let w = MapResource.PatternCell.Value(2);
        let f = MapResource.PatternCell.Value(1);
        let e = MapResource.PatternCell.Nothing;
        {
            name    = "右通路合流の右壁角",
            size    = 5,
            pattern = Vector#{a, a, e, a, a,
                              a, a, w, a, a,
                              a, f, w, e, a,
                              a, a, w, w, a,
                              a, a, a, f, a},
            srcX    = 78,
            srcY    = 26
        }

    /// 左版ルールは短 L の合流角 T=(4,4) にだけ発火し、チップ (104,26) を
    /// ピクセル位置 (4*26, 4*26) = (104, 104) へ出力する。
    @Test
    def testShortJunctionLeftRuleFiresAtCornerOnly(): Unit \ Assert =
        let floorMask = shortJunctionLeftFloorMask();
        let wallCells = MapLoader.computeWallCells(floorMask, 9, 8);
        let grid = MapLoader.buildIntGrid(floorMask, wallCells, 9, 8);
        let tiles = MapLoader.buildAutoRuleTiles(grid, 9, 8, junctionLeftRule() :: Nil,
                                                 (Set#{}: Set[(Int32, Int32)]), 26);
        Assert.assertEq(
            expected = (1, Some((104.0, 26.0, 104.0, 104.0))),
            (List.length(tiles),
             List.head(tiles) |> Option.map(t -> (t#srcX, t#srcY, t#px#x, t#px#y))))

    /// 右版ルールは鏡像盤面の合流角 (4,4) にだけ発火し、チップ (78,26) を出力する。
    @Test
    def testShortJunctionRightRuleFiresAtCornerOnly(): Unit \ Assert =
        let floorMask = shortJunctionRightFloorMask();
        let wallCells = MapLoader.computeWallCells(floorMask, 9, 8);
        let grid = MapLoader.buildIntGrid(floorMask, wallCells, 9, 8);
        let tiles = MapLoader.buildAutoRuleTiles(grid, 9, 8, junctionRightRule() :: Nil,
                                                 (Set#{}: Set[(Int32, Int32)]), 26);
        Assert.assertEq(
            expected = (1, Some((78.0, 26.0, 104.0, 104.0))),
            (List.length(tiles),
             List.head(tiles) |> Option.map(t -> (t#srcX, t#srcY, t#px#x, t#px#y))))

    /// 縦壁が上へ 2 セル以上続く「長い L」（部屋床を rows2..6 に拡張 → 合流角の上上が壁）では
    /// 短 L 限定ルールは発火しない（長い L は既存ルールの担当。二重発火しないことの pin）。
    @Test
    def testShortJunctionRuleSilentOnTallWall(): Unit \ Assert =
        let tallFloor = List.range(5, 8)
            |> List.flatMap(col -> List.range(2, 7) |> List.map(row -> (col, row)))
            |> List.toSet
            |> Set.union(List.range(1, 5) |> List.map(col -> (col, 6)) |> List.toSet);
        let wallCells = MapLoader.computeWallCells(tallFloor, 9, 8);
        let grid = MapLoader.buildIntGrid(tallFloor, wallCells, 9, 8);
        let tiles = MapLoader.buildAutoRuleTiles(grid, 9, 8, junctionLeftRule() :: Nil,
                                                 (Set#{}: Set[(Int32, Int32)]), 26);
        Assert.assertEq(expected = true, List.isEmpty(tiles))

    /// 通路の無い部屋だけの盤面では左右どちらのルールも発火しない（誤発火防止の pin）。
    @Test
    def testShortJunctionRuleSilentOnPlainRoom(): Unit \ Assert =
        let roomOnly = List.range(5, 8)
            |> List.flatMap(col -> List.range(4, 7) |> List.map(row -> (col, row)))
            |> List.toSet;
        let wallCells = MapLoader.computeWallCells(roomOnly, 9, 8);
        let grid = MapLoader.buildIntGrid(roomOnly, wallCells, 9, 8);
        let tiles = MapLoader.buildAutoRuleTiles(grid, 9, 8,
                                                 junctionLeftRule() :: junctionRightRule() :: Nil,
                                                 (Set#{}: Set[(Int32, Int32)]), 26);
        Assert.assertEq(expected = true, List.isEmpty(tiles))

}
