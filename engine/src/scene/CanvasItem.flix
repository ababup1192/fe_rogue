// Color 型は engine_core/src/Color.flix に移動済み。
// CanvasItem は engine_core の `Color` を構造的に使う。

pub trait CanvasItem[a] {
    // 可視性
    pub def isVisible(node: a): Bool
    pub def setVisible(v: Bool, node: a): a

    // 重なり順
    pub def getZIndex(node: a): Int32
    pub def setZIndex(z: Int32, node: a): a

    // 描画色（乗算）
    pub def getModulate(node: a): Color
    pub def setModulate(color: Color, node: a): a

    // ビューポート

    /// 所属する Viewport の矩形を返す。
    /// 現在は常にルート Viewport（デザイン解像度）を返す。
    /// SubViewport 導入時はエフェクトハンドラのスコープで切り替わる。
    pub def getViewportRect(_node: a): Rect2.Rect2 \ GameEngine.Game =
        GameEngine.Game.getViewportRect()

    // 自身のみの描画色（子には伝播しない）
    pub def getSelfModulate(_node: a): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
    pub def setSelfModulate(_color: Color, node: a): a = node

    // Y-sort
    /// true なら自身の直接の子を global_position.y 昇順で描画する。
    /// 子の中で y_sort_enabled = true のものは独自の y-sort コンテキストを開く。
    /// z_index バケットが一次キー、Y は二次キー（Scene.toDrawables の安定ソートで保証）
    pub def isYSortEnabled(_node: a): Bool = false
    pub def setYSortEnabled(_v: Bool, node: a): a = node

    // デフォルト実装
    pub def show(node: a): a = CanvasItem.setVisible(true, node)
    pub def hide(node: a): a = CanvasItem.setVisible(false, node)
}