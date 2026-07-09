/// world → screen のビュー変換。カメラ状態に依存しない純粋な投影数式だけを持つ。
/// カメラは getViewTransform でこの ViewTransform を作り、描画側が各ノードの
/// worldPos を applyToWorldPos に通して screen 座標へ移す。
mod Projection {

    /// ビュー変換: screenPos = worldPos * scale - offset。
    /// scale はズーム倍率（> 1 で寄り、< 1 で引き）、offset は screen 原点のずれ。
    pub type alias ViewTransform = { offset = Vec2.Vec2, scale = Vec2.Vec2 }

    /// world 座標を screen 座標に変換する: screen = world * scale - offset
    pub def applyToWorldPos(transform: ViewTransform, worldPos: Vec2.Vec2): Vec2.Vec2 =
        {x = worldPos#x * transform#scale#x - transform#offset#x,
         y = worldPos#y * transform#scale#y - transform#offset#y}
}
