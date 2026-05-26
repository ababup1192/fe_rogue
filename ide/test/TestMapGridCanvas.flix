// Tests for MapGridCanvas の pure place/remove ヘルパー群
//
// 観点:
//   - Walls レイヤーの place/remove は manualTiles のみを動かす (装飾上書き層)
//   - Floor レイヤーの place/remove は decorTiles のみを動かす (床)
//   - 同セル既存タイルは置換され、重複しない
//
// 衝突は wallMask ではなく decorTiles の 8 近傍判定で自動計算されるため、
// 衝突に関するテストは MapLoader (engine) 側で扱う。

mod TestMapGridCanvas {

    /// 3×3 の空 Level (manualTiles/decorTiles 空)。
    def emptyLevel3x3(): MapResource.Level = {
        let data: MapResource.LevelData = {
            tileSize      = 16,
            width         = 3,
            height        = 3,
            materialId    = "inca_stone",
            manualTiles   = (Nil: List[MapResource.ManualTile]),
            decorTiles    = (Nil: List[MapResource.ManualTile]),
            entities      = (Nil: List[MapResource.Entity]),
            editorPalette = (None: Option[MapResource.EditorPalette])
        };
        MapResource.Level.Level(data)
    }

    def manualTileCount(level: MapResource.Level): Int32 =
        let d = MapResource.levelData(level);
        List.length(d#manualTiles)

    def decorTileCount(level: MapResource.Level): Int32 =
        let d = MapResource.levelData(level);
        List.length(d#decorTiles)

    /// 指定 (col, row) に manualTiles が 1 件以上あるか。
    def hasManualAt(level: MapResource.Level, col: Int32, row: Int32): Bool =
        let d = MapResource.levelData(level);
        List.exists(t -> t#x == col and t#y == row, d#manualTiles)

    def hasDecorAt(level: MapResource.Level, col: Int32, row: Int32): Bool =
        let d = MapResource.levelData(level);
        List.exists(t -> t#x == col and t#y == row, d#decorTiles)

    // ========================================================================
    // placeWallTileAt — manualTiles に追加 (自動壁の上書き、wallMask は概念ごと無い)
    // ========================================================================

    @Test
    def testPlaceWallTileAddsManualTile(): Unit \ Assert =
        let level = emptyLevel3x3();
        let d = MapResource.levelData(level);
        let result = MapGridCanvas.placeWallTileAt(level, d, 1i32, 1i32, 176i32, 16i32);
        Assert.assertEq(expected = true, hasManualAt(result, 1i32, 1i32))

    @Test
    def testPlaceWallTileReplacesExisting(): Unit \ Assert =
        let level = emptyLevel3x3();
        let d0 = MapResource.levelData(level);
        let r1 = MapGridCanvas.placeWallTileAt(level, d0, 2i32, 0i32, 100i32, 0i32);
        let d1 = MapResource.levelData(r1);
        let r2 = MapGridCanvas.placeWallTileAt(r1, d1, 2i32, 0i32, 200i32, 0i32);
        // 同セルに 2 回置いてもタイル数は 1
        Assert.assertEq(expected = 1i32, manualTileCount(r2))

    @Test
    def testPlaceWallTileDoesNotTouchDecor(): Unit \ Assert =
        let level = emptyLevel3x3();
        let d = MapResource.levelData(level);
        let result = MapGridCanvas.placeWallTileAt(level, d, 1i32, 1i32, 176i32, 16i32);
        Assert.assertEq(expected = 0i32, decorTileCount(result))

    // ========================================================================
    // removeWallTileAt — manualTiles 削除
    // ========================================================================

    @Test
    def testRemoveWallTileRemovesManualTile(): Unit \ Assert =
        let level = emptyLevel3x3();
        let d0 = MapResource.levelData(level);
        let placed = MapGridCanvas.placeWallTileAt(level, d0, 0i32, 1i32, 176i32, 16i32);
        let d1 = MapResource.levelData(placed);
        let removed = MapGridCanvas.removeWallTileAt(placed, d1, 0i32, 1i32);
        Assert.assertEq(expected = false, hasManualAt(removed, 0i32, 1i32))

    // ========================================================================
    // placeFloorTileAt — decorTiles のみ追加
    // ========================================================================

    @Test
    def testPlaceFloorTileAddsDecorTile(): Unit \ Assert =
        let level = emptyLevel3x3();
        let d = MapResource.levelData(level);
        let result = MapGridCanvas.placeFloorTileAt(level, d, 1i32, 2i32, 17i32, 68i32);
        Assert.assertEq(expected = true, hasDecorAt(result, 1i32, 2i32))

    @Test
    def testPlaceFloorTileDoesNotTouchManualTiles(): Unit \ Assert =
        let level = emptyLevel3x3();
        let d = MapResource.levelData(level);
        let result = MapGridCanvas.placeFloorTileAt(level, d, 1i32, 2i32, 17i32, 68i32);
        Assert.assertEq(expected = 0i32, manualTileCount(result))

    @Test
    def testPlaceFloorTileReplacesExisting(): Unit \ Assert =
        let level = emptyLevel3x3();
        let d0 = MapResource.levelData(level);
        let r1 = MapGridCanvas.placeFloorTileAt(level, d0, 0i32, 0i32, 17i32, 68i32);
        let d1 = MapResource.levelData(r1);
        let r2 = MapGridCanvas.placeFloorTileAt(r1, d1, 0i32, 0i32, 34i32, 68i32);
        Assert.assertEq(expected = 1i32, decorTileCount(r2))

    // ========================================================================
    // removeFloorTileAt — decorTiles のみ削除
    // ========================================================================

    @Test
    def testRemoveFloorTileRemovesDecorTile(): Unit \ Assert =
        let level = emptyLevel3x3();
        let d0 = MapResource.levelData(level);
        let placed = MapGridCanvas.placeFloorTileAt(level, d0, 2i32, 2i32, 17i32, 68i32);
        let d1 = MapResource.levelData(placed);
        let removed = MapGridCanvas.removeFloorTileAt(placed, d1, 2i32, 2i32);
        Assert.assertEq(expected = false, hasDecorAt(removed, 2i32, 2i32))

    @Test
    def testRemoveFloorTileDoesNotTouchManualTiles(): Unit \ Assert =
        let level = emptyLevel3x3();
        let d0 = MapResource.levelData(level);
        let wallPlaced = MapGridCanvas.placeWallTileAt(level, d0, 1i32, 1i32, 176i32, 16i32);
        let d1 = MapResource.levelData(wallPlaced);
        let result = MapGridCanvas.removeFloorTileAt(wallPlaced, d1, 1i32, 1i32);
        Assert.assertEq(expected = 1i32, manualTileCount(result))
}
