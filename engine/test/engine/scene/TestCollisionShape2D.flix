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
