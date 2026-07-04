/// 物理ボディ共通の速度・移動インターフェースを定めるトレイト。
///
/// Node2D + CollisionObject2D を持つ全ての物理ボディの基底。
/// CharacterBody2D と RigidBody2D がこの trait を実装する。
///
///   CanvasItem
///     +-- Node2D
///           +-- CollisionObject2D
///                 +-- PhysicsBody2D
///                       +-- CharacterBody2D
///                       +-- RigidBody2D
///
/// 衝突応答はこのエンジンの対象外なので、共通の速度インターフェースと
/// 位置を進めるだけの簡易移動のみを提供する。
///
pub trait PhysicsBody2D[a] with CollisionObject2D[a] {

    /// 線形速度を取得する
    /// CharacterBody2D では velocity、RigidBody2D では linearVelocity に対応する。
    pub def getLinearVelocity(body: a): Vec2.Vec2

    /// 線形速度を設定する
    pub def setLinearVelocity(velocity: Vec2.Vec2, body: a): a

    /// 指定のモーションベクトルで移動する（簡易版）。
    ///
    /// 衝突応答は対象外のため位置更新のみ行う。
    /// 将来の衝突応答実装時にオーバーライドする想定。
    pub def moveAndCollide(motion: Vec2.Vec2, body: a): a =
        Node2D.setPosition(Vec2.add(Node2D.getPosition(body), motion), body)
}
