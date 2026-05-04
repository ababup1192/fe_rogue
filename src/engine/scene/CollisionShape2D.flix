/// 2D 衝突形状（Godot Shape2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_shape2d.html
///
/// 衝突判定に使う幾何形状。
/// Area2D の collisionShape フィールドに設定して使う。
///
///   CollisionShape2D
///     +-- RectShape2D: 軸平行の矩形（AABB）
///     +-- CircleShape2D: 円
///     +-- CapsuleShape2D: カプセル（両端が半円の矩形）
///
/// すべての判定関数は形状の **中心座標** を基準として受け取る。
pub enum CollisionShape2D {
    /// 軸平行の矩形
    case RectShape2D({width = Float64, height = Float64})
    /// 円
    case CircleShape2D({radius = Float64})
    /// カプセル（Godot CapsuleShape2D 準拠）
    /// radius: 半円の半径
    /// height: カプセル全体の高さ（両端の半円を含む）
    /// vertical: true なら縦長、false なら横長
    case CapsuleShape2D({radius = Float64, height = Float64, vertical = Bool})
}

mod CollisionShape2D {

    // ========================================================================
    // 汎用オーバーラップ判定
    // ========================================================================

    /// 2 つの形状が重なっているか判定する。
    /// posA / posB は各形状の中心座標。
    pub def checkOverlap(posA: Vec2.Vec2, shapeA: CollisionShape2D,
                          posB: Vec2.Vec2, shapeB: CollisionShape2D): Bool =
        match (shapeA, shapeB) {
            // Rect vs Rect
            case (CollisionShape2D.RectShape2D(ra), CollisionShape2D.RectShape2D(rb)) =>
                checkRectRect(posA, {x = ra#width, y = ra#height},
                              posB, {x = rb#width, y = rb#height})
            // Circle vs Circle
            case (CollisionShape2D.CircleShape2D(ca), CollisionShape2D.CircleShape2D(cb)) =>
                checkCircleCircle(posA, ca#radius, posB, cb#radius)
            // Circle vs Rect
            case (CollisionShape2D.CircleShape2D(ca), CollisionShape2D.RectShape2D(rb)) =>
                checkCircleRect(posA, ca#radius, posB, {x = rb#width, y = rb#height})
            // Rect vs Circle
            case (CollisionShape2D.RectShape2D(ra), CollisionShape2D.CircleShape2D(cb)) =>
                checkCircleRect(posB, cb#radius, posA, {x = ra#width, y = ra#height})
            // Capsule vs Circle
            case (CollisionShape2D.CapsuleShape2D(ca), CollisionShape2D.CircleShape2D(cb)) =>
                checkCapsuleCircle(posA, ca#radius, ca#height, ca#vertical, posB, cb#radius)
            // Circle vs Capsule
            case (CollisionShape2D.CircleShape2D(ca), CollisionShape2D.CapsuleShape2D(cb)) =>
                checkCapsuleCircle(posB, cb#radius, cb#height, cb#vertical, posA, ca#radius)
            // Capsule vs Rect
            case (CollisionShape2D.CapsuleShape2D(ca), CollisionShape2D.RectShape2D(rb)) =>
                checkCapsuleRect(posA, ca#radius, ca#height, ca#vertical,
                                 posB, {x = rb#width, y = rb#height})
            // Rect vs Capsule
            case (CollisionShape2D.RectShape2D(ra), CollisionShape2D.CapsuleShape2D(cb)) =>
                checkCapsuleRect(posB, cb#radius, cb#height, cb#vertical,
                                 posA, {x = ra#width, y = ra#height})
            // Capsule vs Capsule
            case (CollisionShape2D.CapsuleShape2D(ca), CollisionShape2D.CapsuleShape2D(cb)) =>
                checkCapsuleCapsule(posA, ca#radius, ca#height, ca#vertical,
                                    posB, cb#radius, cb#height, cb#vertical)
        }

    // ========================================================================
    // 個別形状ペアの判定
    // ========================================================================

    /// AABB 矩形同士の重なり判定。
    /// pos は矩形の中心、size は幅と高さ。
    ///
    ///   posA          posB
    ///    +--+          +--+
    ///    |  |   <-->   |  |
    ///    +--+          +--+
    ///
    pub def checkRectRect(posA: Vec2.Vec2, sizeA: Vec2.Vec2,
                           posB: Vec2.Vec2, sizeB: Vec2.Vec2): Bool =
        let halfA = Vec2.div(sizeA, 2.0);
        let halfB = Vec2.div(sizeB, 2.0);
        (posA#x + halfA#x > posB#x - halfB#x) and
        (posB#x + halfB#x > posA#x - halfA#x) and
        (posA#y + halfA#y > posB#y - halfB#y) and
        (posB#y + halfB#y > posA#y - halfA#y)

    /// 円同士の重なり判定。
    /// pos は円の中心。
    ///
    ///    (A)  <-->  (B)
    ///
    pub def checkCircleCircle(posA: Vec2.Vec2, radiusA: Float64,
                               posB: Vec2.Vec2, radiusB: Float64): Bool =
        let distSq = Vec2.distanceSquaredTo(posA, posB);
        let sumR = radiusA + radiusB;
        distSq < sumR * sumR

    /// 円と矩形の重なり判定。
    /// circlePos は円の中心、rectPos は矩形の中心、rectSize は幅と高さ。
    ///
    ///    (C)     +----+
    ///            |    |
    ///            +----+
    ///
    pub def checkCircleRect(circlePos: Vec2.Vec2, radius: Float64,
                             rectPos: Vec2.Vec2, rectSize: Vec2.Vec2): Bool =
        let halfW = rectSize#x / 2.0;
        let halfH = rectSize#y / 2.0;
        let dx = Float64.abs(circlePos#x - rectPos#x);
        let dy = Float64.abs(circlePos#y - rectPos#y);
        if (dx >= halfW + radius) false
        else if (dy >= halfH + radius) false
        else if (dx <= halfW or dy <= halfH) true
        else
            let cornerDx = dx - halfW;
            let cornerDy = dy - halfH;
            cornerDx * cornerDx + cornerDy * cornerDy < radius * radius

    // ========================================================================
    // カプセル形状のヘルパー
    // ========================================================================

    /// カプセルの軸線分の両端点を返す。
    /// カプセルの中心座標 pos から、半径を除いた軸方向の両端を計算する。
    ///
    ///   縦向き (vertical=true):
    ///       (A)        segA = pos + (0, -halfSeg)
    ///       | |
    ///       | |  pos
    ///       | |
    ///       (B)        segB = pos + (0, +halfSeg)
    ///
    ///   横向き (vertical=false):
    ///   (A)------(B)   segA = pos + (-halfSeg, 0)
    ///                  segB = pos + (+halfSeg, 0)
    ///
    pub def capsuleSegment(pos: Vec2.Vec2, radius: Float64, height: Float64,
                            vertical: Bool): (Vec2.Vec2, Vec2.Vec2) =
        let halfSeg = Float64.max(0.0, height / 2.0 - radius);
        if (vertical)
            ({x = pos#x, y = pos#y - halfSeg}, {x = pos#x, y = pos#y + halfSeg})
        else
            ({x = pos#x - halfSeg, y = pos#y}, {x = pos#x + halfSeg, y = pos#y})

    /// 点から線分への最短距離の二乗を返す。
    ///
    ///        * point
    ///       /|
    ///      / |
    ///   segA----segB
    ///
    pub def pointToSegmentDistSq(point: Vec2.Vec2,
                                  segA: Vec2.Vec2, segB: Vec2.Vec2): Float64 =
        let ab = Vec2.sub(segB, segA);
        let ap = Vec2.sub(point, segA);
        let abLenSq = Vec2.lengthSquared(ab);
        if (abLenSq < 0.000001)
            Vec2.distanceSquaredTo(point, segA)
        else
            let t = Float64.max(0.0, Float64.min(1.0, Vec2.dot(ap, ab) / abLenSq));
            let closest = Vec2.add(segA, Vec2.mul(ab, t));
            Vec2.distanceSquaredTo(point, closest)

    /// 二つの 2D 線分が交差しているか判定する。
    /// 交差の��積符号法を使用��る。
    def segmentsIntersect(a1: Vec2.Vec2, a2: Vec2.Vec2,
                           b1: Vec2.Vec2, b2: Vec2.Vec2): Bool =
        let d1 = Vec2.cross(Vec2.sub(b2, b1), Vec2.sub(a1, b1));
        let d2 = Vec2.cross(Vec2.sub(b2, b1), Vec2.sub(a2, b1));
        let d3 = Vec2.cross(Vec2.sub(a2, a1), Vec2.sub(b1, a1));
        let d4 = Vec2.cross(Vec2.sub(a2, a1), Vec2.sub(b2, a1));
        (d1 * d2 < 0.0) and (d3 * d4 < 0.0)

    /// 二つの線分間の最短距離の二乗を返す。
    /// 2D 線分が交差する場合は 0 を返す。
    /// それ以外��端点-線分距離の最小値を取る。
    pub def segmentToSegmentDistSq(a1: Vec2.Vec2, a2: Vec2.Vec2,
                                    b1: Vec2.Vec2, b2: Vec2.Vec2): Float64 =
        let ab = Vec2.sub(a2, a1);
        let cd = Vec2.sub(b2, b1);
        let abLenSq = Vec2.lengthSquared(ab);
        let cdLenSq = Vec2.lengthSquared(cd);
        // 両方とも点の場合
        if (abLenSq < 0.000001 and cdLenSq < 0.000001)
            Vec2.distanceSquaredTo(a1, b1)
        // 一方が点の場合
        else if (abLenSq < 0.000001)
            pointToSegmentDistSq(a1, b1, b2)
        else if (cdLenSq < 0.000001)
            pointToSegmentDistSq(b1, a1, a2)
        // 線分が交差している場合
        else if (segmentsIntersect(a1, a2, b1, b2))
            0.0
        else
            // 4 通りの端点-線分距離の最小値を取る
            let d1 = pointToSegmentDistSq(a1, b1, b2);
            let d2 = pointToSegmentDistSq(a2, b1, b2);
            let d3 = pointToSegmentDistSq(b1, a1, a2);
            let d4 = pointToSegmentDistSq(b2, a1, a2);
            Float64.min(Float64.min(d1, d2), Float64.min(d3, d4))

    // ========================================================================
    // カプセル形状の衝突判定
    // ========================================================================

    /// カプセルと円の重なり判定。
    /// カプセルの軸線分と円の中心の距離が、両者の半径の和より小さいかで判定する。
    ///
    ///   (cap)      (circle)
    ///    | |          O
    ///    | |
    ///
    pub def checkCapsuleCircle(capsulePos: Vec2.Vec2, capsuleRadius: Float64,
                                capsuleHeight: Float64, capsuleVertical: Bool,
                                circlePos: Vec2.Vec2, circleRadius: Float64): Bool =
        let (segA, segB) = capsuleSegment(capsulePos, capsuleRadius, capsuleHeight, capsuleVertical);
        let distSq = pointToSegmentDistSq(circlePos, segA, segB);
        let sumR = capsuleRadius + circleRadius;
        distSq < sumR * sumR

    /// カプセルと矩形の重なり判定。
    /// カプセルの軸線分を半径分太らせた領域と矩形の重なりを判定する。
    /// 矩形を半径分膨らませて（ミンコフスキー和）、軸線分との交差を判定する。
    ///
    ///   (cap)   +----+
    ///    | |    |    |
    ///    | |    +----+
    ///
    pub def checkCapsuleRect(capsulePos: Vec2.Vec2, capsuleRadius: Float64,
                              capsuleHeight: Float64, capsuleVertical: Bool,
                              rectPos: Vec2.Vec2, rectSize: Vec2.Vec2): Bool =
        let (segA, segB) = capsuleSegment(capsulePos, capsuleRadius, capsuleHeight, capsuleVertical);
        let halfW = rectSize#x / 2.0;
        let halfH = rectSize#y / 2.0;
        // 線分上の矩形中心への最近接点を求める
        let ab = Vec2.sub(segB, segA);
        let abLenSq = Vec2.lengthSquared(ab);
        let ap = Vec2.sub(rectPos, segA);
        let t = if (abLenSq < 0.000001) 0.0
                else Float64.max(0.0, Float64.min(1.0, Vec2.dot(ap, ab) / abLenSq));
        let closest = Vec2.add(segA, Vec2.mul(ab, t));
        let dx = Float64.abs(closest#x - rectPos#x);
        let dy = Float64.abs(closest#y - rectPos#y);
        // 膨張矩形の辺領域（十字部分）にあれば重なる
        if (dx >= halfW + capsuleRadius or dy >= halfH + capsuleRadius) false
        else if (dx <= halfW or dy <= halfH) true
        else
            let cornerDx = dx - halfW;
            let cornerDy = dy - halfH;
            cornerDx * cornerDx + cornerDy * cornerDy < capsuleRadius * capsuleRadius

    /// カプセル同士の重なり判定。
    /// 二つの軸線分の最短距離が、両者の半径の和より小さいかで判定する。
    ///
    ///   (A)     (B)
    ///    | |     | |
    ///    | |     | |
    ///
    pub def checkCapsuleCapsule(posA: Vec2.Vec2, radiusA: Float64,
                                 heightA: Float64, verticalA: Bool,
                                 posB: Vec2.Vec2, radiusB: Float64,
                                 heightB: Float64, verticalB: Bool): Bool =
        let (segA1, segA2) = capsuleSegment(posA, radiusA, heightA, verticalA);
        let (segB1, segB2) = capsuleSegment(posB, radiusB, heightB, verticalB);
        let distSq = segmentToSegmentDistSq(segA1, segA2, segB1, segB2);
        let sumR = radiusA + radiusB;
        distSq < sumR * sumR

    // ========================================================================
    // MTV（Minimum Translation Vector）計算 — 衝突分離用
    // ========================================================================
    //
    // resolveOverlap は「形状 A を形状 B から分離するために A に加算すべき変位」を返す。
    // 重なっていない場合は None。
    // PhysicsStep が静的衝突解決（push out）に使う。

    /// 2 つの形状の重なりを解消する変位ベクトルを返す。
    /// posA / posB は各形状の中心座標。返り値は posA に足すと A が B から離れる変位。
    /// Capsule を含むペアは未対応（None を返す）。
    pub def resolveOverlap(posA: Vec2.Vec2, shapeA: CollisionShape2D,
                            posB: Vec2.Vec2, shapeB: CollisionShape2D): Option[Vec2.Vec2] =
        match (shapeA, shapeB) {
            case (CollisionShape2D.RectShape2D(ra), CollisionShape2D.RectShape2D(rb)) =>
                resolveRectRect(posA, {x = ra#width, y = ra#height},
                                posB, {x = rb#width, y = rb#height})
            case (CollisionShape2D.CircleShape2D(ca), CollisionShape2D.CircleShape2D(cb)) =>
                resolveCircleCircle(posA, ca#radius, posB, cb#radius)
            case (CollisionShape2D.CircleShape2D(ca), CollisionShape2D.RectShape2D(rb)) =>
                resolveCircleRect(posA, ca#radius, posB, {x = rb#width, y = rb#height})
            case (CollisionShape2D.RectShape2D(ra), CollisionShape2D.CircleShape2D(cb)) =>
                // B (circle) を A (rect) から離す変位を求めて符号反転
                Option.map(v -> Vec2.neg(v),
                    resolveCircleRect(posB, cb#radius, posA, {x = ra#width, y = ra#height}))
            case _ => None  // Capsule 関連は未対応
        }

    /// AABB 矩形同士の MTV。重なる軸のうち侵入量が小さい方向に押し出す。
    pub def resolveRectRect(posA: Vec2.Vec2, sizeA: Vec2.Vec2,
                             posB: Vec2.Vec2, sizeB: Vec2.Vec2): Option[Vec2.Vec2] =
        let halfA = Vec2.div(sizeA, 2.0);
        let halfB = Vec2.div(sizeB, 2.0);
        let dx = posA#x - posB#x;
        let dy = posA#y - posB#y;
        let overlapX = halfA#x + halfB#x - Float64.abs(dx);
        let overlapY = halfA#y + halfB#y - Float64.abs(dy);
        if (overlapX <= 0.0 or overlapY <= 0.0) None
        else if (overlapX < overlapY)
            Some({x = if (dx >= 0.0) overlapX else (-1.0 * overlapX), y = 0.0})
        else
            Some({x = 0.0, y = if (dy >= 0.0) overlapY else (-1.0 * overlapY)})

    /// 円同士の MTV。中心間ベクトル方向に sumR - distance だけ押し出す。
    pub def resolveCircleCircle(posA: Vec2.Vec2, radiusA: Float64,
                                 posB: Vec2.Vec2, radiusB: Float64): Option[Vec2.Vec2] =
        let diff = Vec2.sub(posA, posB);
        let dist = Vec2.length(diff);
        let sumR = radiusA + radiusB;
        if (dist >= sumR) None
        else if (dist < 0.001)
            // 中心一致 — X 正方向に押し出す（任意）
            Some({x = sumR, y = 0.0})
        else
            let push = (sumR - dist) / dist;
            Some(Vec2.mul(diff, push))

    /// 円と矩形の MTV。
    /// circlePos / rectPos は各中心座標。circle を rect から離す変位を返す。
    pub def resolveCircleRect(circlePos: Vec2.Vec2, radius: Float64,
                               rectPos: Vec2.Vec2, rectSize: Vec2.Vec2): Option[Vec2.Vec2] =
        let halfW = rectSize#x / 2.0;
        let halfH = rectSize#y / 2.0;
        // 矩形上の最近接点
        let closestX = Float64.max(rectPos#x - halfW, Float64.min(circlePos#x, rectPos#x + halfW));
        let closestY = Float64.max(rectPos#y - halfH, Float64.min(circlePos#y, rectPos#y + halfH));
        let distX = circlePos#x - closestX;
        let distY = circlePos#y - closestY;
        let dist = Vec2.length({x = distX, y = distY});
        if (dist >= radius) None
        else if (dist < 0.001)
            // 円中心が矩形内部 — 浅い軸方向に押し出す
            let dx = circlePos#x - rectPos#x;
            let dy = circlePos#y - rectPos#y;
            let penX = halfW + radius - Float64.abs(dx);
            let penY = halfH + radius - Float64.abs(dy);
            if (penX < penY)
                Some({x = if (dx >= 0.0) penX else (-1.0 * penX), y = 0.0})
            else
                Some({x = 0.0, y = if (dy >= 0.0) penY else (-1.0 * penY)})
        else
            let push = (radius - dist) / dist;
            Some({x = distX * push, y = distY * push})
}
