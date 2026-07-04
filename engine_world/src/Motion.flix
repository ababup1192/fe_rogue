// Motion — 位置の速度積分（node 版の RigidBody2D 物理積分の最小版）
//
// position と velocity を両方持つ entity の位置を p += v*dt で進める純粋関数。
// node 版では engine の PhysicsStep が担っていた等速移動を、共有部品として ECS に寄せる。
// 重力・衝突応答は持たない（必要なら別 system）。Query.updateWith2 の薄いラッパで意図を名付ける。

mod Motion {

    /// position を velocity で dt 秒積分する。両方持つ entity だけ動く。
    pub def integrate(positions: Map[EntityId, Vec2.Vec2],
                      velocities: Map[EntityId, Vec2.Vec2], dt: Float64): Map[EntityId, Vec2.Vec2] =
        Query.updateWith2(positions, velocities, (p, v) -> Vec2.add(p, Vec2.mul(v, dt)))
}
