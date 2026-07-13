// RenderType — 描画コマンドの型エイリアス
//
// shape は engine の GameEngine.Drawable / TileInstance / TileMapRenderCmd と一致。

mod RenderType {

    /// 角丸＋枠線スタイル。共有の描画命令型 `DrawCmd.BoxStyle`。
    pub type alias BoxStyle = DrawCmd.BoxStyle

    /// スプライト 1 つ分の描画コマンド。共有型 `DrawCmd.Drawable`。
    pub type alias Drawable = DrawCmd.Drawable

    /// `RenderSprite.drawSprite` の描画パラメータ。同型(Vec2/Float)の位置引数が並ぶと
    /// 取り違えやすいため 1 レコードに束ねる。shader/vao は GL コンテキストとして別引数で渡す。
    ///   texture    : GL テクスチャ id (useTexture=false の単色矩形なら 0)
    ///   scale      : 表示矩形サイズ (px)。style 適用時は SDF の rectSize にもなる
    ///   style      : Some で角丸＋枠スタイル (単色矩形のみ有効)
    pub type alias DrawSpriteParams = {
        texture    = Int32,
        position   = Vec2.Vec2,
        scale      = Vec2.Vec2,
        color      = Color,
        alpha      = Float32,
        uvOffset   = Vec2.Vec2,
        uvScale    = Vec2.Vec2,
        rotation   = Float64,
        useTexture = Bool,
        style      = Option[BoxStyle],
        // SDF テキストとして描くか (useTexture かつ font_ アトラスのとき true)
        sdf        = Bool
    }

    /// TileLayer の 1 タイル分の GPU インスタンスデータ。共有型 `DrawCmd.TileInstance`。
    pub type alias TileInstance = DrawCmd.TileInstance

    /// Polygon の塗り潰し描画コマンド。共有型 `DrawCmd.PolygonRenderCmd`。
    pub type alias PolygonCmd = DrawCmd.PolygonRenderCmd

    /// TileLayer のインスタンス描画コマンド (1 draw call で全タイル)。共有型 `DrawCmd.TileMapRenderCmd`。
    pub type alias TileMapRenderCmd = DrawCmd.TileMapRenderCmd

}
