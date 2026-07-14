// Render — 「何をどう見せたいか」だけ書いた Item を、描画部が食べられる形に変換する。
// スプライトもテキストも箱も円も多角形も、同じ { at = 置き場所, item = Item } の語彙で並べられる。
// 利用例: 弾や敵を絵として並べる / HUD の数字やラベルを出す / 破片や紙吹雪を polygon で撒く。
// 形は box / circle / polygon で作り、稀な属性（角丸・半透明・枠・縞）はパイプ修飾で重ねる。
// 注意: 置き場所（位置）は持たず呼び側が渡す。テキストの実寸計算は engine の純粋関数を使う。

mod Render {

    // ── render component（位置を持たない・ノードでない）──

    pub enum Item {
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
    pub type alias PlacedItem = { at = Vec2.Vec2, item = Item }

    // ── smart constructor（Drawable/BoxStyle をゲームから隠す）──

    def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// 全テクスチャ・等倍・中心原点のスプライト（最頻ケース）。反転が要るときは spriteFlipped。
    pub def sprite(texture: String, zIndex: Int32): Item =
        Item.Sprite({ texture = texture, tint = white(), alpha = 1.0f32,
                            scale = {x = 1.0, y = 1.0}, rotation = 0.0, centered = true,
                            flipH = false, flipV = false, regionRect = None, zIndex = zIndex })

    /// 反転付きスプライト。同型の Bool 2 つは取り違えやすいので名前で渡す。
    pub def spriteFlipped(texture: String, zIndex: Int32,
                          flip: { flipH = Bool, flipV = Bool }): Item =
        Item.Sprite({ texture = texture, tint = white(), alpha = 1.0f32,
                            scale = {x = 1.0, y = 1.0}, rotation = 0.0, centered = true,
                            flipH = flip#flipH, flipV = flip#flipV, regionRect = None, zIndex = zIndex })

    pub def text(content: String, fontAtlas: FontAtlas, fontSize: Float64, zIndex: Int32): Item =
        Item.Text({ text = content, fontAtlas = fontAtlas, fontSize = fontSize, tint = white(), zIndex = zIndex })

    /// B0b: 着色テキスト（Text.setColor を適用）。menu の disabled グレー / cursor 色 / ヘッダ accent 等に必要。
    pub def textTinted(content: String, fontAtlas: FontAtlas, fontSize: Float64, tint: Color, zIndex: Int32): Item =
        Item.Text({ text = content, fontAtlas = fontAtlas, fontSize = fontSize, tint = tint, zIndex = zIndex })

    /// 単色塗りの矩形（左上原点・サイズ指定）。
    pub def box(size: Vec2.Vec2, color: Color, zIndex: Int32): Item =
        Item.Box({ size = size, color = color, alpha = 1.0f32,
                         style = Some(solidStyle()), zIndex = zIndex })

    /// 単色塗りの円（直径 radius×2 の全角丸 Box）。置き場所は外接正方形の左上。
    /// 中心で置きたいときは circleAt を使う。
    pub def circle(radius: Float64, color: Color, zIndex: Int32): Item =
        box({ x = radius * 2.0, y = radius * 2.0 }, color, zIndex) |> rounded(radius)

    /// 中心 center に置いた単色の円（PlacedItem）。外接正方形の左上への換算はここが済ませる。
    pub def circleAt(center: Vec2.Vec2, radius: Float64, color: Color, zIndex: Int32): PlacedItem =
        { at = { x = center#x - radius, y = center#y - radius },
          item = circle(radius, color, zIndex) }

    /// 中心 center に置いた単色の矩形（PlacedItem）。左上で置きたいときは box を使う。
    pub def boxAt(center: Vec2.Vec2, size: Vec2.Vec2, color: Color, zIndex: Int32): PlacedItem =
        { at = { x = center#x - size#x / 2.0, y = center#y - size#y / 2.0 },
          item = box(size, color, zIndex) }

    /// 単色塗りの多角形。頂点は置き場所からの相対座標で渡す（絶対座標で組みたいときは
    /// 置き場所を Vec2.zero() にする）。左右反転した形が欲しいときは頂点を flipH に通してから渡す。
    pub def polygon(vertices: List[Vec2.Vec2], color: Color, zIndex: Int32): Item =
        Item.Poly({ vertices = vertices, color = color, alpha = 1.0f32, zIndex = zIndex })

    def solidStyle(): GameEngine.BoxStyle =
        { cornerRadius = 0.0, borderWidth = 0.0, borderColor = white(), borderAlpha = 0.0f32,
          stripeColor = white(), stripeAlpha = 0.0f32, stripeWidth = 0.0, stripePeriod = 0.0 }

    // ── 修飾（稀な属性はパイプで重ねる。効かない種類の item は素通し）──

    /// 角を丸める（Box に効く）。
    pub def rounded(radius: Float64, item: Item): Item =
        match item {
            case Item.Box(b) =>
                Item.Box({ style = Some({ cornerRadius = radius | styleOf(b#style) }) | b })
            case other => other
        }

    /// 透明度（alpha）を指定した値にする（Sprite / Box / Poly に効く。Text は tint が濃度を兼ねる）。
    pub def fade(alpha: Float32, item: Item): Item =
        match item {
            case Item.Sprite(s) => Item.Sprite({ alpha = alpha | s })
            case Item.Box(b)    => Item.Box({ alpha = alpha | b })
            case Item.Poly(p)   => Item.Poly({ alpha = alpha | p })
            case other                => other
        }

    /// 頂点列を左右に鏡映する（縦軸で x を反転・2 回で元に戻る）。polygon や Bezier の
    /// 輪郭・背骨に渡す前に使う。鏡映は頂点の上でだけ提供する（Text のような
    /// 鏡映できない物に flip を書くと型が合わない = 落ちる代わりにコンパイルで止まる）。
    pub def flipH(vertices: List[Vec2.Vec2]): List[Vec2.Vec2] =
        List.map(v -> { x = -1.0 * v#x, y = v#y }, vertices)

    /// 頂点列を上下に鏡映する（横軸で y を反転・2 回で元に戻る）。使い方は flipH と同じ。
    pub def flipV(vertices: List[Vec2.Vec2]): List[Vec2.Vec2] =
        List.map(v -> { x = v#x, y = -1.0 * v#y }, vertices)

    /// 枠線を付ける（Box に効く）。
    pub def outline(color: Color, width: Float64, item: Item): Item =
        match item {
            case Item.Box(b) =>
                Item.Box({ style = Some({ borderColor = color, borderWidth = width,
                                                borderAlpha = 1.0f32 | styleOf(b#style) }) | b })
            case other => other
        }

    /// 縞模様を敷く（Box に効く）。
    pub def striped(stripe: { color = Color, alpha = Float32, width = Float64, period = Float64 },
                    item: Item): Item =
        match item {
            case Item.Box(b) =>
                Item.Box({ style = Some({ stripeColor = stripe#color, stripeAlpha = stripe#alpha,
                                                stripeWidth = stripe#width, stripePeriod = stripe#period
                                                | styleOf(b#style) }) | b })
            case other => other
        }

    /// 大きさ系の属性を factor 倍する（全種類の item に効く）。camera の zoom 適用の芯:
    /// Box は size と style の太さ（角丸・枠・縞）、Sprite は scale、Text は fontSize、
    /// Poly は頂点を、それぞれ一様に伸縮する。置き場所（at）は持たないので呼び側が伸縮する。
    /// 注意: これ単体では「置き場所はそのまま・中身だけ伸びる」= Box は左上を軸に右下へ育つ。
    /// circleAt / boxAt が済ませた中心→左上の換算も崩れる（中心がずれて見える）。
    /// 物を大きく見せたいときはこれではなく、boxAt のサイズや sprite の scale を変えること。
    /// これが正しく見えるのは、at にも同じ倍率の変換を掛ける camera 経路（CameraRig.centerOnZoomed）だけ。
    pub def scaled(factor: Float64, item: Item): Item =
        match item {
            case Item.Sprite(s) => Item.Sprite({ scale = { x = s#scale#x * factor, y = s#scale#y * factor } | s })
            case Item.Text(t)   => Item.Text({ fontSize = t#fontSize * factor | t })
            case Item.Box(b)    =>
                let style1 = b#style |> Option.map(s ->
                    { cornerRadius = s#cornerRadius * factor, borderWidth = s#borderWidth * factor,
                      stripeWidth = s#stripeWidth * factor, stripePeriod = s#stripePeriod * factor | s });
                Item.Box({ size = { x = b#size#x * factor, y = b#size#y * factor }, style = style1 | b })
            case Item.Poly(p)   => Item.Poly({ vertices = List.map(v -> Vec2.mul(v, factor), p#vertices) | p })
        }

    /// zIndex を delta だけ持ち上げる（全種類の item に効く）。組み上がった item の列を
    /// まとめて別の z 帯へ移すとき（UI レイヤーの合流など）に使う。
    pub def raiseZ(delta: Int32, item: Item): Item =
        match item {
            case Item.Sprite(s) => Item.Sprite({ zIndex = s#zIndex + delta | s })
            case Item.Text(t)   => Item.Text({ zIndex = t#zIndex + delta | t })
            case Item.Box(b)    => Item.Box({ zIndex = b#zIndex + delta | b })
            case Item.Poly(p)   => Item.Poly({ zIndex = p#zIndex + delta | p })
        }

    /// 修飾の土台になる style（無ければ solid）。
    def styleOf(style: Option[GameEngine.BoxStyle]): GameEngine.BoxStyle =
        Option.getWithDefault(solidStyle(), style)

    // ── extract / 射影（lib が Drawable を1回だけ組む）──

    /// draw list 全体を描画命令へ（zIndex 順は render_gl が stable sort する）。
    /// Sprite / Text / Box は Drawable、Poly は置き場所を頂点に織り込んだ PolygonRenderCmd になる —
    /// 呼び側は 1 本のリストを組むだけで、2 系統への振り分けはここで終わる。
    pub def draw(items: List[PlacedItem]): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let drawables = items |> List.flatMap(placed ->
            match placed#item {
                case Item.Poly(_) => Nil
                case other              => toDrawables(other, placed#at)
            });
        let polygons = items |> List.filterMap(placed ->
            match placed#item {
                case Item.Poly(p) => Some(polyCmd(placed#at, p))
                case _                  => None
            });
        (drawables, polygons)

    /// `draw` の atlas 注入版。Sprite の region UV を textureInfoOf で解決しつつ、
    /// Poly も PolygonRenderCmd へ振り分ける（draw と同じ 2 列を返す）。
    /// region 付き sprite と Poly が同じ列に混ざる UI（UiRender）の描画口。
    pub def drawWith(textureInfoOf: String -> Option[GameEngine.TextureInfo] \ ef,
                     items: List[PlacedItem]): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) \ ef =
        let drawables = items |> List.flatMap(placed ->
            match placed#item {
                case Item.Poly(_) => (Nil: List[GameEngine.Drawable])
                case other              => toDrawablesAtlas(textureInfoOf, other, placed#at)
            });
        let polygons = items |> List.filterMap(placed ->
            match placed#item {
                case Item.Poly(p) => Some(polyCmd(placed#at, p))
                case _                  => None
            });
        (drawables, polygons)

    /// Poly を置き場所 pos の描画命令へ（全頂点に pos を加算）。
    def polyCmd(pos: Vec2.Vec2,
                p: { vertices = List[Vec2.Vec2], color = Color, alpha = Float32, zIndex = Int32 }): GameEngine.PolygonRenderCmd =
        { vertices = List.map(v -> Vec2.add(v, pos), p#vertices),
          color = p#color, alpha = p#alpha, zIndex = p#zIndex }

    /// World 由来 Drawable 群に camera のズーム倍率を適用する（位置は `Projection.applyToWorldPos` で
    /// screenPos を出した後の共通後処理）。render-from-World の各オーバーレイ（ユニット / 背景 / 範囲表示 /
    /// フォグ等）が共有する camera 適用 spine。Drawable の scale は sprite の拡大率・box の px サイズを表し、
    /// どちらも zoom で乗算するのが正しい camera 適用。
    pub def applyCameraScale(transform: Projection.ViewTransform,
                             ds: List[GameEngine.Drawable]): List[GameEngine.Drawable] =
        List.map(d -> {scale = {x = d#scale#x * transform#scale#x, y = d#scale#y * transform#scale#y} | d}, ds)

    /// 1 アイテム → 複数 Drawable（ボタン等は呼び側で複数アイテムにする）。
    pub def toDrawables(item: Item, pos: Vec2.Vec2): List[GameEngine.Drawable] =
        match item {
            case Item.Sprite(s) =>
                spriteDrawable(s#texture, s#tint, s#alpha, s#scale, s#rotation,
                               s#centered, s#flipH, s#flipV, s#regionRect, s#zIndex, pos) :: Nil
            case Item.Text(t) =>
                textDrawables(t#text, t#fontAtlas, t#fontSize, t#tint, t#zIndex, pos)
            case Item.Box(b) =>
                boxDrawable(b#size, b#color, b#alpha, b#style, b#zIndex, pos) :: Nil
            case Item.Poly(_) =>
                bug!("Render.toDrawables: Poly は Drawable にならない（draw が PolygonRenderCmd へ振り分ける）")
        }

    /// region atlas 対応の射影（drawWith が使う）。textureSize を引いて UV を計算する
    /// （uvOffset = regionPos/texSize, uvScale = regionSize/texSize）。
    /// 非 region スプライト・text・box は pure 経路と同一。
    def toDrawablesAtlas(textureInfoOf: String -> Option[GameEngine.TextureInfo] \ ef,
                         item: Item, pos: Vec2.Vec2): List[GameEngine.Drawable] \ ef =
        match item {
            case Item.Sprite(s) =>
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
        // （SDF 描画では color が color＝文字色。ItemList の per-item 色相当）。
        Text.toDrawables(Text.make(content, fontAtlas, fontSize), pos)
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
