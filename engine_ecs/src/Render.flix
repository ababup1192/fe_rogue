// Render — ノードでない render component と Drawable への extract 射影
//
// Bevy の bevy_sprite プラグイン相当。ゲームは RenderItem（高レベルデータ）を埋めるだけで、
// 低レベルの GameEngine.Drawable（11 フィールド）構築は lib のこのモジュールに閉じる。
// RenderItem は Sprite2D のフィールド設計を再利用するが、ノード機構（EngineNode/Scene/
// ライフサイクル/子）は持たない（＝scene-tree を戻さない）。位置は外（ECS positions / HUD pos）から渡す。
// Text は engine の public 純粋射影 Label2D.toDrawables を再利用。

mod Render {

    // ── render component（位置を持たない・ノードでない）──

    pub enum RenderItem {
        /// texture は handle 相当（String）。regionRect=None で全テクスチャ。UV は射影が計算。
        /// （`region` は Flix 予約語なので engine と同じ `regionRect`）
        case Sprite({ texture = String, tint = Color, alpha = Float32,
                      scale = Vec2.Vec2, rotation = Float64, centered = Bool,
                      flipH = Bool, flipV = Bool, regionRect = Option[Rect2.Rect2], zIndex = Int32 })
        case Text({ text = String, fontAtlas = FontAtlas, fontSize = Float64, zIndex = Int32 })
        case Box({ size = Vec2.Vec2, color = Color, alpha = Float32,
                   style = Option[GameEngine.BoxStyle], zIndex = Int32 })
    }

    // ── smart constructor（Drawable/BoxStyle をゲームから隠す）──

    def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// 全テクスチャ・等倍・中心原点のスプライト（最頻ケース）。
    pub def sprite(texture: String, zIndex: Int32, flipH: Bool, flipV: Bool): RenderItem =
        RenderItem.Sprite({ texture = texture, tint = white(), alpha = 1.0f32,
                            scale = {x = 1.0, y = 1.0}, rotation = 0.0, centered = true,
                            flipH = flipH, flipV = flipV, regionRect = None, zIndex = zIndex })

    pub def text(content: String, fontAtlas: FontAtlas, fontSize: Float64, zIndex: Int32): RenderItem =
        RenderItem.Text({ text = content, fontAtlas = fontAtlas, fontSize = fontSize, zIndex = zIndex })

    /// 単色塗りの矩形（左上原点・サイズ指定）。style は内部で solid に固定。
    pub def solidBox(size: Vec2.Vec2, color: Color, zIndex: Int32): RenderItem =
        RenderItem.Box({ size = size, color = color, alpha = 1.0f32,
                         style = Some(solidStyle()), zIndex = zIndex })

    def solidStyle(): GameEngine.BoxStyle =
        { cornerRadius = 0.0, borderWidth = 0.0, borderColor = white(), borderAlpha = 0.0f32,
          stripeColor = white(), stripeAlpha = 0.0f32, stripeWidth = 0.0, stripePeriod = 0.0 }

    // ── extract / 射影（lib が Drawable を1回だけ組む）──

    /// draw list 全体を Drawable 化（zIndex 順は render_core が stable sort する）。
    pub def draw(items: List[(Vec2.Vec2, RenderItem)]): List[GameEngine.Drawable] =
        List.flatMap(pair -> let (pos, item) = pair; toDrawables(item, pos), items)

    /// 1 アイテム → 複数 Drawable（ボタン等は呼び側で複数アイテムにする）。
    pub def toDrawables(item: RenderItem, pos: Vec2.Vec2): List[GameEngine.Drawable] =
        match item {
            case RenderItem.Sprite(s) =>
                spriteDrawable(s#texture, s#tint, s#alpha, s#scale, s#rotation,
                               s#centered, s#flipH, s#flipV, s#regionRect, s#zIndex, pos) :: Nil
            case RenderItem.Text(t) =>
                textDrawables(t#text, t#fontAtlas, t#fontSize, t#zIndex, pos)
            case RenderItem.Box(b) =>
                boxDrawable(b#size, b#color, b#alpha, b#style, b#zIndex, pos) :: Nil
        }

    // flip は base scale に符号を“乗算”（engine spriteToDrawable と同じ）。centered は素通し。
    // region=Some は textureSize(\Game) が要るので今回未対応＝loud に落とす（部分関数を残さない）。
    def spriteDrawable(texture: String, tint: Color, alpha: Float32, scale: Vec2.Vec2,
                       rotation: Float64, centered: Bool, flipH: Bool, flipV: Bool,
                       regionRect: Option[Rect2.Rect2], zIndex: Int32, pos: Vec2.Vec2): GameEngine.Drawable =
        match regionRect {
            case Some(_) => bug!("Render: region atlas not supported yet (pass regionRect=None)")
            case None    =>
                { texture  = texture,
                  position = pos,
                  scale    = {x = scale#x * flipSign(flipH), y = scale#y * flipSign(flipV)},
                  rotation = rotation,
                  color    = tint,
                  alpha    = alpha,
                  centered = centered,
                  uvOffset = {x = 0.0, y = 0.0},
                  uvScale  = {x = 1.0, y = 1.0},
                  zIndex   = zIndex,
                  style    = None }
        }

    def flipSign(b: Bool): Float64 = if (b) -1.0 else 1.0

    def textDrawables(content: String, fontAtlas: FontAtlas, fontSize: Float64,
                      zIndex: Int32, pos: Vec2.Vec2): List[GameEngine.Drawable] =
        // engine の public 純粋射影に委譲。zIndex は後置きで上書き（現 RenderWorld と同手法）。
        Label2D.toDrawables(Label2D.make(content, fontAtlas, fontSize), pos)
            |> List.map(d -> {zIndex = zIndex | d})

    def boxDrawable(size: Vec2.Vec2, color: Color, alpha: Float32,
                    style: Option[GameEngine.BoxStyle], zIndex: Int32,
                    pos: Vec2.Vec2): GameEngine.Drawable =
        // texture=""・centered=false・position=左上・scale=ピクセルサイズ・style=Some で単色塗り。
        { texture  = "",
          position = pos,
          scale    = size,
          rotation = 0.0,
          color    = color,
          alpha    = alpha,
          centered = false,
          uvOffset = {x = 0.0, y = 0.0},
          uvScale  = {x = 1.0, y = 1.0},
          zIndex   = zIndex,
          style    = style }
}
