/// 2D レイキャスト（線分衝突クエリ）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_raycast2d.html
///
/// Godot RayCast2D 準拠の線分衝突クエリを「いつでも呼べる関数群」として提供する。
/// ノード型ではなくユーティリティモジュール構成（Scene にツリーとして登録する必要なし）。
///
/// グリッドベース移動の事前チェック等で、Player ノードが TileMapLayer 等の衝突源を
/// 直接参照することなく、エンジンの抽象クエリ経由で衝突判定できるようにする。
mod RayCast2D {

    /// origin から target までの線分が静的衝突体（StaticBody2D / TileMapLayer の壁）と
    /// 交差するかを判定する。シーン全体の衝突体に対して走査する。
    pub def isColliding(origin: Vec2.Vec2, target: Vec2.Vec2,
                          scene: Scene[s]): Bool =
        let statics = PhysicsStep.collectStaticColliders(scene);
        List.exists(match (_, sPos, sShape) ->
            segmentIntersectsShape(origin, target, sPos, sShape),
            statics)

    /// 線分が形状と交差するかを形状種別ごとに判定する
    def segmentIntersectsShape(p1: Vec2.Vec2, p2: Vec2.Vec2,
                                shapePos: Vec2.Vec2, shape: CollisionShape2D): Bool =
        match shape {
            case CollisionShape2D.RectShape2D(r) =>
                segmentIntersectsAABB(p1, p2, shapePos, r#width, r#height)
            case CollisionShape2D.CircleShape2D(r) =>
                let distSq = CollisionShape2D.pointToSegmentDistSq(shapePos, p1, p2);
                distSq <= r#radius * r#radius
            case CollisionShape2D.CapsuleShape2D(_) =>
                false
        }

    /// 線分 p1→p2 と軸平行矩形（中心 center、サイズ w×h）の交差判定（Slab method）
    def segmentIntersectsAABB(p1: Vec2.Vec2, p2: Vec2.Vec2,
                                center: Vec2.Vec2, w: Float64, h: Float64): Bool =
        let halfW = w / 2.0;
        let halfH = h / 2.0;
        let minX = center#x - halfW;
        let maxX = center#x + halfW;
        let minY = center#y - halfH;
        let maxY = center#y + halfH;
        let dx = p2#x - p1#x;
        let dy = p2#y - p1#y;
        let (tMinX, tMaxX) =
            if (Float64.abs(dx) < 1.0e-9)
                if (p1#x < minX or p1#x > maxX) (1.0, -1.0)
                else (-1.0e18, 1.0e18)
            else {
                let t1 = (minX - p1#x) / dx;
                let t2 = (maxX - p1#x) / dx;
                (Float64.min(t1, t2), Float64.max(t1, t2))
            };
        let (tMinY, tMaxY) =
            if (Float64.abs(dy) < 1.0e-9)
                if (p1#y < minY or p1#y > maxY) (1.0, -1.0)
                else (-1.0e18, 1.0e18)
            else {
                let t1 = (minY - p1#y) / dy;
                let t2 = (maxY - p1#y) / dy;
                (Float64.min(t1, t2), Float64.max(t1, t2))
            };
        let tEnter = Float64.max(tMinX, tMinY);
        let tExit  = Float64.min(tMaxX, tMaxY);
        // 線分上 (0..1) で衝突区間が存在すれば true
        tEnter <= tExit and tExit >= 0.0 and tEnter <= 1.0
}
