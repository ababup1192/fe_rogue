/// 衝突判定を持つ 2D オブジェクトの基底トレイト（Godot CollisionObject2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_collisionobject2d.html
///
/// Area2D など衝突形状を持つノードが実装する。
/// Node2D をスーパートレイトに持つため、空間上の位置情報も利用できる。
///
///   CanvasItem
///     +-- Node2D
///           +-- CollisionObject2D
///                 +-- Area2D
///
pub trait CollisionObject2D[a] with Node2D[a] {

    /// このノードの衝突形状を返す。
    /// None の場合は衝突判定に参加しない。
    pub def getCollisionShape(node: a): Option[CollisionShape2D]

    /// 他のエリアの侵入を検出するか（Godot: monitoring）
    pub def isMonitoring(node: a): Bool

    /// 他のエリアから検出されるか（Godot: monitorable）
    pub def isMonitorable(node: a): Bool

    /// 衝突判定の処理優先度（Godot: priority）
    /// 値が大きいほど優先的に処理される。デフォルトは 0。
    pub def getCollisionPriority(_node: a): Int32 = 0
}
