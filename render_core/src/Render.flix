// RenderType — 描画コマンドの型エイリアス
//
// shape は engine の GameEngine.Drawable / TileInstance / TileMapRenderCmd と一致。

mod RenderType {

    /// 角丸＋枠線スタイル (Godot StyleBoxFlat 相当)。`Drawable.style = Some(..)` のとき、
    /// 単色矩形 (texture="") を「塗り＋枠＋角丸＋AA」で 1 フラグメント描画する。
    /// cornerRadius/borderWidth は px。塗り色は Drawable#color/#alpha を使う。
    ///
    /// stripe* は塗り領域に重ねる 45° 斜線ハッチ（CSS の repeating-linear-gradient 相当）。
    /// `stripeWidth <= 0` または `stripeAlpha <= 0` でハッチ無効＝従来の塗りのみ。
    pub type alias BoxStyle = {
        cornerRadius = Float64,
        borderWidth  = Float64,
        borderColor  = Color,
        borderAlpha  = Float32,
        stripeColor  = Color,
        stripeAlpha  = Float32,
        stripeWidth  = Float64,
        stripePeriod = Float64
    }

    /// スプライト 1 つ分の描画コマンド (zIndex 順でソートして描画される)
    /// `style = Some(..)` かつ texture="" のとき角丸スタイル矩形として描く (それ以外は従来通り)。
    pub type alias Drawable = {
        texture = String,
        position = Vec2.Vec2,
        scale = Vec2.Vec2,
        rotation = Float64,
        color = Color,
        alpha = Float32,
        centered = Bool,
        uvOffset = Vec2.Vec2,
        uvScale = Vec2.Vec2,
        zIndex = Int32,
        style = Option[BoxStyle]
    }

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

    /// TileMapLayer の 1 タイル分の GPU インスタンスデータ
    pub type alias TileInstance = {
        px    = Vec2.Vec2,
        uvOff = Vec2.Vec2,
        uvSc  = Vec2.Vec2,
        alpha = Float32
    }

    /// Polygon2D の塗り潰し描画コマンド。vertices は既にスクリーン座標（px）に
    /// 変換済みの凸多角形の頂点列（GL_TRIANGLE_FAN で塗る）。
    pub type alias PolygonCmd = {
        vertices = List[Vec2.Vec2],
        color    = Color,
        alpha    = Float32,
        zIndex   = Int32
    }

    /// TileMapLayer のインスタンス描画コマンド (1 draw call で全タイル)
    pub type alias TileMapRenderCmd = {
        textureName = String,
        tileSize    = Float64,
        position    = Vec2.Vec2,
        tileScale   = Vec2.Vec2,
        color       = Color,
        zIndex      = Int32,
        tileVaoId   = Int32,
        tileCount   = Int32
    }

}
