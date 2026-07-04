// Viewport — 画面（矩形 bounds）に対する空間クエリ
//
// node 版の VisibleOnScreenNotifier2D ＋ ScreenNotifyHandler が担っていた「画面外に出た」検出を
// ECS の純粋クエリに置き換える共有部品。bounds の外（margin 付き）に出た entity の id を返すだけ。
// 「出た後どうするか（despawn 等）」はゲーム側の責務（Collision.detectCollisions と同じ分担）。

mod Viewport {

    /// 軸平行の矩形領域。画面なら {0, 0, width, height}。
    pub type alias Bounds = { minX = Float64, minY = Float64, maxX = Float64, maxY = Float64 }

    /// 幅・高さから原点基準の bounds を作る。
    pub def bounds(width: Float64, height: Float64): Bounds =
        { minX = 0.0, minY = 0.0, maxX = width, maxY = height }

    /// 点が bounds の外（各辺から margin 以上はみ出している）か。
    pub def isOutside(p: Vec2.Vec2, b: Bounds, margin: Float64): Bool =
        p#x < (b#minX - margin) or p#x > (b#maxX + margin) or
        p#y < (b#minY - margin) or p#y > (b#maxY + margin)

    /// position を持つ entity のうち、bounds の外（margin 付き）に出ているものの id 一覧。
    pub def offscreenEntities(positions: Map[EntityId, Vec2.Vec2], b: Bounds, margin: Float64): List[EntityId] =
        Map.foldLeftWithKey((acc, id, p) -> if (isOutside(p, b, margin)) id :: acc else acc, Nil, positions)
}
