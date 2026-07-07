// Render — 「何をどう見せたいか」だけ書いた RenderItem を、描画部が食べられる形に変換する。
// スプライトもテキストも箱も円も多角形も、同じ (置き場所, RenderItem) の語彙で並べられる。
// 利用例: 弾や敵を絵として並べる / HUD の数字やラベルを出す / 破片や紙吹雪を polygon で撒く。
// 形は box / circle / polygon で作り、稀な属性（角丸・半透明・枠・縞）はパイプ修飾で重ねる。
// 注意: 置き場所（位置）は持たず呼び側が渡す。テキストの実寸計算は engine の純粋関数を使う。

mod Render {

    // ── render component（位置を持たない・ノードでない）──

    pub enum RenderItem {
        /// texture は handle 相当（String）。regionRect=None で全テクスチャ。UV は射影が計算。
        /// （`region` は Flix 予約語なので engine と同じ `regionRect`）
        case Sprite({ texture = String, tint = Color, alpha = Float32,
                      scale = Vec2.Vec2, rotation = Float64, centered = Bool,
                      flipH = Bool, flipV = Bool, regionRect = Option[Rect2.Rect2], zIndex = Int32 })
        case Text({ text = String, fontAtlas = FontAtlas, fontSize = Float64, tint = Color, zIndex = Int32 })
        case Box({ size = Vec2.Vec2, color = Color, alpha = Float32,
                   style = Option[GameEngine.BoxStyle], zIndex = Int32 })
        /// 単色の凸多角形。頂点は置き場所からの相対座標（draw が置き場所を全頂点に加算する）。
        case Poly({ vertices = List[Vec2.Vec2], color = Color, alpha = Float32, zIndex = Int32 })
    }

    /// 置き場所つきの描画物。View はこの列を組み、draw が描画命令へ変換する。
    pub type alias Placed = (Vec2.Vec2, RenderItem)

    // ── smart constructor（Drawable/BoxStyle をゲームから隠す）──

    def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// 全テクスチャ・等倍・中心原点のスプライト（最頻ケース）。
    pub def sprite(texture: String, zIndex: Int32, flipH: Bool, flipV: Bool): RenderItem =
        RenderItem.Sprite({ texture = texture, tint = white(), alpha = 1.0f32,
                            scale = {x = 1.0, y = 1.0}, rotation = 0.0, centered = true,
                            flipH = flipH, flipV = flipV, regionRect = None, zIndex = zIndex })

    pub def text(content: String, fontAtlas: FontAtlas, fontSize: Float64, zIndex: Int32): RenderItem =
        RenderItem.Text({ text = content, fontAtlas = fontAtlas, fontSize = fontSize, tint = white(), zIndex = zIndex })

    /// B0b: 着色テキスト（Label2D.setModulate を適用）。menu の disabled グレー / cursor 色 / ヘッダ accent 等に必要。
    pub def textTinted(content: String, fontAtlas: FontAtlas, fontSize: Float64, tint: Color, zIndex: Int32): RenderItem =
        RenderItem.Text({ text = content, fontAtlas = fontAtlas, fontSize = fontSize, tint = tint, zIndex = zIndex })

    /// 単色塗りの矩形（左上原点・サイズ指定）。
    pub def box(size: Vec2.Vec2, color: Color, zIndex: Int32): RenderItem =
        RenderItem.Box({ size = size, color = color, alpha = 1.0f32,
                         style = Some(solidStyle()), zIndex = zIndex })

    /// box の別名（左上原点・サイズ指定の単色矩形）。
    pub def solidBox(size: Vec2.Vec2, color: Color, zIndex: Int32): RenderItem =
        box(size, color, zIndex)

    /// 単色塗りの円（直径 radius×2 の全角丸 Box）。置き場所は外接正方形の左上。
    pub def circle(radius: Float64, color: Color, zIndex: Int32): RenderItem =
        box({ x = radius * 2.0, y = radius * 2.0 }, color, zIndex) |> rounded(radius)

    /// 単色塗りの多角形。頂点は置き場所からの相対座標で渡す（絶対座標で組みたいときは
    /// 置き場所を Vec2.zero() にする）。
    pub def polygon(vertices: List[Vec2.Vec2], color: Color, zIndex: Int32): RenderItem =
        RenderItem.Poly({ vertices = vertices, color = color, alpha = 1.0f32, zIndex = zIndex })

    def solidStyle(): GameEngine.BoxStyle =
        { cornerRadius = 0.0, borderWidth = 0.0, borderColor = white(), borderAlpha = 0.0f32,
          stripeColor = white(), stripeAlpha = 0.0f32, stripeWidth = 0.0, stripePeriod = 0.0 }

    // ── 修飾（稀な属性はパイプで重ねる。効かない種類の item は素通し）──

    /// 角を丸める（Box に効く）。
    pub def rounded(radius: Float64, item: RenderItem): RenderItem =
        match item {
            case RenderItem.Box(b) =>
                RenderItem.Box({ style = Some({ cornerRadius = radius | styleOf(b#style) }) | b })
            case other => other
        }

    /// 半透明にする（Sprite / Box / Poly に効く。Text は tint が濃度を兼ねる）。
    pub def fade(alpha: Float32, item: RenderItem): RenderItem =
        match item {
            case RenderItem.Sprite(s) => RenderItem.Sprite({ alpha = alpha | s })
            case RenderItem.Box(b)    => RenderItem.Box({ alpha = alpha | b })
            case RenderItem.Poly(p)   => RenderItem.Poly({ alpha = alpha | p })
            case other                => other
        }

    /// 枠線を付ける（Box に効く）。
    pub def outline(color: Color, width: Float64, item: RenderItem): RenderItem =
        match item {
            case RenderItem.Box(b) =>
                RenderItem.Box({ style = Some({ borderColor = color, borderWidth = width,
                                                borderAlpha = 1.0f32 | styleOf(b#style) }) | b })
            case other => other
        }

    /// 縞模様を敷く（Box に効く）。
    pub def striped(stripe: { color = Color, alpha = Float32, width = Float64, period = Float64 },
                    item: RenderItem): RenderItem =
        match item {
            case RenderItem.Box(b) =>
                RenderItem.Box({ style = Some({ stripeColor = stripe#color, stripeAlpha = stripe#alpha,
                                                stripeWidth = stripe#width, stripePeriod = stripe#period
                                                | styleOf(b#style) }) | b })
            case other => other
        }

    /// 修飾の土台になる style（無ければ solid）。
    def styleOf(style: Option[GameEngine.BoxStyle]): GameEngine.BoxStyle =
        Option.getWithDefault(solidStyle(), style)

    // ── extract / 射影（lib が Drawable を1回だけ組む）──

    /// draw list 全体を描画命令へ（zIndex 順は render_core が stable sort する）。
    /// Sprite / Text / Box は Drawable、Poly は置き場所を頂点に織り込んだ PolygonRenderCmd になる —
    /// 呼び側は 1 本のリストを組むだけで、2 系統への振り分けはここで終わる。
    pub def draw(items: List[Placed]): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let drawables = items |> List.flatMap(pair -> {
            let (pos, item) = pair;
            match item {
                case RenderItem.Poly(_) => Nil
                case other              => toDrawables(other, pos)
            }
        });
        let polygons = items |> List.filterMap(pair -> {
            let (pos, item) = pair;
            match item {
                case RenderItem.Poly(p) => Some(polyCmd(pos, p))
                case _                  => None
            }
        });
        (drawables, polygons)

    /// Poly を置き場所 pos の描画命令へ（全頂点に pos を加算）。
    def polyCmd(pos: Vec2.Vec2,
                p: { vertices = List[Vec2.Vec2], color = Color, alpha = Float32, zIndex = Int32 }): GameEngine.PolygonRenderCmd =
        { vertices = List.map(v -> Vec2.add(v, pos), p#vertices),
          color = p#color, alpha = p#alpha, zIndex = p#zIndex }

    /// World 由来 Drawable 群に camera のズーム倍率を適用する（位置は `Camera2D.applyToWorldPos` で
    /// screenPos を出した後の共通後処理）。render-from-World の各オーバーレイ（ユニット / 背景 / 範囲表示 /
    /// フォグ等）が共有する camera 適用 spine。Drawable の scale は sprite の拡大率・box の px サイズを表し、
    /// どちらも zoom で乗算するのが正しい camera 適用。
    pub def applyCameraScale(transform: Camera2D.ViewTransform,
                             ds: List[GameEngine.Drawable]): List[GameEngine.Drawable] =
        List.map(d -> {scale = {x = d#scale#x * transform#scale#x, y = d#scale#y * transform#scale#y} | d}, ds)

    /// 1 アイテム → 複数 Drawable（ボタン等は呼び側で複数アイテムにする）。
    pub def toDrawables(item: RenderItem, pos: Vec2.Vec2): List[GameEngine.Drawable] =
        match item {
            case RenderItem.Sprite(s) =>
                spriteDrawable(s#texture, s#tint, s#alpha, s#scale, s#rotation,
                               s#centered, s#flipH, s#flipV, s#regionRect, s#zIndex, pos) :: Nil
            case RenderItem.Text(t) =>
                textDrawables(t#text, t#fontAtlas, t#fontSize, t#tint, t#zIndex, pos)
            case RenderItem.Box(b) =>
                boxDrawable(b#size, b#color, b#alpha, b#style, b#zIndex, pos) :: Nil
            case RenderItem.Poly(_) =>
                bug!("Render.toDrawables: Poly は Drawable にならない（draw が PolygonRenderCmd へ振り分ける）")
        }

    /// B0b: region atlas 対応の射影。textureSize を引いて UV を計算する
    /// （Sprite2D.computeUv 相当の正規化: uvOffset = regionPos/texSize, uvScale = regionSize/texSize）。
    /// 非 region スプライト・text・box は pure 経路と同一。fe_rogue 等の atlas 主体ゲームの render-from-World に必要。
    /// テクスチャ寸法の引き方は `textureInfoOf` で注入する。ゲーム実行時は Game registry 版を渡し、
    /// 画面なしのテストやプレビューでは `_ -> None` などの純粋関数を渡せる（region を使わなければ結果は同じ）。
    pub def drawAtlasWith(textureInfoOf: String -> Option[GameEngine.TextureInfo] \ ef,
                          items: List[Placed]): List[GameEngine.Drawable] \ ef =
        List.flatMap(pair -> let (pos, item) = pair; toDrawablesAtlas(textureInfoOf, item, pos), items)

    /// `drawAtlasWith` の Game registry 版（`GameEngine.Game.getTextureInfo` で寸法を引く）。
    /// region スプライトを含む本番描画の既定口。
    pub def drawAtlas(items: List[Placed]): List[GameEngine.Drawable] \ GameEngine.Game =
        drawAtlasWith(name -> GameEngine.Game.getTextureInfo(name), items)

    def toDrawablesAtlas(textureInfoOf: String -> Option[GameEngine.TextureInfo] \ ef,
                         item: RenderItem, pos: Vec2.Vec2): List[GameEngine.Drawable] \ ef =
        match item {
            case RenderItem.Sprite(s) =>
                let (uvOff, uvScl) = match s#regionRect {
                    case None       => ({x = 0.0, y = 0.0}, {x = 1.0, y = 1.0})
                    case Some(rect) => match textureInfoOf(s#texture) {
                        case Some(ti) => ({x = rect#position#x / ti#width, y = rect#position#y / ti#height},
                                          {x = rect#size#x / ti#width, y = rect#size#y / ti#height})
                        case None     => ({x = 0.0, y = 0.0}, {x = 1.0, y = 1.0})
                    }
                };
                ({ texture = s#texture, position = pos,
                   scale = {x = s#scale#x * flipSign(s#flipH), y = s#scale#y * flipSign(s#flipV)},
                   rotation = s#rotation, color = s#tint, alpha = s#alpha, centered = s#centered,
                   uvOffset = uvOff, uvScale = uvScl, zIndex = s#zIndex, style = None }: GameEngine.Drawable) :: Nil
            case other => toDrawables(other, pos)
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
                      tint: Color, zIndex: Int32, pos: Vec2.Vec2): List[GameEngine.Drawable] =
        // engine の public 純粋射影に委譲。B0b: Drawable の color を tint で上書き＝文字色
        // （SDF 描画では color が modulate＝文字色。ItemList の per-item 色相当）。
        Label2D.toDrawables(Label2D.make(content, fontAtlas, fontSize), pos)
            |> List.map(d -> {color = tint, zIndex = zIndex | d})

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
