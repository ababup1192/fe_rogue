/// 物理ボディの共通インターフェース（Godot PhysicsBody2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_physicsbody2d.html
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
/// Godot の PhysicsBody2D は move_and_collide / test_move が主要メソッドだが、
/// 衝突応答は本エンジンのスコープ外のため、
/// 共通の速度インターフェースと簡易移動のみ提供する。
///
pub trait PhysicsBody2D[a] with CollisionObject2D[a] {

    /// 線形速度を取得する
    /// CharacterBody2D では velocity、RigidBody2D では linearVelocity に対応する。
    pub def getLinearVelocity(body: a): Vec2.Vec2

    /// 線形速度を設定する
    pub def setLinearVelocity(velocity: Vec2.Vec2, body: a): a

    /// 指定のモーションベクトルで移動する（Godot move_and_collide 簡易版）
    ///
    /// Godot では衝突情報（KinematicCollision2D）を返すが、
    /// 衝突応答は本エンジンのスコープ外のため、位置更新のみ行う。
    /// 将来の衝突応答実装時にオーバーライドする想定。
    pub def moveAndCollide(motion: Vec2.Vec2, body: a): a =
        Node2D.setPosition(Vec2.add(Node2D.getPosition(body), motion), body)
}
