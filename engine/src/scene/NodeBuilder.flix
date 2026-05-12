/// ノード構築・更新のユーティリティモジュール
///
/// trait の出所（CanvasItem / Node2D）を意識せずにノードを構築できる。
/// 型安全性は trait 制約で担保される。
///
///   use NodeBuilder.{position, scale, show}
///
///   Sprite2D.make("res://art/player.png", pos, s)
///       |> position({x = 100.0f32, y = 200.0f32})
///       |> scale({x = 2.0f32, y = 2.0f32})
///       |> show
///
mod NodeBuilder {

    // ── CanvasItem 系 ──

    /// 表示する
    pub def show(node: n): n with CanvasItem[n] =
        CanvasItem.show(node)

    /// 非表示にする
    pub def hide(node: n): n with CanvasItem[n] =
        CanvasItem.hide(node)

    /// 表示フラグを設定する
    pub def visible(v: Bool, node: n): n with CanvasItem[n] =
        CanvasItem.setVisible(v, node)

    /// 描画順を設定する
    pub def zIndex(z: Int32, node: n): n with CanvasItem[n] =
        CanvasItem.setZIndex(z, node)

    /// 色変調を設定する
    pub def modulate(color: Color, node: n): n with CanvasItem[n] =
        CanvasItem.setModulate(color, node)

    // ── Node2D 系 ──

    /// 位置を設定する
    pub def position(pos: Vec2.Vec2, node: n): n with Node2D[n] =
        Node2D.setPosition(pos, node)

    /// 回転（ラジアン）を設定する
    pub def rotation(r: Float64, node: n): n with Node2D[n] =
        Node2D.setRotation(r, node)

    /// スケールを設定する
    pub def scale(s: Vec2.Vec2, node: n): n with Node2D[n] =
        Node2D.setScale(s, node)

    /// スキュー（ラジアン）を設定する
    pub def skew(s: Float64, node: n): n with Node2D[n] =
        Node2D.setSkew(s, node)

    /// オフセット分だけ移動する
    pub def translate(offset: Vec2.Vec2, node: n): n with Node2D[n] =
        Node2D.translate(offset, node)

    /// 現在の回転に加算する
    pub def rotate(radians: Float64, node: n): n with Node2D[n] =
        Node2D.rotate(radians, node)

    /// 現在のスケールにベクトルを乗算する
    pub def applyScale(ratio: Vec2.Vec2, node: n): n with Node2D[n] =
        Node2D.applyScale(ratio, node)

    /// 指定した点の方を向く
    pub def lookAt(point: Vec2.Vec2, node: n): n with Node2D[n] =
        Node2D.lookAt(point, node)
}
