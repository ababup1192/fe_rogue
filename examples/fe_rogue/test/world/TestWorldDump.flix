// ── WorldDump: 注釈チケット（F8）に同梱する world.json の組み立て ──
//
// 検証するのは 3 つの芯: 壁キーの読み方（TRBL 3 値）・カメラ投影の逆変換・
// 矩形からセルへの割り付け。JSON の文字列表現そのものは Util.Json に任せる。

/// 3×3 の小さな盤面。壁は (1,0) と (1,2) の 2 セルで、範囲内の残りは床。
///
///   . W .      W = 壁 / それ以外の範囲内 = 床 / 範囲外 = E 扱い
///   F . F
///   . W .
def worldDumpTerrainFixture(): MapSnapshot =
    { tileSize = 26.0,
      usedRect = { position = {x = 0, y = 0}, size = {x = 3, y = 3} },
      wallCells = Set#{(1, 0), (1, 2)},
      mapGlobal = {x = 0.0, y = 0.0},
      placements = Nil }

/// 壁キーは上右下左の順に W(壁)/F(床)/E(どちらでもない) を並べた 4 文字。
/// 床セル集合なし（None）では「範囲内かつ非壁 = F」に落ちる旧挙動:
/// 中央セル (1,1) は上下が壁・左右が床で "WFWF"、
/// 左上角 (0,0) は上と左が範囲外・右が壁・下が床で "EWFE"。
@Test
def testWorldDumpWallTritKey(): Unit \ Assert =
    let terrain = worldDumpTerrainFixture();
    Assert.assertEq(
        expected = ("WFWF", "EWFE"),
        (WorldDump.wallTritKey({x = 1, y = 1}, None, terrain),
         WorldDump.wallTritKey({x = 0, y = 0}, None, terrain)))

/// 床セル集合を渡すと「範囲内だが床が無い空間（void）」が E になる。
/// fixture の床を右列 (2,1) だけに絞ると、中央セル (1,1) の左 (0,1) は
/// 範囲内・非壁のまま床でなくなり、キーは "WFWF" → "WFWE" に変わる
/// （レンダラの trit キーと同じ基準。None 挙動との差分を pin）。
@Test
def testWorldDumpWallTritKeyDistinguishesVoidFromFloor(): Unit \ Assert =
    let terrain = worldDumpTerrainFixture();
    Assert.assertEq(
        expected = "WFWE",
        WorldDump.wallTritKey({x = 1, y = 1}, Some(Set#{(2, 1)}), terrain))

/// screenToWorld はカメラ投影の逆変換。画面中央（デザイン 240×128 の (120, 64)）は
/// ズームによらず「カメラが中央に映しているワールド座標」そのものへ戻る。
@Test
def testWorldDumpScreenToWorldCenter(): Unit \ Assert =
    let camera = Camera.make({x = 100.0, y = 50.0}) |> Camera.setZoom({x = 0.5, y = 0.5});
    let center = WorldDump.screenToWorld({x = 120.0, y = 64.0}, camera);
    Assert.assertEq(expected = (100.0, 50.0), (center#x, center#y))

/// 盤面レス（地形なし）の World では、囲ったセルの列挙は空になる（タイトル画面で
/// 注釈を書いても cellsInRect が出ないだけで落ちない）。
@Test
def testWorldDumpCellsUnderWithoutTerrain(): Unit \ Assert =
    let rect = { position = {x = 100.0, y = 60.0}, size = {x = 20.0, y = 20.0} };
    Assert.assertEq(expected = Nil,
                    WorldDump.cellsUnder(rect, World.empty()) |> List.map(cell -> (cell#x, cell#y)))

/// 地形あり・初期カメラ（原点・ズーム 0.32）の World で、画面中央から右下 16px 四方の
/// 矩形を囲うと、ワールドでは 50px 四方（16 / 0.32）に相当し、セル幅 26px の
/// 2×2 セル（(0,0)〜(1,1)）へ行順に割り付く。
@Test
def testWorldDumpCellsUnderCoversZoomedCells(): Unit \ Assert =
    let world = World.applyCmd(World.Cmd.SetMapSnapshot(Some(worldDumpTerrainFixture())), World.empty());
    let rect = { position = {x = 120.0, y = 64.0}, size = {x = 16.0, y = 16.0} };
    Assert.assertEq(
        expected = (0, 0) :: (1, 0) :: (0, 1) :: (1, 1) :: Nil,
        WorldDump.cellsUnder(rect, world) |> List.map(cell -> (cell#x, cell#y)))

/// フロア全体の ASCII 地図。fixture の 3×3 盤面では壁 2 セルが # に、床が . になり、
/// カーソル（World.empty の初期位置 (0,0)）が + として床の上に重なる。
///
///   +#.      1 行目: カーソル・壁・床
///   ...      2 行目: すべて床
///   .#.      3 行目: 床・壁・床
@Test
def testWorldDumpMapRowsAscii(): Unit \ Assert =
    let world = World.applyCmd(World.Cmd.SetMapSnapshot(Some(worldDumpTerrainFixture())), World.empty());
    Assert.assertEq(expected = "+#." :: "..." :: ".#." :: Nil, WorldDump.mapRows(Nil, world))

/// 床セル集合（MapFloorInfo）を seed すると、範囲内・非壁でも床でないセルは `,`（盤内 void）になる。
/// fixture の床を (2,1) と (0,2) だけに絞った地図:
///
///   +#,      1 行目: カーソル・壁・void
///   ,,.      2 行目: void・void・床
///   .#,      3 行目: 床・壁・void
@Test
def testWorldDumpMapRowsVoidGlyph(): Unit \ Assert =
    let world = World.empty()
        |> World.applyCmd(World.Cmd.SetMapSnapshot(Some(worldDumpTerrainFixture())))
        |> World.applyCmd(World.Cmd.SetMapFloorInfo(Some(
               {materialId = "room_1", floorCells = Set#{(2, 1), (0, 2)}})));
    Assert.assertEq(expected = "+#," :: ",,." :: ".#," :: Nil, WorldDump.mapRows(Nil, world))

/// 水路入りの 3×3 盤面。壁は (1,0)(1,2)(0,2) だが (1,0) は床セル集合にも入る
/// （水路 = 通行不可なのに床として描かれるセル）。(0,2) はどの描画床の 8 近傍でもない。
///
///   . ~ .      ~ = 水路（壁かつ描画床） / それ以外の壁 = W
///   . . F      F = 床セル集合 {(1,0), (2,1)}
///   W W .
def worldDumpTroughTerrainFixture(): MapSnapshot =
    { tileSize = 26.0,
      usedRect = { position = {x = 0, y = 0}, size = {x = 3, y = 3} },
      wallCells = Set#{(1, 0), (1, 2), (0, 2)},
      mapGlobal = {x = 0.0, y = 0.0},
      placements = Nil }

/// 通行不可でも床セル集合に入るセル（水路）は地図で `~` になり、純粋な壁 `#` と区別される。
/// タイルベイクは水路を床として数えるので、再現器が地図から床マスクを正しく復元できる。
///
///   +~,      1 行目: カーソル・水路・void
///   ,,.      2 行目: void・void・床
///   ##,      3 行目: 壁・壁・void
@Test
def testWorldDumpMapRowsTroughGlyph(): Unit \ Assert =
    let world = World.empty()
        |> World.applyCmd(World.Cmd.SetMapSnapshot(Some(worldDumpTroughTerrainFixture())))
        |> World.applyCmd(World.Cmd.SetMapFloorInfo(Some(
               {materialId = "room_2", floorCells = Set#{(1, 0), (2, 1)}})));
    Assert.assertEq(expected = "+~," :: ",,." :: "##," :: Nil, WorldDump.mapRows(Nil, world))

/// 床セル集合ありの壁キーはタイルベイクと同じ基準: W=壁リング（描画床の 8 近傍）所属・
/// F=床セル集合所属・E=それ以外。(1,1) は上の水路 (1,0) が F・下 (1,2) と左 (0,1) が
/// リングで W → "FFWW"。(0,1) の下 (0,2) は通行不可でもリング外なので E → "WWEE"
/// （地形基準だと W と出て、実際に焼かれるチップとずれる）。
@Test
def testWorldDumpWallTritKeyUsesBakeRing(): Unit \ Assert =
    let terrain = worldDumpTroughTerrainFixture();
    let floorCells = Some(Set#{(1, 0), (2, 1)});
    Assert.assertEq(
        expected = ("FFWW", "WWEE"),
        (WorldDump.wallTritKey({x = 1, y = 1}, floorCells, terrain),
         WorldDump.wallTritKey({x = 0, y = 1}, floorCells, terrain)))

/// MapFloorInfo store の round-trip: seed した materialId / 床セル集合が読め、
/// 未 seed（World.empty）は None。
@Test
def testWorldDumpMapFloorInfoStoreRoundTrip(): Unit \ Assert =
    let world = World.applyCmd(World.Cmd.SetMapFloorInfo(Some(
        {materialId = "room_3", floorCells = Set#{(1, 1)}})), World.empty());
    Assert.assertEq(
        expected = (Some(("room_3", 1)), None),
        (World.mapFloorInfoOf(world) |> Option.map(info -> (info#materialId, Set.size(info#floorCells))),
         World.mapFloorInfoOf(World.empty()) |> Option.map(info -> info#materialId)))

/// タイル列 → セルごとのチップ列。同じセル (1,0) に床チップ (0,2) と壁チップ (3,1) を
/// この順で置くと、チップ列も下 → 上の同じ順で並ぶ（px / src はピクセル値で、
/// tileSize=26 で割ったグリッド座標に落ちる）。
@Test
def testWorldDumpChipsOfTilesStacksInDrawOrder(): Unit \ Assert =
    let floorTile = ({px = {x = 26.0, y = 0.0}, srcX = 0.0,  srcY = 52.0,
                      flipH = false, flipV = false, alpha = 1.0f32,
                      tint = TileLayer.noTint()}: TileData);
    let wallTile  = ({px = {x = 26.0, y = 0.0}, srcX = 78.0, srcY = 26.0,
                      flipH = false, flipV = false, alpha = 1.0f32,
                      tint = TileLayer.noTint()}: TileData);
    let chips = MapSetup.chipsOfTiles(26.0, floorTile :: wallTile :: Nil, Map.empty());
    Assert.assertEq(
        expected = (0, 2) :: (3, 1) :: Nil,
        Map.get((1, 0), chips) |> Option.getWithDefault(Nil) |> List.map(chip -> (chip#x, chip#y)))

/// SetTileChips で seed したチップ列は tileChipsAtOf で読め、seed の無いセルは空になる。
@Test
def testWorldDumpTileChipsStoreRoundTrip(): Unit \ Assert =
    let chips = Map#{(2, 3) => {x = 5, y = 1} :: Nil};
    let world = World.applyCmd(World.Cmd.SetTileChips(chips), World.empty());
    Assert.assertEq(
        expected = ((5, 1) :: Nil, Nil),
        (World.tileChipsAtOf({x = 2, y = 3}, world) |> List.map(chip -> (chip#x, chip#y)),
         World.tileChipsAtOf({x = 0, y = 0}, world) |> List.map(chip -> (chip#x, chip#y))))

/// dump の出力は機械可読（JSON としてパースが通る）。中身の網羅は上のテスト群が担い、
/// ここは「AI やツールがそのまま読める形式で出ている」ことだけを固定する。
@Test
def testWorldDumpProducesValidJson(): Unit \ Assert =
    let rect = { position = {x = 100.0, y = 60.0}, size = {x = 20.0, y = 20.0} };
    Assert.assertTrue(WorldDump.dump(rect, World.empty()) |> Util.Json.parse |> Result.isOk)
