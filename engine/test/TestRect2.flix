// Tests for Rect2 module

// --- fromSize ---

/// 原点からサイズ指定で矩形を作る
@Test
def testRect2FromSize(): Unit \ Assert =
    let rect = Rect2.fromSize({x = 100.0, y = 200.0});
    Assert.assertEq(expected = (0.0, 0.0, 100.0, 200.0),
                    (rect#position#x, rect#position#y, rect#size#x, rect#size#y))

// --- end ---

/// 終端座標は position + size
@Test
def testRect2End(): Unit \ Assert =
    let rect: Rect2.Rect2 = {position = {x = 10.0, y = 20.0}, size = {x = 100.0, y = 50.0}};
    let e = Rect2.end(rect);
    Assert.assertEq(expected = (110.0, 70.0), (e#x, e#y))

/// 原点矩形の終端はサイズと一致する
@Test
def testRect2EndFromOrigin(): Unit \ Assert =
    let rect = Rect2.fromSize({x = 480.0, y = 720.0});
    let e = Rect2.end(rect);
    Assert.assertEq(expected = (480.0, 720.0), (e#x, e#y))

// --- area ---

/// 面積は width * height
@Test
def testRect2Area(): Unit \ Assert =
    let rect: Rect2.Rect2 = {position = {x = 0.0, y = 0.0}, size = {x = 30.0, y = 20.0}};
    Assert.assertEq(expected = 600.0, Rect2.area(rect))

// --- center ---

/// 中心座標は position + size / 2
@Test
def testRect2Center(): Unit \ Assert =
    let rect: Rect2.Rect2 = {position = {x = 10.0, y = 20.0}, size = {x = 100.0, y = 50.0}};
    let c = Rect2.center(rect);
    Assert.assertEq(expected = (60.0, 45.0), (c#x, c#y))

/// 原点矩形の中心はサイズの半分
@Test
def testRect2CenterFromOrigin(): Unit \ Assert =
    let rect = Rect2.fromSize({x = 480.0, y = 720.0});
    let c = Rect2.center(rect);
    Assert.assertEq(expected = (240.0, 360.0), (c#x, c#y))

// --- hasPoint ---

/// 矩形内部の点は含まれる
@Test
def testRect2HasPointInside(): Unit \ Assert =
    let rect = Rect2.fromSize({x = 100.0, y = 100.0});
    Assert.assertTrue(Rect2.hasPoint({x = 50.0, y = 50.0}, rect))

/// 矩形外部の点は含まれない
@Test
def testRect2HasPointOutside(): Unit \ Assert =
    let rect = Rect2.fromSize({x = 100.0, y = 100.0});
    Assert.assertFalse(Rect2.hasPoint({x = 150.0, y = 50.0}, rect))

/// 矩形の境界上の点は含まれる
@Test
def testRect2HasPointOnEdge(): Unit \ Assert =
    let rect = Rect2.fromSize({x = 100.0, y = 100.0});
    Assert.assertTrue(Rect2.hasPoint({x = 100.0, y = 100.0}, rect))

/// オフセットされた矩形での判定
@Test
def testRect2HasPointWithOffset(): Unit \ Assert =
    let rect: Rect2.Rect2 = {position = {x = 50.0, y = 50.0}, size = {x = 100.0, y = 100.0}};
    // 矩形は (50,50) ~ (150,150)
    Assert.assertEq(
        expected = (false, true, false),
        (Rect2.hasPoint({x = 30.0, y = 80.0}, rect),
         Rect2.hasPoint({x = 80.0, y = 80.0}, rect),
         Rect2.hasPoint({x = 200.0, y = 80.0}, rect)))
