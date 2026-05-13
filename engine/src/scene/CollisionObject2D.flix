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

    /// 自身が属する衝突レイヤー（ビットマスク、Godot: collision_layer）。
    /// デフォルトは Godot と同じ 1i32（ビット 0 のみ）。
    pub def getCollisionLayer(_node: a): Int32 = 1i32

    /// 観測対象とする衝突レイヤー（ビットマスク、Godot: collision_mask）。
    /// デフォルトは Godot と同じ 1i32（ビット 0 のみ）。
    pub def getCollisionMask(_node: a): Int32 = 1i32
}

mod CollisionObject2D {
    /// ビット表現リストを Int32 ビットマスクにエンコードする。
    /// リストは MSB 先頭で読む（二進数を左から書いた順）。
    ///
    /// 例:
    ///   bits(1 :: 0 :: Nil)            = 2 (0b10,   bit1)
    ///   bits(1 :: 0 :: 1 :: Nil)       = 5 (0b101,  bit2 + bit0)
    ///   bits(0 :: 0 :: 0 :: 1 :: Nil)  = 1 (0b0001, bit0)
    ///
    /// `collisionLayer` / `collisionMask` を設定するときに、Godot エディタの
    /// ビット 32 個のチェックボックスのようにビット位置を視覚的に書きたいときに使う。
    /// 0 / 1 以外の値が混ざっていても bitwiseOr で吸収されるが意味のある使い方ではない。
    pub def bits(xs: List[Int32]): Int32 =
        List.foldLeft((acc, b) ->
            Int32.bitwiseOr(Int32.leftShift(acc, 1i32), b),
            0i32, xs)
}
