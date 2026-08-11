// WallFaces（見える壁面の収集）— eye に向く面だけが残ること、壁どうしの
// 内部面が出ないこと、面の線分がセル境界 ±0.5 に載ること。
mod TestWallFaces {

    def loneWall(): Grid.Cell -> Bool = c -> c#x == 2 and c#y == 2

    @Test
    def testLoneWallShowsOnlyEyeFacingFace(): Unit \ Assert =
        // 真横（左）から見た孤立壁は、左面 1 枚だけ（法線が eye 側の -x を向く）。
        let faces = WallFaces.visibleFaces(loneWall(), 4, { x = 0.0, y = 2.0 });
        let nx = faces |> List.head |> Option.map(f -> f#normal#x) |> Option.getWithDefault(0.0);
        Assert.assertEq(expected = (1, -1.0), (List.length(faces), nx))

    @Test
    def testInternalFaceBetweenWallsIsDropped(): Unit \ Assert =
        // 壁 2 マスが横に並んでも、共有境界の面は出ない — 左から見て左面 1 枚のまま。
        let solid = c -> (c#x == 2 or c#x == 3) and c#y == 2;
        Assert.assertEq(expected = 1,
            List.length(WallFaces.visibleFaces(solid, 4, { x = 0.0, y = 2.0 })))

    @Test
    def testFaceOfLiesOnCellBoundary(): Unit \ Assert =
        // セル (2,3) の右面は x = 2.5 の縦線分（y は 2.5 → 3.5）。
        let f = WallFaces.faceOf({ x = 2, y = 3 }, Dir4.Dir4.Right);
        Assert.assertEq(expected = (2.5, 2.5, 2.5, 3.5), (f#a#x, f#a#y, f#b#x, f#b#y))

    @Test
    def testPointAtEndsMatchAAndB(): Unit \ Assert =
        // t = 0 が a・t = 1 が b にぴったり一致（模様の世界固定の前提）。
        let f = WallFaces.faceOf({ x = 0, y = 0 }, Dir4.Dir4.Up);
        let p0 = WallFaces.pointAt(f, 0.0);
        let p1 = WallFaces.pointAt(f, 1.0);
        Assert.assertEq(expected = (f#a#x, f#a#y, f#b#x, f#b#y), (p0#x, p0#y, p1#x, p1#y))
}
