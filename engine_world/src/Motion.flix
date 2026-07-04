// Motion — 位置と速度を持つ物を、速度のぶんだけ位置へ進める（等速移動）。
// 「位置 += 速度 × 経過時間」を毎回書かずに済み、たくさんの物をまとめて一様に動かせる。
// 利用例: 弾をまっすぐ飛ばす / 敵を一定の向きへ流す / 落下物を下へ送る。
// 注意: 等速移動だけ。重力や衝突のはね返りは持たない（必要なら別の処理で）。

mod Motion {

    /// position を velocity で dt 秒積分する。両方持つ entity だけ動く。
    pub def integrate(positions: Map[EntityId, Vec2.Vec2],
                      velocities: Map[EntityId, Vec2.Vec2], dt: Float64): Map[EntityId, Vec2.Vec2] =
        Query.updateWith2(positions, velocities, (p, v) -> Vec2.add(p, Vec2.mul(v, dt)))
}
