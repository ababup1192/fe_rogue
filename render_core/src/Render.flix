// RenderType — 描画コマンドの型エイリアス
//
// shape は engine の GameEngine.Drawable / TileInstance / TileMapRenderCmd と一致。

mod RenderType {

    /// スプライト 1 つ分の描画コマンド (zIndex 順でソートして描画される)
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
        zIndex = Int32
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
