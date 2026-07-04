// Quad のテスト。回転矩形の頂点と、帯（strip）の等幅性を固定する。
// Vec2 は Eq 非導出なので、頂点は (x, y) のタプル列に落として比較する。

mod TestQuad {

    /// 角度0の回転矩形は軸並行の長方形：中心 (10,20)・halfW 2・halfH 3 なら
    /// 角は (8,17),(12,17),(12,23),(8,23)。
    @Test
    def testRotatedAxisAligned(): Unit \ Assert =
        let corners = Quad.rotated({x = 10.0, y = 20.0}, 2.0, 3.0, 0.0);
        Assert.assertEq(
            expected = (8.0, 17.0) :: (12.0, 17.0) :: (12.0, 23.0) :: (8.0, 23.0) :: Nil,
            List.map(p -> (p#x, p#y), corners))

    /// 水平な中心線の帯：along=(1,0)・normal=(0,1) なので、offset がそのまま y になる。
    /// p0=(0,0) p1=(10,0) o1=-1 o2=1 → 頂点 (0,-1),(10,-1),(10,1),(0,1)。
    @Test
    def testStripHorizontal(): Unit \ Assert =
        let band = Quad.strip({x = 0.0, y = 0.0}, {x = 10.0, y = 0.0}, -1.0, 1.0);
        Assert.assertEq(
            expected = (0.0, -1.0) :: (10.0, -1.0) :: (10.0, 1.0) :: (0.0, 1.0) :: Nil,
            List.map(p -> (p#x, p#y), band))

    /// 等幅性：向きに依らず帯の幅は |o2 - o1|。斜め (3,4) の 3-4-5 線分でも、
    /// 始端側の2頂点（先頭 = p0+n*o1、末尾 = p0+n*o2）の距離は 5.0 になる。
    @Test
    def testStripConstantWidthOnDiagonal(): Unit \ Assert =
        let band = Quad.strip({x = 0.0, y = 0.0}, {x = 3.0, y = 4.0}, -2.0, 3.0);
        let widthAtStart = forM (first <- List.head(band); last <- List.last(band))
                           yield Vec2.distanceTo(first, last);
        Assert.assertEq(expected = Some(true),
            Option.map(w -> Float64.abs(w - 5.0) < 0.000001, widthAtStart))

    /// orientedByAxis は axis=(1,0)（ローカル +x そのまま）のとき rotated の angle=0 と
    /// 完全に一致する（頂点も巻き順も同じ）。
    @Test
    def testOrientedByAxisEqualsRotatedAtZero(): Unit \ Assert =
        let byAxis = Quad.orientedByAxis({x = 10.0, y = 20.0}, {x = 1.0, y = 0.0}, 2.0, 3.0);
        let byAngle = Quad.rotated({x = 10.0, y = 20.0}, 2.0, 3.0, 0.0);
        Assert.assertEq(
            expected = List.map(p -> (p#x, p#y), byAngle),
            List.map(p -> (p#x, p#y), byAxis))

    /// orientedByAxis の axis=(0,1) は 90° 回した箱：+x 軸が +y を向く。中心 (10,20)・
    /// halfLen 2・halfThick 3 なら角は (13,18),(13,22),(7,22),(7,18)（rotated と同じ巻き順）。
    @Test
    def testOrientedByAxisQuarterTurn(): Unit \ Assert =
        let corners = Quad.orientedByAxis({x = 10.0, y = 20.0}, {x = 0.0, y = 1.0}, 2.0, 3.0);
        Assert.assertEq(
            expected = (13.0, 18.0) :: (13.0, 22.0) :: (7.0, 22.0) :: (7.0, 18.0) :: Nil,
            List.map(p -> (p#x, p#y), corners))
}
