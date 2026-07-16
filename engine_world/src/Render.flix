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
                      flipH = Bool, flipV = Bool, regionRect = Option[Rect2.Rect2], zIndex = Int32,
                      blend = DrawCmd.BlendMode })
        case Text({ text = String, fontAtlas = FontAtlas, fontSize = Float64, tint = Color, zIndex = Int32 })
        case Box({ size = Vec2.Vec2, color = Color, alpha = Float32,
                   style = Option[GameEngine.BoxStyle], zIndex = Int32, blend = DrawCmd.BlendMode })
        /// 単色の単純多角形（自己交差しなければ凹でもよい。塗りは描画側が耳切りで三角形化）。
        /// 頂点は置き場所からの相対座標（draw が置き場所を全頂点に加算する）。
        case Poly({ vertices = List[Vec2.Vec2], color = Color, alpha = Float32, zIndex = Int32,
                    blend = DrawCmd.BlendMode })
        /// rect（スクリーン空間・design px）で inner を切り抜く。入れ子は交差。
        /// App + withCamera 経路では中身にはカメラが掛かるが、窓は常にスクリーン固定 —
        /// PiP やパネル内スクロール用（world に追従する窓は v1 対象外）。
        case Clipped({ rect = Rect2.Rect2, inner = Item })
    }

    /// 置き場所つきの描画物。View はこの列を組み、draw が描画命令へ変換する。
    pub type alias PlacedItem = { at = Vec2.Vec2, item = Item }

    // ── smart constructor（Drawable/BoxStyle をゲームから隠す）──

    def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// 全テクスチャ・等倍・中心原点のスプライト（最頻ケース）。反転が要るときは spriteFlipped。
    pub def sprite(texture: String, zIndex: Int32): Item =
        Item.Sprite({ texture = texture, tint = white(), alpha = 1.0f32,
                            scale = {x = 1.0, y = 1.0}, rotation = 0.0, centered = true,
                            flipH = false, flipV = false, regionRect = None, zIndex = zIndex,
                            blend = DrawCmd.BlendMode.Normal })

    /// 反転付きスプライト。同型の Bool 2 つは取り違えやすいので名前で渡す。
    pub def spriteFlipped(texture: String, zIndex: Int32,
                          flip: { flipH = Bool, flipV = Bool }): Item =
        Item.Sprite({ texture = texture, tint = white(), alpha = 1.0f32,
                            scale = {x = 1.0, y = 1.0}, rotation = 0.0, centered = true,
                            flipH = flip#flipH, flipV = flip#flipV, regionRect = None, zIndex = zIndex,
                            blend = DrawCmd.BlendMode.Normal })

    pub def text(content: String, fontAtlas: FontAtlas, fontSize: Float64, zIndex: Int32): Item =
        Item.Text({ text = content, fontAtlas = fontAtlas, fontSize = fontSize, tint = white(), zIndex = zIndex })

    /// B0b: 着色テキスト（Text.setColor を適用）。menu の disabled グレー / cursor 色 / ヘッダ accent 等に必要。
    pub def textTinted(content: String, fontAtlas: FontAtlas, fontSize: Float64, tint: Color, zIndex: Int32): Item =
        Item.Text({ text = content, fontAtlas = fontAtlas, fontSize = fontSize, tint = tint, zIndex = zIndex })

    /// 単色塗りの矩形（左上原点・サイズ指定）。
    pub def box(size: Vec2.Vec2, color: Color, zIndex: Int32): Item =
        Item.Box({ size = size, color = color, alpha = 1.0f32,
                         style = Some(solidStyle()), zIndex = zIndex,
                         blend = DrawCmd.BlendMode.Normal })

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
        Item.Poly({ vertices = vertices, color = color, alpha = 1.0f32, zIndex = zIndex,
                    blend = DrawCmd.BlendMode.Normal })

    // ── 図形の語彙（polygon の上に組んだ形。凹も可 — 描画側の耳切りが三角形化する）──
    // 角度はぜんぶ「1 周 = 1.0 の回転量 t」で渡す（t = 0 が真上・時計回り = 画面の見た目どおり）。
    // 各図形は Item 版（頂点は原点中心。fade などの修飾をパイプで重ねてから置く）と、
    // 無修飾の近道の At 版（中心を渡すと PlacedItem になる）の 2 段構え。

    /// 正 n 角形（外接半径 radius・頂点が真上・原点中心）。三角形・ひし形・六角形はこれ。
    pub def ngon(n: Int32, radius: Float64, color: Color, zIndex: Int32): Item =
        polygon(List.range(0, n) |> List.map(i ->
            onCircle(radius, radius, Int32.toFloat64(i) / Int32.toFloat64(n))), color, zIndex)

    /// ngon を中心 center に置く近道。
    pub def ngonAt(center: Vec2.Vec2, n: Int32, radius: Float64, color: Color, zIndex: Int32): PlacedItem =
        { at = center, item = ngon(n, radius, color, zIndex) }

    /// 楕円（radii は x/y の半径・原点中心。32 角形の近似）。
    /// 同型の Float64 2 つは取り違えやすいので Vec2 で渡す。
    pub def ellipse(radii: Vec2.Vec2, color: Color, zIndex: Int32): Item =
        let segs = 32;
        polygon(List.range(0, segs) |> List.map(i ->
            onCircle(radii#x, radii#y, Int32.toFloat64(i) / Int32.toFloat64(segs))), color, zIndex)

    /// ellipse を中心 center に置く近道。
    pub def ellipseAt(center: Vec2.Vec2, radii: Vec2.Vec2, color: Color, zIndex: Int32): PlacedItem =
        { at = center, item = ellipse(radii, color, zIndex) }

    /// 扇形（パイ。要が原点）。中心角が半周を超える形（パックマン等）も正しく塗れる
    /// — 凹みは描画側の耳切りが三角形化する。
    pub def sector(radius: Float64, sweep: {fromT = Float64, toT = Float64},
                   color: Color, zIndex: Int32): Item =
        polygon(Vec2.zero() :: arcPoints(radius, sweep), color, zIndex)

    /// sector を中心 center に置く近道。
    pub def sectorAt(center: Vec2.Vec2, radius: Float64, sweep: {fromT = Float64, toT = Float64},
                     color: Color, zIndex: Int32): PlacedItem =
        { at = center, item = sector(radius, sweep, color, zIndex) }

    /// 円を弦で切った弓形（弧 + 弦。多角形は自動で閉じる・原点中心の円由来）。
    pub def circleSegment(radius: Float64, sweep: {fromT = Float64, toT = Float64},
                          color: Color, zIndex: Int32): Item =
        polygon(arcPoints(radius, sweep), color, zIndex)

    /// circleSegment を中心 center に置く近道。
    pub def circleSegmentAt(center: Vec2.Vec2, radius: Float64, sweep: {fromT = Float64, toT = Float64},
                            color: Color, zIndex: Int32): PlacedItem =
        { at = center, item = circleSegment(radius, sweep, color, zIndex) }

    /// 星（points 尖り・外径と内径の交互・原点中心）。凹んだ形の代表。
    pub def star(points: Int32, radii: {outer = Float64, inner = Float64},
                 color: Color, zIndex: Int32): Item =
        polygon(List.range(0, points * 2) |> List.map(i -> {
            let r = if (Int32.modulo(i, 2) == 0) radii#outer else radii#inner;
            onCircle(r, r, Int32.toFloat64(i) / Int32.toFloat64(points * 2))
        }), color, zIndex)

    /// star を中心 center に置く近道。
    pub def starAt(center: Vec2.Vec2, points: Int32, radii: {outer = Float64, inner = Float64},
                   color: Color, zIndex: Int32): PlacedItem =
        { at = center, item = star(points, radii, color, zIndex) }

    /// 線分 a→b の輪郭（太さ width の凸四角形の頂点列）。lineSeg の芯で、時計の針のように
    /// 「根元を原点に置いて rotated で回す」使い方のために頂点のまま取れるようにしてある。
    pub def lineQuad(a: Vec2.Vec2, b: Vec2.Vec2, width: Float64): List[Vec2.Vec2] =
        let d = Vec2.sub(b, a);
        let len = Vec2.length(d);
        let nrm = if (len < 0.0001) Vec2.zero()
                  else Vec2.mul({ x = 0.0 - d#y / len, y = d#x / len }, width / 2.0);
        Vec2.add(a, nrm) :: Vec2.add(b, nrm) :: Vec2.sub(b, nrm) :: Vec2.sub(a, nrm) :: Nil

    /// 線分 a→b を太さ width の四角形で描く（任意角度の線の代用）。
    /// a, b は絶対座標で渡す（置き場所は組み込み済み）。
    pub def lineSeg(a: Vec2.Vec2, b: Vec2.Vec2, width: Float64, color: Color, zIndex: Int32): PlacedItem =
        { at = Vec2.zero(), item = polygon(lineQuad(a, b, width), color, zIndex) }

    /// 飾り終えた「左上原点の item」（box / circle / text）を中心 center に置く
    /// （size はその item の見た目の大きさ。中心→左上の換算をここが済ませる）。
    /// 「Item を作る → パイプで修飾 → atCenter で置く」が一方通行で読める並びになる。
    /// Poly は受け付けず loud に落とす — 頂点が原点中心なので `{ at = center, item = … }` が
    /// そのまま中心置きであり、ここを通すと黙って半サイズずれる事故になるため。
    /// ガードは Clipped を剥がした葉で判定する（窓に包んでもすり抜けさせない）。
    pub def atCenter(center: Vec2.Vec2, size: Vec2.Vec2, item: Item): PlacedItem =
        match leafOf(item) {
            case Item.Poly(_) =>
                bug!("Render.atCenter: Poly は at がそのまま中心 — { at = center, item = … } と書く")
            case _ =>
                { at = { x = center#x - size#x / 2.0, y = center#y - size#y / 2.0 }, item = item }
        }

    /// Clipped を剥がした芯の item（ガード判定用 — 窓は見ない）。
    def leafOf(item: Item): Item =
        match item {
            case Item.Clipped(c) => leafOf(c#inner)
            case leaf            => leaf
        }

    /// 円周（楕円周）上の点（Vec2.onEllipse の近道 — 半径 2 つを個別に受ける内部形）。
    def onCircle(rx: Float64, ry: Float64, t: Float64): Vec2.Vec2 =
        Vec2.onEllipse({ x = rx, y = ry }, t)

    /// fromT..toT の弧を 24 分割した点列（端点含む）。
    def arcPoints(radius: Float64, sweep: {fromT = Float64, toT = Float64}): List[Vec2.Vec2] =
        let segs = 24;
        List.range(0, segs + 1) |> List.map(i ->
            onCircle(radius, radius,
                sweep#fromT + (sweep#toT - sweep#fromT) * Int32.toFloat64(i) / Int32.toFloat64(segs)))

    def solidStyle(): GameEngine.BoxStyle =
        DrawCmd.defaultStyle(white())

    // ── clip（スクリーン空間の切り抜き窓）──

    /// item を rect（スクリーン空間・design px）で切り抜く。窓の外のピクセルは描かれない。
    /// 入れ子は交差。修飾（fade / scaled 等）は窓を素通りして中身に効く。
    /// 端のちらつきを避けるため rect は整数 design px で作ること。
    pub def clipped(rect: Rect2.Rect2, item: Item): Item =
        Item.Clipped({ rect = rect, inner = item })

    /// 置き場所つきの列をまとめて切り抜く近道（PiP・パネル内スクロールの出口で使う）。
    pub def clippedAll(rect: Rect2.Rect2, items: List[PlacedItem]): List[PlacedItem] =
        items |> List.map(p -> { item = clipped(rect, p#item) | p })

    // ── 修飾（稀な属性はパイプで重ねる。効かない種類の item は素通し）──

    /// 修飾を Clipped の窓越しに葉へ届ける。窓（rect）には触れない —
    /// 「clip は最後の見た目、修飾は中身」という一方向の重なりを保つ。
    def onLeaf(f: Item -> Item, item: Item): Item =
        match item {
            case Item.Clipped(c) => Item.Clipped({ inner = onLeaf(f, c#inner) | c })
            case leaf            => f(leaf)
        }

    /// 角を丸める（Box に効く）。
    pub def rounded(radius: Float64, item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Box(b) =>
                Item.Box({ style = Some({ cornerRadius = radius | styleOf(b#style) }) | b })
            case other => other
        }, item)

    /// 透明度（alpha）を指定した値にする（Sprite / Box / Poly に効く。Text は tint が濃度を兼ねる）。
    pub def fade(alpha: Float32, item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Sprite(s) => Item.Sprite({ alpha = alpha | s })
            case Item.Box(b)    => Item.Box({ alpha = alpha | b })
            case Item.Poly(p)   => Item.Poly({ alpha = alpha | p })
            case other                => other
        }, item)

    /// ピクセルの重ね方を変える（Sprite / Box / Poly に効く。Text は文字の可読性が第一で対象外）。
    /// Add = 明るく足す（グロー・炎・魔法）、Multiply = 暗く沈める（影・暗幕）。
    /// どちらも「自分より奥（小さい zIndex）に描かれた物」に効く — 暗幕で暗くしたい物は
    /// 暗幕より小さい z に置くこと。同じ zIndex 同士では draw の並べ順が奥/手前を決める
    /// （安定ソートは同順位を入力順のまま保つため、先に並べた物ほど奥＝ blend が効く側になる）。
    pub def blended(mode: DrawCmd.BlendMode, item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Sprite(s) => Item.Sprite({ blend = mode | s })
            case Item.Box(b)    => Item.Box({ blend = mode | b })
            case Item.Poly(p)   => Item.Poly({ blend = mode | p })
            case other          => other
        }, item)

    /// 頂点列を左右に鏡映する（縦軸で x を反転・2 回で元に戻る）。polygon や Bezier の
    /// 輪郭・背骨に渡す前に使う。鏡映は頂点の上でだけ提供する（Text のような
    /// 鏡映できない物に flip を書くと型が合わない = 落ちる代わりにコンパイルで止まる）。
    pub def flipH(vertices: List[Vec2.Vec2]): List[Vec2.Vec2] =
        List.map(v -> { x = -1.0 * v#x, y = v#y }, vertices)

    /// 頂点列を上下に鏡映する（横軸で y を反転・2 回で元に戻る）。使い方は flipH と同じ。
    pub def flipV(vertices: List[Vec2.Vec2]): List[Vec2.Vec2] =
        List.map(v -> { x = v#x, y = -1.0 * v#y }, vertices)

    /// 頂点列を原点周りに t（1 周 = 1.0・正で時計回り = 画面の見た目どおり）回す。
    /// 回転の軸は「頂点をどこを原点に組むか」で決める（他エンジンの pivot と同じ考え方）:
    /// 原点中心の形なら中心回転、lineQuad の根元を原点に置けば時計の針になる。
    pub def rotated(t: Float64, vertices: List[Vec2.Vec2]): List[Vec2.Vec2] =
        let c = Vec2.cos(Vec2.tau() * t);
        let s = Vec2.sin(Vec2.tau() * t);
        List.map(v -> { x = v#x * c - v#y * s, y = v#x * s + v#y * c }, vertices)

    /// 任意の点 pivot 周りに回す（蝶番・ドア用の近道。pivot へ寄せて回して戻すのと同じ）。
    pub def rotatedAround(t: Float64, pivot: Vec2.Vec2, vertices: List[Vec2.Vec2]): List[Vec2.Vec2] =
        vertices
            |> List.map(v -> Vec2.sub(v, pivot))
            |> rotated(t)
            |> List.map(v -> Vec2.add(v, pivot))

    /// 枠線を付ける（Box に効く）。
    pub def outline(color: Color, width: Float64, item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Box(b) =>
                Item.Box({ style = Some({ borderColor = color, borderWidth = width,
                                                borderAlpha = 1.0f32 | styleOf(b#style) }) | b })
            case other => other
        }, item)

    /// 縞模様を敷く（Box に効く）。dir は 0 = 斜め 45° / 1 = 横縞 / 2 = 縦縞。
    pub def striped(stripe: { color = Color, alpha = Float32, width = Float64, period = Float64, dir = Int32 },
                    item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Box(b) =>
                Item.Box({ style = Some({ stripeColor = stripe#color, stripeAlpha = stripe#alpha,
                                                stripeWidth = stripe#width, stripePeriod = stripe#period,
                                                stripeDir = stripe#dir
                                                | styleOf(b#style) }) | b })
            case other => other
        }, item)

    /// 市松のタイルを重ねる（Box に効く）。PC-98 の網ディザ風。
    pub def checker(c: { color = Color, alpha = Float32, cell = Float64 }, item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Box(b) =>
                Item.Box({ style = Some({ checkerColor = c#color, checkerAlpha = c#alpha,
                                                checkerCell = c#cell
                                                | styleOf(b#style) }) | b })
            case other => other
        }, item)

    /// 大きさ系の属性を factor 倍する（全種類の item に効く）。camera の zoom 適用の芯:
    /// Box は size と style の太さ（角丸・枠・縞・市松）、Sprite は scale、Text は fontSize、
    /// Poly は頂点を、それぞれ一様に伸縮する。置き場所（at）は持たないので呼び側が伸縮する。
    /// 注意: これ単体では「置き場所はそのまま・中身だけ伸びる」= Box は左上を軸に右下へ育つ。
    /// circleAt / boxAt が済ませた中心→左上の換算も崩れる（中心がずれて見える）。
    /// 物を大きく見せたいときはこれではなく、boxAt のサイズや sprite の scale を変えること。
    /// これが正しく見えるのは、at にも同じ倍率の変換を掛ける camera 経路（CameraRig.centerOn）だけ。
    pub def scaled(factor: Float64, item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Sprite(s) => Item.Sprite({ scale = { x = s#scale#x * factor, y = s#scale#y * factor } | s })
            case Item.Text(t)   => Item.Text({ fontSize = t#fontSize * factor | t })
            case Item.Box(b)    =>
                let style1 = b#style |> Option.map(s -> DrawCmd.scalePx(factor, s));
                Item.Box({ size = { x = b#size#x * factor, y = b#size#y * factor }, style = style1 | b })
            case Item.Poly(p)   => Item.Poly({ vertices = List.map(v -> Vec2.mul(v, factor), p#vertices) | p })
            case Item.Clipped(_) => bug!("Render.scaled: onLeaf が Clipped を剥がすのでここには届かない")
        }, item)

    /// zIndex を delta だけ持ち上げる（全種類の item に効く）。組み上がった item の列を
    /// まとめて別の z 帯へ移すとき（UI レイヤーの合流など）に使う。
    pub def raiseZ(delta: Int32, item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Sprite(s) => Item.Sprite({ zIndex = s#zIndex + delta | s })
            case Item.Text(t)   => Item.Text({ zIndex = t#zIndex + delta | t })
            case Item.Box(b)    => Item.Box({ zIndex = b#zIndex + delta | b })
            case Item.Poly(p)   => Item.Poly({ zIndex = p#zIndex + delta | p })
            case Item.Clipped(_) => bug!("Render.raiseZ: onLeaf が Clipped を剥がすのでここには届かない")
        }, item)

    /// 修飾の土台になる style（無ければ solid）。
    def styleOf(style: Option[GameEngine.BoxStyle]): GameEngine.BoxStyle =
        Option.getWithDefault(solidStyle(), style)

    // ── extract / 射影（lib が Drawable を1回だけ組む）──

    /// draw list 全体を描画命令へ（zIndex 順は render_gl が stable sort する）。
    /// Sprite / Text / Box は Drawable、Poly は置き場所を頂点に織り込んだ PolygonRenderCmd になる —
    /// 呼び側は 1 本のリストを組むだけで、2 系統への振り分けはここで終わる。
    pub def draw(items: List[PlacedItem]): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        drawInto((item, pos) -> toDrawables(item, pos), items)

    /// `draw` の atlas 注入版。Sprite の region UV を textureInfoOf で解決しつつ、
    /// Poly も PolygonRenderCmd へ振り分ける（draw と同じ 2 列を返す）。
    /// region 付き sprite と Poly が同じ列に混ざる UI（UiRender）の描画口。
    pub def drawWith(textureInfoOf: String -> Option[GameEngine.TextureInfo] \ ef,
                     items: List[PlacedItem]): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) \ ef =
        drawInto((item, pos) -> toDrawablesAtlas(textureInfoOf, item, pos), items)

    /// draw / drawWith の共通トラバーサル。Clipped を剥がして有効な窓（入れ子は交差）を決め、
    /// 葉を Drawable / PolygonRenderCmd へ振り分けてから窓を刻む。振り分けの分岐を 1 本に
    /// しておかないと、Clipped の扱いが 2 経路で割れる。
    def drawInto(toDs: (Item, Vec2.Vec2) -> List[GameEngine.Drawable] \ ef,
                 items: List[PlacedItem]): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) \ ef =
        let drawables = items |> List.flatMap(placed -> {
            let (leaf, clip) = unwrapClip(placed#item, None);
            match leaf {
                case Item.Poly(_) => (Nil: List[GameEngine.Drawable])
                case other        => toDs(other, placed#at) |> List.map(d -> { clip = clip | d })
            }
        });
        let polygons = items |> List.filterMap(placed -> {
            let (leaf, clip) = unwrapClip(placed#item, None);
            match leaf {
                case Item.Poly(p) => Some({ clip = clip | polyCmd(placed#at, p) })
                case _            => None
            }
        });
        (drawables, polygons)

    /// Clipped を剥がし、(芯の item, 有効な窓) を返す。入れ子の窓は交差する。
    def unwrapClip(item: Item, clip: Option[Rect2.Rect2]): (Item, Option[Rect2.Rect2]) =
        match item {
            case Item.Clipped(c) =>
                let merged = match clip {
                    case None    => Some(c#rect)
                    case Some(r) => Some(Rect2.intersect(r, c#rect))
                };
                unwrapClip(c#inner, merged)
            case leaf => (leaf, clip)
        }

    /// Poly を置き場所 pos の描画命令へ（全頂点に pos を加算）。
    def polyCmd(pos: Vec2.Vec2,
                p: { vertices = List[Vec2.Vec2], color = Color, alpha = Float32, zIndex = Int32,
                     blend = DrawCmd.BlendMode }): GameEngine.PolygonRenderCmd =
        { vertices = List.map(v -> Vec2.add(v, pos), p#vertices),
          color = p#color, alpha = p#alpha, zIndex = p#zIndex, clip = None, blend = p#blend }

    /// World 由来 Drawable 群に camera のズーム倍率を適用する（位置は `Projection.applyToWorldPos` で
    /// screenPos を出した後の共通後処理）。render-from-World の各オーバーレイ（ユニット / 背景 / 範囲表示 /
    /// フォグ等）が共有する camera 適用 spine。Drawable の scale は sprite の拡大率・box の px サイズを表し、
    /// どちらも zoom で乗算するのが正しい camera 適用。
    pub def applyCameraScale(transform: Projection.ViewTransform,
                             ds: List[GameEngine.Drawable]): List[GameEngine.Drawable] =
        List.map(d -> {scale = {x = d#scale#x * transform#scale#x, y = d#scale#y * transform#scale#y} | d}, ds)

    /// 1 アイテム → 複数 Drawable（ボタン等は呼び側で複数アイテムにする）。
    /// Clipped は中身を変換してから窓を刻む（入れ子は交差 — draw を通さない直呼びでも clip が効く）。
    pub def toDrawables(item: Item, pos: Vec2.Vec2): List[GameEngine.Drawable] =
        match item {
            case Item.Sprite(s) =>
                spriteDrawable(s#texture, s#tint, s#alpha, s#scale, s#rotation,
                               s#centered, s#flipH, s#flipV, s#regionRect, s#zIndex, s#blend, pos) :: Nil
            case Item.Text(t) =>
                textDrawables(t#text, t#fontAtlas, t#fontSize, t#tint, t#zIndex, pos)
            case Item.Box(b) =>
                boxDrawable(b#size, b#color, b#alpha, b#style, b#zIndex, b#blend, pos) :: Nil
            case Item.Poly(_) =>
                bug!("Render.toDrawables: Poly は Drawable にならない（draw が PolygonRenderCmd へ振り分ける）")
            case Item.Clipped(c) =>
                toDrawables(c#inner, pos) |> List.map(d -> { clip = mergeClip(c#rect, d#clip) | d })
        }

    /// 窓 rect を既存の clip と重ねる（両方あれば交差）。
    def mergeClip(rect: Rect2.Rect2, existing: Option[Rect2.Rect2]): Option[Rect2.Rect2] =
        match existing {
            case None    => Some(rect)
            case Some(r) => Some(Rect2.intersect(rect, r))
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
                   uvOffset = uvOff, uvScale = uvScl, zIndex = s#zIndex, style = None,
                   clip = None, blend = s#blend }: GameEngine.Drawable) :: Nil
            case other => toDrawables(other, pos)
        }

    // flip は base scale に符号を“乗算”（engine spriteToDrawable と同じ）。centered は素通し。
    // region=Some は textureSize(\Game) が要るので今回未対応＝loud に落とす（部分関数を残さない）。
    def spriteDrawable(texture: String, tint: Color, alpha: Float32, scale: Vec2.Vec2,
                       rotation: Float64, centered: Bool, flipH: Bool, flipV: Bool,
                       regionRect: Option[Rect2.Rect2], zIndex: Int32, blend: DrawCmd.BlendMode,
                       pos: Vec2.Vec2): GameEngine.Drawable =
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
                  style    = None,
                  clip     = None,
                  blend    = blend }
        }

    def flipSign(b: Bool): Float64 = if (b) -1.0 else 1.0

    def textDrawables(content: String, fontAtlas: FontAtlas, fontSize: Float64,
                      tint: Color, zIndex: Int32, pos: Vec2.Vec2): List[GameEngine.Drawable] =
        // engine の public 純粋射影に委譲。B0b: Drawable の color を tint で上書き＝文字色
        // （SDF 描画では color が color＝文字色。ItemList の per-item 色相当）。
        Text.toDrawables(Text.make(content, fontAtlas, fontSize), pos)
            |> List.map(d -> {color = tint, zIndex = zIndex | d})

    def boxDrawable(size: Vec2.Vec2, color: Color, alpha: Float32,
                    style: Option[GameEngine.BoxStyle], zIndex: Int32, blend: DrawCmd.BlendMode,
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
          style    = style,
          clip     = None,
          blend    = blend }
}
