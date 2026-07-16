// DrawCmd — 1 フレームぶんの描画命令の型。
//
// フロント（engine のシーングラフ）が組み立て、バックエンド（render_gl の GL 描画・
// engine_tools の SoftRaster）が受け取って絵にする。両者が同じ型を見るための共有語彙。
// engine（契約層）に置くことで、ゲーム・フロント・各バックエンドが 1 つの定義を共有する。

mod DrawCmd {

    /// ピクセルの重ね方（ブレンドモード）。
    /// Normal = ふつうの半透明合成。Add = 光が重なるように明るく足す（グロー・炎・魔法）。
    /// Multiply = 下の色に掛けて暗く沈める（影・暗幕。2D 光源の土台）。
    /// バックエンド（GL / SoftRaster）は同じ式で合成する:
    ///   Add      : out = min(1, dst + src×srcAlpha)
    ///   Multiply : out = dst×(1 − srcAlpha×(1 − src))  （srcAlpha=1 で dst×src・白は素通し・黒は黒）
    pub enum BlendMode with Eq, Order, ToString {
        case Normal
        case Add
        case Multiply
    }

    /// 角丸＋枠線スタイル。`Drawable.style = Some(..)` かつ texture="" のとき、
    /// 単色矩形を「塗り＋枠＋角丸＋AA」で 1 フラグメント描画する。長さはすべて px。
    ///
    /// stripe* は塗り領域に重ねる斜線ハッチ（CSS の repeating-linear-gradient 相当）。
    /// `stripeWidth <= 0` または `stripeAlpha <= 0` でハッチ無効＝塗りのみ。
    /// stripePeriod は縞の周期 px、stripeWidth は縞 1 本の幅 px。
    /// checker* は塗り領域に重ねる市松のタイル。`checkerCell <= 0` または
    /// `checkerAlpha <= 0` で無効。重なる順は 塗り → 縞 → 市松 → 枠。
    pub type alias BoxStyle = {
        cornerRadius = Float64,
        borderWidth  = Float64,
        borderColor  = Color,
        borderAlpha  = Float32,
        stripeColor  = Color,
        stripeAlpha  = Float32,
        stripeWidth  = Float64,
        stripePeriod = Float64,
        stripeDir    = Int32,   // 縞の向き: 0 = 斜め 45° / 1 = 横縞 / 2 = 縦縞
        checkerColor = Color,   // 市松タイルの色
        checkerAlpha = Float32, // 市松タイルの濃さ（0 で無効）
        checkerCell  = Float64  // 市松のセル一辺 px（0 で無効）
    }

    /// 何も飾らない素の BoxStyle（枠・縞・市松すべて無効）。色系は塗りと同じ base を入れておく。
    /// フィールドを足すときはここへ既定値を 1 つ足せば、組み立て側は上書きだけで済む。
    pub def defaultStyle(base: Color): BoxStyle =
        { cornerRadius = 0.0, borderWidth = 0.0, borderColor = base, borderAlpha = 0.0f32,
          stripeColor = base, stripeAlpha = 0.0f32, stripeWidth = 0.0, stripePeriod = 0.0,
          stripeDir = 0, checkerColor = base, checkerAlpha = 0.0f32, checkerCell = 0.0 }

    /// px の長さを持つフィールド（角丸・枠線幅・縞の幅と周期・市松のセル）を一括で factor 倍する。
    /// zoom やスケール適用が同じ表を見るための共通ヘルパ。
    pub def scalePx(factor: Float64, st: BoxStyle): BoxStyle =
        { cornerRadius = st#cornerRadius * factor,
          borderWidth  = st#borderWidth * factor,
          stripeWidth  = st#stripeWidth * factor,
          stripePeriod = st#stripePeriod * factor,
          checkerCell  = st#checkerCell * factor | st }

    /// clip 矩形（design px・スクリーン空間）を出力ピクセルの整数矩形 (x0, y0, x1, y1) へ写す
    /// （top-left 原点・floor 量子化）。GL の glScissor と SoftRaster の setClip が同じ画素集合を
    /// 見るための共通式 — y の反転（GL は左下原点）は GL 側だけが行う。
    /// 端のちらつきを避けたい呼び側は clip 矩形を整数 design px で作ること。
    pub def clipPixels(scale: {scaleX = Float64, scaleY = Float64}, clip: Rect2.Rect2): (Int32, Int32, Int32, Int32) =
        let f = v -> Float64.floor(v) |> Float64.tryToInt32 |> Option.getWithDefault(0);
        (f(clip#position#x * scale#scaleX),
         f(clip#position#y * scale#scaleY),
         f((clip#position#x + clip#size#x) * scale#scaleX),
         f((clip#position#y + clip#size#y) * scale#scaleY))

    /// スプライト 1 つ分の描画命令（zIndex 順にソートして描画される）。
    /// `style = Some(..)` かつ texture="" のとき角丸スタイル矩形として描く。
    /// `clip` はスクリーン空間（design px）の切り抜き窓 — None なら切らない。
    /// バックエンドは窓の外のピクセルを描かない（GL: scissor / SoftRaster: setClip）。
    /// `blend` はピクセルの重ね方（既定 Normal — 従来と同じ半透明合成）。
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
        style = Option[BoxStyle],
        clip = Option[Rect2.Rect2],
        blend = BlendMode
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
    /// blend は持たない = タイルは常に Normal（光り物・暗幕の実需要はエンティティ側。必要になったら拡張）。
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
    /// `clip` は Drawable と同じスクリーン空間の切り抜き窓（None なら切らない）。
    /// `blend` はピクセルの重ね方（既定 Normal — 従来と同じ半透明合成）。
    pub type alias PolygonRenderCmd = {
        vertices = List[Vec2.Vec2],
        color    = Color,
        alpha    = Float32,
        zIndex   = Int32,
        clip     = Option[Rect2.Rect2],
        blend    = BlendMode
    }

}
