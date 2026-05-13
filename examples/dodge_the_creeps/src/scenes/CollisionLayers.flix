/// Dodge the Creeps の衝突レイヤー定義（Godot collision_layer / collision_mask 用）。
///
/// 32 ビットの各ビットをカテゴリに割り当てる。各 Area2D / RigidBody2D に対して
///   - collisionLayer: 自分が属するレイヤー（or 演算で複数指定可）
///   - collisionMask:  自分が観測するレイヤー（or 演算で複数指定可）
/// を設定すると、AreaEvent.collectPairs と PhysicsStep.resolveOneRigid が
/// (mask & layer) != 0 のペアのみ判定対象とする。
///
/// このゲームでは Player と Mob の 2 種類だけ:
///   PlayerArea  : layer=player(), mask=mob()  （Player は Mob だけ観測）
///   Mob (Rigid) : layer=mob(),    mask=0      （Mob は誰も観測しない・誰にも押されない）
///
/// `CollisionObject2D.bits` は MSB 先頭のビット列を Int32 に変換するヘルパ:
///   bits(0 :: 1 :: Nil) = 0b01 = 1   (bit0)
///   bits(1 :: 0 :: Nil) = 0b10 = 2   (bit1)
mod CollisionLayers {
    /// プレイヤーを表すレイヤー (bit 0)
    pub def player(): Int32 = CollisionObject2D.bits(0 :: 1 :: Nil)

    /// モブを表すレイヤー (bit 1)
    pub def mob(): Int32 = CollisionObject2D.bits(1 :: 0 :: Nil)
}
