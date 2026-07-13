// DrawCmd — 1 フレームぶんの描画命令の型。
//
// フロント（engine のシーングラフ）が組み立て、バックエンド（render_gl の GL 描画・
// engine_tools の SoftRaster）が受け取って絵にする。両者が同じ型を見るための共有語彙。
// engine_core に置くことで、ゲーム・フロント・各バックエンドが 1 つの定義を共有する。

mod DrawCmd {

    /// 角丸＋枠線スタイル。`Drawable.style = Some(..)` かつ texture="" のとき、
    /// 単色矩形を「塗り＋枠＋角丸＋AA」で 1 フラグメント描画する。長さはすべて px。
    ///
    /// stripe* は塗り領域に重ねる 45° 斜線ハッチ（CSS の repeating-linear-gradient 相当）。
    /// `stripeWidth <= 0` または `stripeAlpha <= 0` でハッチ無効＝塗りのみ。
    /// stripePeriod は縞の周期 px、stripeWidth は縞 1 本の幅 px。
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

    /// スプライト 1 つ分の描画命令（zIndex 順にソートして描画される）。
    /// `style = Some(..)` かつ texture="" のとき角丸スタイル矩形として描く。
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

    /// タイルマップ 1 タイル分のインスタンスデータ。tilemap loader が組み立て、
    /// バックエンドの `initTileBuffer` が GPU へアップロードする素材。
    pub type alias TileInstance = {
        px    = Vec2.Vec2,
        uvOff = Vec2.Vec2,
        uvSc  = Vec2.Vec2,
        alpha = Float32
    }

    /// タイルマップのインスタンス描画命令（1 draw call で全タイル）。
    /// `tileScale` はカメラの zoom を反映するスクリーン倍率で、zoom 未指定時は (1, 1)。
    /// `tileVaoId` は `initTileBuffer` が返したバックエンドのハンドル（中身はバックエンドだけが知る）。
    pub type alias TileMapRenderCmd = {
        textureName = String,
        tileSize    = Float64,
        position    = Vec2.Vec2,
        tileScale   = Vec2.Vec2,
        color       = Color,
        zIndex      = Int32,
        tileVaoId   = GpuHandle.TileVao,
        tileCount   = Int32
    }

    /// 凸多角形の塗り潰し命令。vertices はスクリーン px に変換済みの頂点列を渡す。
    pub type alias PolygonRenderCmd = {
        vertices = List[Vec2.Vec2],
        color    = Color,
        alpha    = Float32,
        zIndex   = Int32
    }

}
