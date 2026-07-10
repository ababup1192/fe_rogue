// Tests for CollisionShape2D module

// ========================================================================
// checkRectRect
// ========================================================================

/// 重なっている矩形
@Test
def testRectRectOverlapping(): Unit \ Assert =
    let posA = {x = 0.0, y = 0.0};
    let posB = {x = 3.0, y = 0.0};
    let sizeA = {x = 4.0, y = 4.0};
    let sizeB = {x = 4.0, y = 4.0};
    Assert.assertEq(expected = true, CollisionShape2D.checkRectRect(posA, sizeA, posB, sizeB))

/// 離れている矩形
@Test
def testRectRectNotOverlapping(): Unit \ Assert =
    let posA = {x = 0.0, y = 0.0};
    let posB = {x = 10.0, y = 0.0};
    let sizeA = {x = 4.0, y = 4.0};
    let sizeB = {x = 4.0, y = 4.0};
    Assert.assertEq(expected = false, CollisionShape2D.checkRectRect(posA, sizeA, posB, sizeB))

/// 辺が接触（タンジェント）は重ならない
@Test
def testRectRectTouching(): Unit \ Assert =
    let posA = {x = 0.0, y = 0.0};
    let posB = {x = 4.0, y = 0.0};
    let sizeA = {x = 4.0, y = 4.0};
    let sizeB = {x = 4.0, y = 4.0};
    Assert.assertEq(expected = false, CollisionShape2D.checkRectRect(posA, sizeA, posB, sizeB))

/// 完全に包含
@Test
def testRectRectContained(): Unit \ Assert =
    let posA = {x = 0.0, y = 0.0};
    let posB = {x = 0.0, y = 0.0};
    let sizeA = {x = 10.0, y = 10.0};
    let sizeB = {x = 2.0, y = 2.0};
    Assert.assertEq(expected = true, CollisionShape2D.checkRectRect(posA, sizeA, posB, sizeB))

// ========================================================================
// checkCircleCircle
// ========================================================================

/// 重なっている円
@Test
def testCircleCircleOverlapping(): Unit \ Assert =
    let posA = {x = 0.0, y = 0.0};
    let posB = {x = 3.0, y = 0.0};
    Assert.assertEq(expected = true, CollisionShape2D.checkCircleCircle(posA, 2.0, posB, 2.0))

/// 離れている円
@Test
def testCircleCircleNotOverlapping(): Unit \ Assert =
    let posA = {x = 0.0, y = 0.0};
    let posB = {x = 10.0, y = 0.0};
    Assert.assertEq(expected = false, CollisionShape2D.checkCircleCircle(posA, 2.0, posB, 2.0))

/// 接触（タンジェント）は重ならない
@Test
def testCircleCircleTouching(): Unit \ Assert =
    let posA = {x = 0.0, y = 0.0};
    let posB = {x = 4.0, y = 0.0};
    Assert.assertEq(expected = false, CollisionShape2D.checkCircleCircle(posA, 2.0, posB, 2.0))

// ========================================================================
// checkCircleRect
// ========================================================================

/// 円が矩形の辺に重なる
@Test
def testCircleRectOverlappingSide(): Unit \ Assert =
    let circlePos = {x = 0.0, y = 3.0};
    let rectPos = {x = 0.0, y = 0.0};
    let rectSize = {x = 4.0, y = 4.0};
    Assert.assertEq(expected = true, CollisionShape2D.checkCircleRect(circlePos, 2.0, rectPos, rectSize))

/// 円が矩形から離れている
@Test
def testCircleRectNotOverlapping(): Unit \ Assert =
    let circlePos = {x = 10.0, y = 10.0};
    let rectPos = {x = 0.0, y = 0.0};
    let rectSize = {x = 4.0, y = 4.0};
    Assert.assertEq(expected = false, CollisionShape2D.checkCircleRect(circlePos, 2.0, rectPos, rectSize))

/// 円が矩形のコーナーに重なる
@Test
def testCircleRectCornerOverlap(): Unit \ Assert =
    let circlePos = {x = 3.0, y = 3.0};
    let rectPos = {x = 0.0, y = 0.0};
    let rectSize = {x = 4.0, y = 4.0};
    Assert.assertEq(expected = true, CollisionShape2D.checkCircleRect(circlePos, 2.0, rectPos, rectSize))

/// 円が矩形のコーナー外側で離れている
@Test
def testCircleRectCornerMiss(): Unit \ Assert =
    let circlePos = {x = 4.0, y = 4.0};
    let rectPos = {x = 0.0, y = 0.0};
    let rectSize = {x = 4.0, y = 4.0};
    Assert.assertEq(expected = false, CollisionShape2D.checkCircleRect(circlePos, 1.0, rectPos, rectSize))

/// 円の中心が矩形の内部にある
@Test
def testCircleRectCircleInsideRect(): Unit \ Assert =
    let circlePos = {x = 0.5, y = 0.5};
    let rectPos = {x = 0.0, y = 0.0};
    let rectSize = {x = 10.0, y = 10.0};
    Assert.assertEq(expected = true, CollisionShape2D.checkCircleRect(circlePos, 1.0, rectPos, rectSize))

// ========================================================================
// checkOverlap（汎用ディスパッチ）
// ========================================================================

/// RectShape2D 同士のディスパッチ
@Test
def testCheckOverlapRectRect(): Unit \ Assert =
    let shapeA = CollisionShape2D.RectShape2D({width = 4.0, height = 4.0});
    let shapeB = CollisionShape2D.RectShape2D({width = 4.0, height = 4.0});
    let posA = {x = 0.0, y = 0.0};
    let posB = {x = 3.0, y = 0.0};
    Assert.assertEq(expected = true, CollisionShape2D.checkOverlap(posA, shapeA, posB, shapeB))

/// CircleShape2D 同士のディスパッチ
@Test
def testCheckOverlapCircleCircle(): Unit \ Assert =
    let shapeA = CollisionShape2D.CircleShape2D({radius = 2.0});
    let shapeB = CollisionShape2D.CircleShape2D({radius = 2.0});
    let posA = {x = 0.0, y = 0.0};
    let posB = {x = 3.0, y = 0.0};
    Assert.assertEq(expected = true, CollisionShape2D.checkOverlap(posA, shapeA, posB, shapeB))

/// Circle vs Rect のディスパッチ
@Test
def testCheckOverlapCircleRect(): Unit \ Assert =
    let shapeA = CollisionShape2D.CircleShape2D({radius = 2.0});
    let shapeB = CollisionShape2D.RectShape2D({width = 4.0, height = 4.0});
    let posA = {x = 0.0, y = 3.0};
    let posB = {x = 0.0, y = 0.0};
    Assert.assertEq(expected = true, CollisionShape2D.checkOverlap(posA, shapeA, posB, shapeB))

/// Rect vs Circle のディスパッチ（逆順）
@Test
def testCheckOverlapRectCircle(): Unit \ Assert =
    let shapeA = CollisionShape2D.RectShape2D({width = 4.0, height = 4.0});
    let shapeB = CollisionShape2D.CircleShape2D({radius = 2.0});
    let posA = {x = 0.0, y = 0.0};
    let posB = {x = 0.0, y = 3.0};
    Assert.assertEq(expected = true, CollisionShape2D.checkOverlap(posA, shapeA, posB, shapeB))

// ========================================================================
// capsuleSegment
// ========================================================================

/// 縦向きカプセル: 高さ 10, 半径 2 → 軸線分 ±3
///
///       segA (0, -3)
///        |
///   pos (0, 0)
///        |
///       segB (0, +3)
///
@Test
def testCapsuleSegmentVertical(): Unit \ Assert =
    let (segA, segB) = CollisionShape2D.capsuleSegment({x = 0.0, y = 0.0}, 2.0, 10.0, true);
    Assert.assertEq(expected = (0.0, -3.0, 0.0, 3.0), (segA#x, segA#y, segB#x, segB#y))

/// 横向きカプセル: 高さ 10, 半径 2 → 軸線分 ±3
///
///   segA (-3, 0) --- pos (0, 0) --- segB (+3, 0)
///
@Test
def testCapsuleSegmentHorizontal(): Unit \ Assert =
    let (segA, segB) = CollisionShape2D.capsuleSegment({x = 0.0, y = 0.0}, 2.0, 10.0, false);
    Assert.assertEq(expected = (-3.0, 0.0, 3.0, 0.0), (segA#x, segA#y, segB#x, segB#y))

/// 高さが直径以下のカプセル: 軸線分の長さが 0 になる
@Test
def testCapsuleSegmentDegenerateToCircle(): Unit \ Assert =
    let (segA, segB) = CollisionShape2D.capsuleSegment({x = 5.0, y = 5.0}, 3.0, 4.0, true);
    Assert.assertEq(expected = (5.0, 5.0, 5.0, 5.0), (segA#x, segA#y, segB#x, segB#y))

// ========================================================================
// pointToSegmentDistSq
// ========================================================================

/// 点が線分の中間投影上にある場合
///
///     * point (2, 3)
///     |
///   A(0,0)-----B(4,0)
///
@Test
def testPointToSegmentDistSqProjection(): Unit \ Assert =
    let distSq = CollisionShape2D.pointToSegmentDistSq({x = 2.0, y = 3.0}, {x = 0.0, y = 0.0}, {x = 4.0, y = 0.0});
    Assert.assertEq(expected = 9.0, distSq)

/// 点が線分の端点 A 側にある場合
@Test
def testPointToSegmentDistSqEndpointA(): Unit \ Assert =
    let distSq = CollisionShape2D.pointToSegmentDistSq({x = -1.0, y = 0.0}, {x = 0.0, y = 0.0}, {x = 4.0, y = 0.0});
    Assert.assertEq(expected = 1.0, distSq)

/// 退化した線分（点）の場合
@Test
def testPointToSegmentDistSqDegenerate(): Unit \ Assert =
    let distSq = CollisionShape2D.pointToSegmentDistSq({x = 3.0, y = 4.0}, {x = 0.0, y = 0.0}, {x = 0.0, y = 0.0});
    Assert.assertEq(expected = 25.0, distSq)

// ========================================================================
// checkCapsuleCircle
// ========================================================================

/// 縦向きカプセルと円が重なっている
///
///    (cap)    radius=2, height=10
///     | |
///     | |     (circle) radius=2 at (3, 0)
///     | |
///
@Test
def testCapsuleCircleOverlapping(): Unit \ Assert =
    Assert.assertEq(expected = true,
        CollisionShape2D.checkCapsuleCircle(
            {x = 0.0, y = 0.0}, 2.0, 10.0, true,
            {x = 3.0, y = 0.0}, 2.0))

/// 縦向きカプセルと円が離れている
@Test
def testCapsuleCircleNotOverlapping(): Unit \ Assert =
    Assert.assertEq(expected = false,
        CollisionShape2D.checkCapsuleCircle(
            {x = 0.0, y = 0.0}, 2.0, 10.0, true,
            {x = 10.0, y = 0.0}, 2.0))

/// カプセルの端点付近で円と重なる
@Test
def testCapsuleCircleOverlapNearEnd(): Unit \ Assert =
    Assert.assertEq(expected = true,
        CollisionShape2D.checkCapsuleCircle(
            {x = 0.0, y = 0.0}, 2.0, 10.0, true,
            {x = 0.0, y = 7.0}, 2.5))

/// カプセルの端点から離れている
@Test
def testCapsuleCircleMissNearEnd(): Unit \ Assert =
    Assert.assertEq(expected = false,
        CollisionShape2D.checkCapsuleCircle(
            {x = 0.0, y = 0.0}, 2.0, 10.0, true,
            {x = 0.0, y = 8.0}, 2.0))

// ========================================================================
// checkCapsuleRect
// ========================================================================

/// 縦向きカプセルと矩形が重なっている（辺領域）
///
///   capsule x: [-2, 2]  rect x: [1.5, 5.5]
///   → 重なりあり
///
@Test
def testCapsuleRectOverlappingSide(): Unit \ Assert =
    Assert.assertEq(expected = true,
        CollisionShape2D.checkCapsuleRect(
            {x = 0.0, y = 0.0}, 2.0, 10.0, true,
            {x = 3.5, y = 0.0}, {x = 4.0, y = 4.0}))

/// 縦向きカプセルと矩形が離れている
@Test
def testCapsuleRectNotOverlapping(): Unit \ Assert =
    Assert.assertEq(expected = false,
        CollisionShape2D.checkCapsuleRect(
            {x = 0.0, y = 0.0}, 2.0, 10.0, true,
            {x = 20.0, y = 0.0}, {x = 4.0, y = 4.0}))

/// カプセルの半径範囲内で矩形の角と重なる
///
///   capsule segment: (0,-3) to (0,3), radius=2
///   rect: center (2.5, 4.5), half=(1,1) → corner at (1.5, 3.5)
///   端点 (0,3) からコーナー (1.5, 3.5) まで: sqrt(2.25+0.25)=sqrt(2.5)≈1.58 < 2.0
///
@Test
def testCapsuleRectCornerOverlap(): Unit \ Assert =
    Assert.assertEq(expected = true,
        CollisionShape2D.checkCapsuleRect(
            {x = 0.0, y = 0.0}, 2.0, 10.0, true,
            {x = 2.5, y = 4.5}, {x = 2.0, y = 2.0}))

/// カプセルの半径範囲外で矩形の角と交差しない
@Test
def testCapsuleRectCornerMiss(): Unit \ Assert =
    Assert.assertEq(expected = false,
        CollisionShape2D.checkCapsuleRect(
            {x = 0.0, y = 0.0}, 1.0, 6.0, true,
            {x = 4.0, y = 6.0}, {x = 2.0, y = 2.0}))

// ========================================================================
// checkCapsuleCapsule
// ========================================================================

/// 平行な縦向きカプセル同士が重なっている
@Test
def testCapsuleCapsuleOverlapping(): Unit \ Assert =
    Assert.assertEq(expected = true,
        CollisionShape2D.checkCapsuleCapsule(
            {x = 0.0, y = 0.0}, 2.0, 10.0, true,
            {x = 3.0, y = 0.0}, 2.0, 10.0, true))

/// 平行な縦向きカプセル同士が離れている
@Test
def testCapsuleCapsuleNotOverlapping(): Unit \ Assert =
    Assert.assertEq(expected = false,
        CollisionShape2D.checkCapsuleCapsule(
            {x = 0.0, y = 0.0}, 2.0, 10.0, true,
            {x = 10.0, y = 0.0}, 2.0, 10.0, true))

/// 縦と横のカプセルが交差している
@Test
def testCapsuleCapsuleCross(): Unit \ Assert =
    Assert.assertEq(expected = true,
        CollisionShape2D.checkCapsuleCapsule(
            {x = 0.0, y = 0.0}, 1.0, 10.0, true,
            {x = 0.0, y = 0.0}, 1.0, 10.0, false))

/// 接触ぎりぎりで離れている（半径の和 = 距離）
@Test
def testCapsuleCapsuleTouching(): Unit \ Assert =
    Assert.assertEq(expected = false,
        CollisionShape2D.checkCapsuleCapsule(
            {x = 0.0, y = 0.0}, 2.0, 10.0, true,
            {x = 4.0, y = 0.0}, 2.0, 10.0, true))

// ========================================================================
// checkOverlap: カプセル組み合わせのディスパッチ
// ========================================================================

/// Capsule vs Circle のディスパッチ
@Test
def testCheckOverlapCapsuleCircle(): Unit \ Assert =
    let shapeA = CollisionShape2D.CapsuleShape2D({radius = 2.0, height = 10.0, vertical = true});
    let shapeB = CollisionShape2D.CircleShape2D({radius = 2.0});
    Assert.assertEq(expected = true,
        CollisionShape2D.checkOverlap({x = 0.0, y = 0.0}, shapeA, {x = 3.0, y = 0.0}, shapeB))

/// Circle vs Capsule のディスパッチ（逆順）
@Test
def testCheckOverlapCircleCapsule(): Unit \ Assert =
    let shapeA = CollisionShape2D.CircleShape2D({radius = 2.0});
    let shapeB = CollisionShape2D.CapsuleShape2D({radius = 2.0, height = 10.0, vertical = true});
    Assert.assertEq(expected = true,
        CollisionShape2D.checkOverlap({x = 3.0, y = 0.0}, shapeA, {x = 0.0, y = 0.0}, shapeB))

/// Capsule vs Rect のディスパッチ
@Test
def testCheckOverlapCapsuleRect(): Unit \ Assert =
    let shapeA = CollisionShape2D.CapsuleShape2D({radius = 2.0, height = 10.0, vertical = true});
    let shapeB = CollisionShape2D.RectShape2D({width = 4.0, height = 4.0});
    Assert.assertEq(expected = true,
        CollisionShape2D.checkOverlap({x = 0.0, y = 0.0}, shapeA, {x = 3.5, y = 0.0}, shapeB))

/// Capsule vs Capsule のディスパッチ
@Test
def testCheckOverlapCapsuleCapsule(): Unit \ Assert =
    let shapeA = CollisionShape2D.CapsuleShape2D({radius = 2.0, height = 10.0, vertical = true});
    let shapeB = CollisionShape2D.CapsuleShape2D({radius = 2.0, height = 10.0, vertical = true});
    Assert.assertEq(expected = true,
        CollisionShape2D.checkOverlap({x = 0.0, y = 0.0}, shapeA, {x = 3.0, y = 0.0}, shapeB))

// ========================================================================
// SlopeShape2D — 円・カプセルと坂の判定と MTV
// ========================================================================

/// MTV の成分を小数 4 桁へ丸める（斜辺法線は無理数成分を持つため）
def slopeTestRound4(x: Float64): Float64 = Float64.floor(x * 10000.0 + 0.5) / 10000.0

/// Option[Vec2] の MTV を丸めたタプルへ変換する
def mtvRound4(mtv: Option[Vec2.Vec2]): Option[(Float64, Float64)] =
    Option.map(v -> (slopeTestRound4(v#x), slopeTestRound4(v#y)), mtv)

/// 45° 坂（右登り）の斜辺に重なる円は checkOverlap で検出される
@Test
def testCheckOverlapCircleSlope(): Unit \ Assert =
    let circle = CollisionShape2D.CircleShape2D({radius = 8.0});
    let slopeShape = CollisionShape2D.SlopeShape2D({width = 32.0, height = 32.0, riseRight = true});
    let n = Vec2.normalized({x = -1.0, y = -1.0});
    Assert.assertEq(expected = true,
        CollisionShape2D.checkOverlap(Vec2.mul(n, 6.0), circle, {x = 0.0, y = 0.0}, slopeShape))

/// 45° 坂（右登り）の斜辺にめり込んだ円の MTV。
/// 斜辺中点 (0,0) の法線方向へ 6 の位置に半径 8 の円 → めり込み 2 を法線 (-1,-1)/√2 へ押し出す。
///
///        (C)
///       / |
///   ○  /  |     ○ = 円（斜辺の左上側）
///    (A)---(B)
///
@Test
def testCircleSlopeHypotenuseMtv(): Unit \ Assert =
    let n = Vec2.normalized({x = -1.0, y = -1.0});
    let mtv = CollisionShape2D.resolveCircleSlope(
        Vec2.mul(n, 6.0), 8.0, {x = 0.0, y = 0.0}, {x = 32.0, y = 32.0}, true);
    Assert.assertEq(expected = Some((-1.4142, -1.4142)), mtvRound4(mtv))

/// 坂から遠い円は重ならず MTV も無い
@Test
def testCircleSlopeFarApart(): Unit \ Assert =
    let circle = CollisionShape2D.CircleShape2D({radius = 2.0});
    let slopeShape = CollisionShape2D.SlopeShape2D({width = 32.0, height = 32.0, riseRight = true});
    let overlap = CollisionShape2D.checkOverlap({x = 100.0, y = 100.0}, circle, {x = 0.0, y = 0.0}, slopeShape);
    let mtv = CollisionShape2D.resolveOverlap({x = 100.0, y = 100.0}, circle, {x = 0.0, y = 0.0}, slopeShape);
    Assert.assertEq(expected = (false, None), (overlap, mtvRound4(mtv)))

/// 円が坂の垂直面（右登りの右側面 x=16）にめり込む → 真横 +x へ押し出す
@Test
def testCircleSlopeVerticalFaceMtv(): Unit \ Assert =
    let mtv = CollisionShape2D.resolveCircleSlope(
        {x = 22.0, y = 0.0}, 8.0, {x = 0.0, y = 0.0}, {x = 32.0, y = 32.0}, true);
    Assert.assertEq(expected = Some((2.0, 0.0)), mtvRound4(mtv))

/// 円が坂の底面（y=16）にめり込む → 真下 +y へ押し出す
@Test
def testCircleSlopeBottomFaceMtv(): Unit \ Assert =
    let mtv = CollisionShape2D.resolveCircleSlope(
        {x = 0.0, y = 22.0}, 8.0, {x = 0.0, y = 0.0}, {x = 32.0, y = 32.0}, true);
    Assert.assertEq(expected = Some((0.0, 2.0)), mtvRound4(mtv))

/// 左登り坂（riseRight=false）の斜辺 → 鏡像の法線 (+1,-1)/√2 へ押し出す
@Test
def testCircleSlopeRiseLeftMtv(): Unit \ Assert =
    let n = Vec2.normalized({x = 1.0, y = -1.0});
    let mtv = CollisionShape2D.resolveCircleSlope(
        Vec2.mul(n, 6.0), 8.0, {x = 0.0, y = 0.0}, {x = 32.0, y = 32.0}, false);
    Assert.assertEq(expected = Some((1.4142, -1.4142)), mtvRound4(mtv))

/// 円の中心が坂の内部 → 最も浅い辺（この配置では底面）へ、辺までの距離＋半径ぶん押し出す
@Test
def testCircleSlopeCenterInsideMtv(): Unit \ Assert =
    let mtv = CollisionShape2D.resolveCircleSlope(
        {x = 10.0, y = 12.0}, 2.0, {x = 0.0, y = 0.0}, {x = 32.0, y = 32.0}, true);
    Assert.assertEq(expected = Some((0.0, 6.0)), mtvRound4(mtv))

/// resolveOverlap: 坂が A 側のときは円側 MTV の符号反転になる
@Test
def testResolveSlopeCircleNegated(): Unit \ Assert =
    let n = Vec2.normalized({x = -1.0, y = -1.0});
    let slopeShape = CollisionShape2D.SlopeShape2D({width = 32.0, height = 32.0, riseRight = true});
    let circle = CollisionShape2D.CircleShape2D({radius = 8.0});
    let mtv = CollisionShape2D.resolveOverlap({x = 0.0, y = 0.0}, slopeShape, Vec2.mul(n, 6.0), circle);
    Assert.assertEq(expected = Some((1.4142, 1.4142)), mtvRound4(mtv))

/// 矩形と坂は MTV を返さない（静的地形同士は分離しない）
@Test
def testResolveRectSlopeReturnsNone(): Unit \ Assert =
    let rect = CollisionShape2D.RectShape2D({width = 8.0, height = 8.0});
    let slopeShape = CollisionShape2D.SlopeShape2D({width = 32.0, height = 32.0, riseRight = true});
    let mtv = CollisionShape2D.resolveOverlap({x = 10.0, y = 10.0}, rect, {x = 0.0, y = 0.0}, slopeShape);
    Assert.assertEq(expected = None, mtvRound4(mtv))

/// 坂同士の重なりは外接箱で近似判定する（MTV は返さない）
@Test
def testCheckOverlapSlopeSlope(): Unit \ Assert =
    let slopeShape = CollisionShape2D.SlopeShape2D({width = 32.0, height = 32.0, riseRight = true});
    let near = CollisionShape2D.checkOverlap({x = 0.0, y = 0.0}, slopeShape, {x = 30.0, y = 0.0}, slopeShape);
    let far = CollisionShape2D.checkOverlap({x = 0.0, y = 0.0}, slopeShape, {x = 100.0, y = 0.0}, slopeShape);
    let mtv = CollisionShape2D.resolveOverlap({x = 0.0, y = 0.0}, slopeShape, {x = 30.0, y = 0.0}, slopeShape);
    Assert.assertEq(expected = (true, false, None), (near, far, mtvRound4(mtv)))

/// checkOverlap: 坂を含むペアは引数の順序を入れ替えても同じ結果になる
@Test
def testCheckOverlapSlopeDispatchSymmetry(): Unit \ Assert =
    let slopeShape = CollisionShape2D.SlopeShape2D({width = 32.0, height = 32.0, riseRight = true});
    let circle = CollisionShape2D.CircleShape2D({radius = 8.0});
    let rect = CollisionShape2D.RectShape2D({width = 8.0, height = 8.0});
    let capsule = CollisionShape2D.CapsuleShape2D({radius = 2.0, height = 10.0, vertical = true});
    let slopePos = {x = 0.0, y = 0.0};
    let otherPos = {x = 14.0, y = 10.0};
    let forward = (CollisionShape2D.checkOverlap(otherPos, circle, slopePos, slopeShape),
                   CollisionShape2D.checkOverlap(otherPos, rect, slopePos, slopeShape),
                   CollisionShape2D.checkOverlap(otherPos, capsule, slopePos, slopeShape));
    let backward = (CollisionShape2D.checkOverlap(slopePos, slopeShape, otherPos, circle),
                    CollisionShape2D.checkOverlap(slopePos, slopeShape, otherPos, rect),
                    CollisionShape2D.checkOverlap(slopePos, slopeShape, otherPos, capsule));
    Assert.assertEq(expected = ((true, true, true), (true, true, true)), (forward, backward))

// ========================================================================
// カプセルの MTV
// ========================================================================

/// 縦カプセルが矩形の左辺にめり込む → 真横 -x へ 1 押し出す
@Test
def testCapsuleRectSideMtv(): Unit \ Assert =
    let mtv = CollisionShape2D.resolveCapsuleRect(
        {x = 0.0, y = 0.0}, 2.0, 10.0, true, {x = 5.0, y = 0.0}, {x = 8.0, y = 8.0});
    Assert.assertEq(expected = Some((-1.0, 0.0)), mtvRound4(mtv))

/// 縦カプセルと円 → 軸線分上の最近接点から円の反対向きへ押し出す
@Test
def testCapsuleCircleMtv(): Unit \ Assert =
    let mtv = CollisionShape2D.resolveCapsuleCircle(
        {x = 0.0, y = 0.0}, 2.0, 10.0, true, {x = 3.0, y = 0.0}, 2.0);
    Assert.assertEq(expected = Some((-1.0, 0.0)), mtvRound4(mtv))

/// 平行な縦カプセル同士 → 半径和 4 に対し軸間距離 3 → 不足 1 を -x へ押し出す
@Test
def testCapsuleCapsuleParallelMtv(): Unit \ Assert =
    let mtv = CollisionShape2D.resolveCapsuleCapsule(
        {x = 0.0, y = 0.0}, 2.0, 10.0, true, {x = 3.0, y = 0.0}, 2.0, 10.0, true);
    Assert.assertEq(expected = Some((-1.0, 0.0)), mtvRound4(mtv))

/// 縦カプセルの下端が 45° 坂の斜辺にめり込む → 斜辺法線 (-1,-1)/√2 へ押し出す。
/// 下端 (-2,-2) から斜辺までの距離は 2√2 → めり込み 4-2√2 ≈ 1.1716。
@Test
def testCapsuleSlopeHypotenuseMtv(): Unit \ Assert =
    let mtv = CollisionShape2D.resolveCapsuleSlope(
        {x = -2.0, y = -5.0}, 4.0, 14.0, true, {x = 0.0, y = 0.0}, {x = 32.0, y = 32.0}, true);
    Assert.assertEq(expected = Some((-0.8284, -0.8284)), mtvRound4(mtv))
