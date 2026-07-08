// Color 型は engine_core/src/Color.flix にある。Visual はその `Color` を構造的に使う。

/// 描画の見た目（色変調・可視性・重なり順）をまとめた値部品。
/// 描画型はこれを埋め込んで見た目の属性を共有するので、型ごとに同じフィールドを書かずに済む。
/// 利用例: ノードを一時的に非表示にする / 前面へ出す / 色を掛ける。
///
/// modulate … 色変調（{r, g, b} の乗算）
/// visible  … 表示フラグ
/// zIndex   … 重なり順（大きいほど手前）
pub type alias Visual = {
    modulate = Color,
    visible = Bool,
    zIndex = Int32
}

mod Visual {

    /// 既定の見た目（白で色変調なし・表示・重なり順 0）。
    pub def default(): Visual =
        { modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32}, visible = true, zIndex = 0 }

    /// 色変調を取得する
    pub def getModulate(v: Visual): Color = v#modulate

    /// 色変調を設定する
    pub def setModulate(modulate: Color, v: Visual): Visual =
        { modulate = modulate | v }

    /// 可視性を取得する
    pub def getVisible(v: Visual): Bool = v#visible

    /// 可視性を設定する
    pub def setVisible(visible: Bool, v: Visual): Visual =
        { visible = visible | v }

    /// 重なり順を取得する
    pub def getZIndex(v: Visual): Int32 = v#zIndex

    /// 重なり順を設定する
    pub def setZIndex(zIndex: Int32, v: Visual): Visual =
        { zIndex = zIndex | v }
}
