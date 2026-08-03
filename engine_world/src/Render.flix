// Render — 「何をどう見せたいか」だけ書いた Item を、描画部が食べられる形に変換する。
// スプライトもテキストも箱も円も多角形も、同じ { at = 置き場所, item = Item } の語彙で並べられる。
// 形は box / circle / polygon で作り、稀な属性（角丸・半透明・枠・縞）はパイプ修飾で重ねる。
// 注意: 置き場所は持たず呼び側が渡す。テキストの実寸計算は engine の純粋関数を使う。

mod Render {

    // ── render component（位置を持たない・ノードでない）──

    /// 傾き（rotation）の単位は「回転数」— 1 周 = 1.0・正で時計回り。ラジアンへの変換は
    /// 描画命令を作る出口で 1 回だけ行う（rotated / ui.json の poly と同じ数え方）。
    /// 回す軸は種類ごとに 1 つ: Box と Sprite は自分の中心、Text は置き場所。
    /// 集まりを丸ごと傾けるときは turnedAll を使う（軸の違いはそこが吸収する）。
    pub enum Item {
        /// texture は handle 相当（String）。regionRect=None で全テクスチャ。UV は射影が計算。
        /// （`region` は Flix 予約語なので engine と同じ `regionRect`）
        case Sprite({ texture = String, tint = Color, alpha = Float32,
                      scale = Vec2.Vec2, rotation = Float64, centered = Bool,
                      flipH = Bool, flipV = Bool, regionRect = Option[Rect2.Rect2], zIndex = Int32,
                      blend = DrawCmd.BlendMode })
        case Text({ text = String, fontAtlas = FontAtlas, fontSize = Float64, tint = Color,
                    rotation = Float64, zIndex = Int32 })
        case Box({ size = Vec2.Vec2, color = Color, alpha = Float32, rotation = Float64,
                   style = Option[GameEngine.BoxStyle], zIndex = Int32, blend = DrawCmd.BlendMode })
        /// 単色の単純多角形（自己交差しなければ凹でもよい。塗りは描画側が耳切りで三角形化）。
        /// 頂点は置き場所からの相対座標（draw が置き場所を全頂点に加算する）。
        /// grad = Some(色列) で頂点ごとの色になり面の中で滑らかに混ざる（gradPolygon / vgrad で作る。
        /// 扇割りのため凸の形で使う）。None = color 一色。
        case Poly({ vertices = List[Vec2.Vec2], color = Color, alpha = Float32, zIndex = Int32,
                    blend = DrawCmd.BlendMode, grad = Option[List[DrawCmd.VertexTint]] })
        /// rect（スクリーン空間・design px）で inner を切り抜く。入れ子は交差。
        /// App + withCamera 経路では中身にはカメラが掛かるが、窓は常にスクリーン固定 —
        /// PiP やパネル内スクロール用（world に追従する窓は v1 対象外）。
        case Clipped({ rect = Rect2.Rect2, inner = Item })
        /// 宣言シェーダーで矩形 rect を塗る面（水面など）。GL 経路では eff Shader が本物の
        /// シェーダーで描き、GL の無い経路（SoftRaster / F8 注釈）では代表色のベタ塗りに落ちる。
        /// rect はスクリーン空間 px（uv=0..1 がこの矩形）、t は world#time（uTime に渡す）。
        /// mask = この面を切り抜く多角形の列（rect 左上からの相対座標）。空なら矩形そのまま。
        /// 非空なら GL でステンシルに焼いて「多角形の内側だけ」塗る（丸い池形など任意形に抜く）。
        case Shader({ rect = Rect2.Rect2, spec = ShaderDoc.Spec, t = Float64,
                      mask = List[List[Vec2.Vec2]], zIndex = Int32, blend = DrawCmd.BlendMode })
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
        Item.Text({ text = content, fontAtlas = fontAtlas, fontSize = fontSize, tint = white(),
                    rotation = 0.0, zIndex = zIndex })

    /// 着色テキスト。disabled のグレー表示やカーソル色、見出しの強調色などに使う。
    pub def textTinted(content: String, fontAtlas: FontAtlas, fontSize: Float64, tint: Color, zIndex: Int32): Item =
        Item.Text({ text = content, fontAtlas = fontAtlas, fontSize = fontSize, tint = tint,
                    rotation = 0.0, zIndex = zIndex })

    /// 単色塗りの矩形（左上原点・サイズ指定）。
    pub def box(size: Vec2.Vec2, color: Color, zIndex: Int32): Item =
        Item.Box({ size = size, color = color, alpha = 1.0f32, rotation = 0.0,
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

    /// 中心 center に置いた、縁がふわっと消える円の列（ソフトな光の玉）。
    /// look#alpha は中心の濃さ 0..1、look#blend は重ね方（光り物は Add が定番）。
    /// 減衰は RadialGlow（グロー bake）と同じ smoothstep カーブに合わせてある —
    /// 焼いたハロと絵の系統が揃う。テクスチャに頼らないのは、fx.json（閉形式
    /// パーティクル）が「アセット不要・どの描画部でも同じ絵」を守るため。
    pub def glowAt(center: Vec2.Vec2, radius: Float64, color: Color,
                   look: { alpha = Float64, blend = DrawCmd.BlendMode },
                   zIndex: Int32): List[PlacedItem] =
        if (radius <= 0.0 or look#alpha <= 0.0) Nil
        else {
            // 輪の数は半径に応じて増やす（1px 未満の輪は意味がないため半径 px を上限の目安に、
            // 大きな玉でも段差が見えない 24 で頭打ち・小さな粒でも形が保てる下限 4）。
            let rings = Int32.min(24, Int32.max(4, ceilI(radius)));
            let n = Int32.toFloat64(rings);
            // 外側の輪から順に「その輪まで重なった濃さ」が減衰カーブに乗るように積む。
            // 同色・同ブレンドの重なりは順序に依らないので、輪の並び順は見た目に影響しない。
            List.range(0, rings) |> List.filterMap(k -> {
                let kf = Int32.toFloat64(k);
                let ringRadius = radius * (1.0 - kf / n);
                // 輪 k が受け持つ帯の中央の距離（0=中心, 1=縁）で目標の濃さを決める。
                let target = c -> look#alpha * smoothFalloff(1.0 - (c + 0.5) / n);
                let before = if (k == 0) 0.0 else target(kf - 1.0);
                let goal = target(kf);
                // Add は足し算で濃さが積もる。Normal / Multiply は「上に重ねるほど
                // 残りの薄さが縮む」ので、差分を残り分で割って 1 枚ぶんの alpha に戻す。
                let ringAlpha = match look#blend {
                    case DrawCmd.BlendMode.Add => goal - before
                    case _                     =>
                        if (before >= 0.9999) 0.0 else (goal - before) / (1.0 - before)
                };
                if (ringAlpha <= 0.0) None
                else Some(circleAt(center, ringRadius, color, zIndex)
                    |> (placed -> { item = placed#item
                                        |> fade(Float64.truncateToFloat32(ringAlpha))
                                        |> blended(look#blend) | placed }))
            })
        }

    /// 中心 0 → 縁 1 の距離を濃さ倍率に写す減衰（RadialGlow.smoothstepCurve と同じ式）。
    /// engine_world は engine_tools（RadialGlow の住処）に依存できないため、式だけ揃える。
    def smoothFalloff(t: Float64): Float64 =
        let x = Float64.max(0.0, Float64.min(1.0, 1.0 - t));
        x * x * (3.0 - 2.0 * x)

    /// 切り上げの Int32（輪の数の見積もり用。非負前提）。
    def ceilI(x: Float64): Int32 =
        Float64.ceil(x) |> Float64.tryToInt32 |> Option.getWithDefault(16)

    /// 中心 center に置いた単色の矩形（PlacedItem）。左上で置きたいときは box を使う。
    pub def boxAt(center: Vec2.Vec2, size: Vec2.Vec2, color: Color, zIndex: Int32): PlacedItem =
        { at = { x = center#x - size#x / 2.0, y = center#y - size#y / 2.0 },
          item = box(size, color, zIndex) }

    /// items が空なら boxAt の仮色の板 1 枚に倒す fail-open。スプライトのコマ名違い・
    /// 読み込み失敗で画面に穴を開けない（板が出れば「絵が無い」と目で判る）ための口 —
    /// 空でなければ items をそのまま返す。
    pub def orBoxAt(center: Vec2.Vec2, size: Vec2.Vec2, color: Color, zIndex: Int32,
                    items: List[PlacedItem]): List[PlacedItem] =
        if (List.isEmpty(items)) boxAt(center, size, color, zIndex) :: Nil
        else items

    /// 宣言シェーダーで矩形 rect を塗る面（PlacedItem）。at に rect の左上を入れる —
    /// 描画は at を置き場所に使うので、withCamera 下では at がカメラ変換を受けて面が追従する
    /// （カメラ無しなら at は rect#position のままで画面固定）。t は uTime に渡す秒（world#time など）。
    /// GL 経路では eff Shader が本物のシェーダーで描き、GL の無い経路では代表色ベタ塗りに落ちる。
    pub def shaderFill(spec: ShaderDoc.Spec, rect: Rect2.Rect2, t: Float64, zIndex: Int32): PlacedItem =
        { at = rect#position,
          item = Item.Shader({ rect = rect, spec = spec, t = t, mask = Nil, zIndex = zIndex,
                               blend = DrawCmd.BlendMode.Normal }) }

    /// 宣言シェーダーで rect を塗り、maskPolys（ワールド座標の多角形の列）の内側だけに抜く面。
    /// 丸い池のような任意の形に水面を切り抜くのに使う（GL 経路がステンシルで抜く）。
    /// maskPolys は shaderFill と同じワールド座標で渡す — 内部で rect 左上からの相対に直して
    /// 持つので、withCamera の平行移動・ズームが rect と一緒に mask にも掛かる（形がずれない）。
    pub def shaderFillMasked(spec: ShaderDoc.Spec, rect: Rect2.Rect2,
                             maskPolys: List[List[Vec2.Vec2]], t: Float64, zIndex: Int32): PlacedItem =
        let rel = maskPolys |> List.map(poly ->
            poly |> List.map(v -> Vec2.sub(v, rect#position)));
        { at = rect#position,
          item = Item.Shader({ rect = rect, spec = spec, t = t, mask = rel, zIndex = zIndex,
                               blend = DrawCmd.BlendMode.Normal }) }

    /// 単色塗りの多角形。頂点は置き場所からの相対座標で渡す（絶対座標で組みたいときは
    /// 置き場所を Vec2.zero() にする）。左右反転した形が欲しいときは頂点を flipH に通してから渡す。
    pub def polygon(vertices: List[Vec2.Vec2], color: Color, zIndex: Int32): Item =
        Item.Poly({ vertices = vertices, color = color, alpha = 1.0f32, zIndex = zIndex,
                    blend = DrawCmd.BlendMode.Normal, grad = None })

    /// 頂点色つきの凸多角形。各頂点に色と濃さを与えると、面の中で滑らかに混ざる
    /// （空・水面・光の帯のグラデを 1 部品で描く — 1px の色帯を積む必要はない）。
    /// 頂点は置き場所からの相対座標。描画側が扇割りで三角形化するため凸の形で使うこと
    /// — 凹ませたい形は凸に割って並べる。
    pub def gradPolygon(vertices: List[DrawCmd.GradVertex], zIndex: Int32): Item =
        Item.Poly({ vertices = List.map(v -> v#pos, vertices),
                    color = vertices |> List.head |> Option.map(v -> v#color)
                                     |> Option.getWithDefault(white()),
                    alpha = 1.0f32, zIndex = zIndex, blend = DrawCmd.BlendMode.Normal,
                    grad = Some(List.map(v -> ({ color = v#color, alpha = v#alpha }: DrawCmd.VertexTint),
                                         vertices)) })

    /// 上下 2 色の縦グラデ矩形（左上原点・サイズ指定）。空や夕暮れの背景の定番形。
    /// 濃さも変えたいとき（上へ消える光の帯など）は gradPolygon で頂点ごとに渡す。
    pub def vgrad(size: Vec2.Vec2, colors: { top = Color, bottom = Color }, zIndex: Int32): Item =
        gradPolygon(
            { pos = { x = 0.0, y = 0.0 },       color = colors#top,    alpha = 1.0f32 } ::
            { pos = { x = size#x, y = 0.0 },    color = colors#top,    alpha = 1.0f32 } ::
            { pos = { x = size#x, y = size#y }, color = colors#bottom, alpha = 1.0f32 } ::
            { pos = { x = 0.0, y = size#y },    color = colors#bottom, alpha = 1.0f32 } :: Nil,
            zIndex)

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
        ellipseSegs(radii, 32, color, zIndex)

    /// ellipse を中心 center に置く近道。
    pub def ellipseAt(center: Vec2.Vec2, radii: Vec2.Vec2, color: Color, zIndex: Int32): PlacedItem =
        { at = center, item = ellipse(radii, color, zIndex) }

    /// 縁の分割数を選べる楕円。小さく描く楕円（足元の影・遠くの茂み）では、既定の 32 分割は
    /// 頂点どうしの間隔が 1px を大きく切る — 絵は変わらないのに、頂点を組んで三角形へ
    /// ほどく手間だけが数を積む。何百個も撒く層では大きさに見合う分割数を渡す。
    pub def ellipseSegs(radii: Vec2.Vec2, segs: Int32, color: Color, zIndex: Int32): Item =
        let n = Int32.max(3, segs);
        polygon(List.range(0, n) |> List.map(i ->
            onCircle(radii#x, radii#y, Int32.toFloat64(i) / Int32.toFloat64(n))), color, zIndex)

    /// ellipseSegs を中心 center に置く近道。
    pub def ellipseSegsAt(center: Vec2.Vec2, radii: Vec2.Vec2, segs: Int32, color: Color,
                          zIndex: Int32): PlacedItem =
        { at = center, item = ellipseSegs(radii, segs, color, zIndex) }

    /// その大きさの楕円に見合う縁の分割数。頂点の間隔がおよそ 2px になる所で頭打ちにする
    /// （それ以上細かくしても画面では丸さが変わらない）。
    pub def ellipseSegsFor(radii: Vec2.Vec2): Int32 =
        let r = Float64.max(radii#x, radii#y);
        Int32.max(6, Int32.min(32, Num.floorInt(r) + 6))

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

    /// 置き場所はそのままに、中身（Item）だけ入れ替える。`fade` や `rounded` のような
    /// 「Item を受けて Item を返す」修飾を、置き場所つきの物へ掛ける口。
    /// 修飾ごとに PlacedItem 版を増やさなくて済む。
    pub def overItem(f: Item -> Item \ ef, placed: PlacedItem): PlacedItem \ ef =
        { item = f(placed#item) | placed }

    /// 組み上がった列を丸ごと薄くする（`fade` の列版）。覆い・淡い層・消えていく残像に使う。
    pub def fadeAll(alpha: Float32, items: List[PlacedItem]): List[PlacedItem] =
        items |> List.map(placed -> overItem(fade(alpha), placed))

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
            case Item.Shader(s) => Item.Shader({ blend = mode | s })
            case other          => other
        }, item)

    /// 重なり順（zIndex）を delta だけずらす。組み上がった絵の相対的な前後関係は保ったまま、
    /// 集まり全体を別の層へ持ち上げる／沈める。
    /// 見下ろし画面の Y ソート（足元の高さで前後を決める）は Depth がこれを使って作る。
    pub def zShifted(delta: Int32, item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Sprite(s) => Item.Sprite({ zIndex = s#zIndex + delta | s })
            case Item.Text(x)   => Item.Text({ zIndex = x#zIndex + delta | x })
            case Item.Box(b)    => Item.Box({ zIndex = b#zIndex + delta | b })
            case Item.Poly(p)   => Item.Poly({ zIndex = p#zIndex + delta | p })
            case Item.Shader(s) => Item.Shader({ zIndex = s#zIndex + delta | s })
            case other          => other
        }, item)

    /// 置き場所つきの列を丸ごと delta だけずらす（zShifted の列版）。
    pub def zShiftedAll(delta: Int32, items: List[PlacedItem]): List[PlacedItem] =
        items |> List.map(placed -> { item = zShifted(delta, placed#item) | placed })

    /// 組み上がった列を丸ごと d だけ動かす（zShiftedAll の位置版）。
    /// 部品を 0 起点で組んでから最後に置き場所を与える書き方（盤の原点へ寄せる・
    /// UI の枠の中へ入れる・粒を発生源へ運ぶ）がこれで 1 行になる。
    /// 中身（大きさ・頂点・z）には触らない — 動かすのは置き場所だけ。
    pub def movedAll(d: Vec2.Vec2, items: List[PlacedItem]): List[PlacedItem] =
        items |> List.map(placed -> { at = Vec2.add(d, placed#at) | placed })

    /// 置き場所と頂点を step px の升目に載せる（ドット絵の升目に合わせて角を落とす）。
    /// なめらかな多角形をドット絵と同じ画面に置くと、そこだけ画素の階段が無くて浮くので揃える。
    /// step = 1.0 で 1 画素、2.0 なら 2 画素ぶんの粗さ。静的な絵（1 度だけ焼く層）向けで、
    /// 毎フレーム掛ける物ではない。
    ///
    /// 動かすのは位置だけで、大きさ（箱の size・絵の scale）は触らない — 大きさを丸めると
    /// 敷き詰めた面に隙間や重なりが出るため。半端な大きさの物を升目に載せたいなら、
    /// 呼ぶ側が整数の大きさで作ること。
    pub def snapped(step: Float64, item: Item): Item =
        if (not Float64.isFinite(step) or step <= 0.0) item
        else onLeaf(leaf -> match leaf {
            case Item.Poly(p) => Item.Poly({ vertices = List.map(snapVec(step), p#vertices) | p })
            case other        => other
        }, item)

    /// snapped の列版（置き場所も升目に載せる）。
    pub def snappedAll(step: Float64, items: List[PlacedItem]): List[PlacedItem] =
        if (not Float64.isFinite(step) or step <= 0.0) items
        else items |> List.map(p ->
            { at = snapVec(step, p#at), item = snapped(step, p#item) })

    def snapVec(step: Float64, v: Vec2.Vec2): Vec2.Vec2 =
        { x = Float64.round(v#x / step) * step, y = Float64.round(v#y / step) * step }

    /// 絵の色を差し替える（Sprite だけに効く。白 = 元の絵のまま）。同じ 1 枚の絵を、
    /// 色だけ変えて使い回すための口 — 木や草を 1 本ずつわずかに違う色にすると、
    /// 並んでも単調にならない。
    ///
    /// 掛け算ではなく差し替えなので、すでに色が乗っている絵に重ねても足し合わさらない。
    /// 箱や多角形は素通し（色を持つ場所が別なので、ここでは触らない）。
    pub def tinted(color: Color, item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Sprite(sp) => Item.Sprite({ tint = color | sp })
            case other           => other
        }, item)

    /// tinted の列版。
    pub def tintedAll(color: Color, items: List[PlacedItem]): List[PlacedItem] =
        items |> List.map(p -> { item = tinted(color, p#item) | p })

    /// 飾りの無い箱（角丸・枠線・縞・市松・回転がどれも無い単色）を、同じ形の多角形へ直す。
    /// 静的レイヤー（1 度だけ GPU に焼く層）は多角形だけを焼くので、箱で組んだ絵を
    /// そこへ載せたいときの入口。飾りのある箱・箱以外はそのまま返す（焼かれずに動的側へ残る）。
    pub def boxAsPoly(item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Box(b) =>
                if (Float64.abs(b#rotation) > 0.000001 or not plainStyle(b#style)) leaf
                else Item.Poly({ vertices = { x = 0.0, y = 0.0 } :: { x = b#size#x, y = 0.0 }
                                     :: { x = b#size#x, y = b#size#y } :: { x = 0.0, y = b#size#y } :: Nil,
                                 color = b#color, alpha = b#alpha, zIndex = b#zIndex,
                                 blend = b#blend, grad = None })
            case other => other
        }, item)

    /// boxAsPoly の列版。
    pub def boxesAsPolys(items: List[PlacedItem]): List[PlacedItem] =
        items |> List.map(p -> { item = boxAsPoly(p#item) | p })

    /// その箱が「ただの単色の矩形」か（角丸・枠線・縞・市松がどれも無い）。
    def plainStyle(style: Option[GameEngine.BoxStyle]): Bool =
        match style {
            case None    => true
            case Some(s) =>
                Float64.abs(s#cornerRadius) < 0.000001
                    and Float64.abs(s#borderWidth) < 0.000001
                    and s#borderAlpha == 0.0f32
                    and s#stripeAlpha == 0.0f32
                    and s#checkerAlpha == 0.0f32
        }

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

    /// 1 点を pivot 周りに t 回す（rotatedAround の 1 点版）。
    def rotAbout(t: Float64, pivot: Vec2.Vec2, p: Vec2.Vec2): Vec2.Vec2 =
        rotatedAround(t, pivot, p :: Nil) |> List.head |> Option.getWithDefault(p)

    /// item を自分の軸で t（1 周 = 1.0）傾ける。軸は Box / Sprite が自分の中心、Text が置き場所、
    /// Poly が頂点の原点（＝置き場所）。Shader の面は傾かない — uv の向きが面と一緒に回ると
    /// 模様の意味が変わってしまうので、模様を回したいときは spec 側の Rotate を使う。
    pub def turned(t: Float64, item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Sprite(s) => Item.Sprite({ rotation = s#rotation + t | s })
            case Item.Box(b)    => Item.Box({ rotation = b#rotation + t | b })
            case Item.Text(x)   => Item.Text({ rotation = x#rotation + t | x })
            case Item.Poly(p)   => Item.Poly({ vertices = rotated(t, p#vertices) | p })
            case other          => other
        }, item)

    /// 置き場所つきの列を、pivot（画面座標）のまわりに丸ごと t 傾ける。カード 1 枚のように
    /// 複数部品で 1 つの物を作っているとき、これを通せば全体が 1 枚の板のように傾く
    /// （各部品を自分の軸で回しつつ、置き場所も pivot のまわりを回る）。
    /// 注意: 窓（clipped）の枠は傾かない — 中身だけが回る。centered=false のスプライトは
    /// 中心位置がここでは分からないため左上を軸に回る（既定の centered=true ならズレない）。
    pub def turnedAll(t: Float64, pivot: Vec2.Vec2, items: List[PlacedItem]): List[PlacedItem] =
        items |> List.map(placed -> {
            let anchor = anchorOf(placed);
            let shift = Vec2.sub(rotAbout(t, pivot, anchor), anchor);
            { at = Vec2.add(placed#at, shift), item = turned(t, placed#item) }
        })

    /// その item が「自分の軸で回るときの中心」（画面座標）。turnedAll はこの点を pivot の
    /// まわりに動かすことで、部品の自転と公転を噛み合わせる。
    def anchorOf(placed: PlacedItem): Vec2.Vec2 =
        match leafOf(placed#item) {
            case Item.Box(b) => Vec2.add(placed#at, Vec2.div(b#size, 2.0))
            case _           => placed#at
        }

    /// 枠線を付ける（Box に効く）。
    pub def outline(color: Color, width: Float64, item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Box(b) =>
                Item.Box({ style = Some({ borderColor = color, borderWidth = width,
                                                borderAlpha = 1.0f32 | styleOf(b#style) }) | b })
            case other => other
        }, item)

    /// 濃さつきの枠線を付ける（Box に効く）。outline は枠が常に不透明 — 中身を邪魔しない
    /// 薄い枠（ホバー枠・ガイド線）はこちらで alpha を渡す。同型の引数の取り違えを防ぐため
    /// 名前つきで渡す。
    pub def outlineA(border: { color = Color, alpha = Float32, width = Float64 }, item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Box(b) =>
                Item.Box({ style = Some({ borderColor = border#color, borderWidth = border#width,
                                                borderAlpha = border#alpha | styleOf(b#style) }) | b })
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
    /// Box は size と style の太さ、Sprite は scale、Text は fontSize、Poly は頂点を、
    /// それぞれ一様に伸縮する。置き場所（at）は持たないので呼び側が伸縮する。
    /// 注意: これ単体では置き場所はそのままで中身だけ伸びる = Box は左上を軸に右下へ育ち、
    /// circleAt / boxAt が済ませた中心→左上の換算も崩れる。単に物を大きく見せたいときは
    /// これではなく boxAt のサイズや sprite の scale を変えること。正しく見えるのは、at にも
    /// 同じ倍率を掛ける camera 経路（CameraRig.centerOn）だけ。
    pub def scaled(factor: Float64, item: Item): Item =
        onLeaf(leaf -> match leaf {
            case Item.Sprite(s) => Item.Sprite({ scale = { x = s#scale#x * factor, y = s#scale#y * factor } | s })
            case Item.Text(t)   => Item.Text({ fontSize = t#fontSize * factor | t })
            case Item.Box(b)    =>
                let style1 = b#style |> Option.map(s -> DrawCmd.scalePx(factor, s));
                Item.Box({ size = { x = b#size#x * factor, y = b#size#y * factor }, style = style1 | b })
            case Item.Poly(p)   => Item.Poly({ vertices = List.map(v -> Vec2.mul(v, factor), p#vertices) | p })
            case Item.Shader(s) =>
                Item.Shader({ rect = { position = Vec2.mul(s#rect#position, factor),
                                       size = Vec2.mul(s#rect#size, factor) },
                              mask = s#mask |> List.map(poly ->
                                  poly |> List.map(v -> Vec2.mul(v, factor))) | s })
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
            case Item.Shader(s) => Item.Shader({ zIndex = s#zIndex + delta | s })
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

    /// 描く物のうち、フォントのアトラスにまだ無い字を「テクスチャ名 → 字」で集める。
    /// 起動時に焼くのは「ソースとアセットに書いてある字」なので、実行中に計算で作った字や
    /// プレイヤーが入れた名前はここに出てくる。渡した先（描画部）が焼いて足す。
    /// たいていは空なので、毎フレーム呼んでよい。
    pub def missingGlyphs(items: List[PlacedItem]): Map[String, Set[Int32]] =
        items |> List.foldLeft((acc, placed) -> {
            let (leaf, _clip) = unwrapClip(placed#item, None);
            match leaf {
                case Item.Text(t) =>
                    let atlas = t#fontAtlas;
                    let missing = t#text |> String.toList |> List.filterMap(ch -> {
                        let cp = TextLayout.charToCodePoint(ch);
                        // 改行は字ではない（レイアウトの区切り）。
                        if (cp == 10 or Map.memberOf(cp, atlas#glyphs)) None else Some(cp)
                    });
                    if (List.isEmpty(missing)) acc
                    else {
                        let had = Map.get(atlas#textureName, acc) |> Option.getWithDefault(Set.empty());
                        Map.insert(atlas#textureName, Set.union(had, List.toSet(missing)), acc)
                    }
                case _ => acc
            }
        }, Map.empty())

    /// Shader 面だけを取り出して eff Shader が食える描画依頼へ変換する（GL 経路専用）。
    /// programOf は Spec → コンパイル済みプログラムのハンドル（バックエンドが用意）。
    /// Clipped に包まれた Shader も剥がして拾う。GL の無い経路（F8/SoftRaster）は
    /// これを呼ばず draw の代表色ベタ塗りに任せる。
    pub def drawShaders(programOf: ShaderDoc.Spec -> GpuHandle.ShaderProgram \ ef,
                        items: List[PlacedItem]): List[ShaderEffect.ShaderRenderCmd] \ ef =
        items |> List.filterMap(placed -> {
            let (leaf, _clip) = unwrapClip(placed#item, None);
            match leaf {
                case Item.Shader(s) =>
                    // 位置は placed#at（カメラの平行移動＋ズームを済ませた点）、大きさは
                    // scaled 済みの rect#size から取る — HUD/画面固定（カメラ無しなら at は
                    // rect#position のまま）は不変で、withCamera 下だけワールドの矩形が追従する。
                    // mask も同じ理屈で rect 左上相対 + at にして画面座標にする（rect と同じ
                    // カメラ変換に乗るので形がずれない）。
                    Some({ program = programOf(s#spec),
                           rect = { position = placed#at, size = s#rect#size },
                           mask = s#mask |> List.map(poly ->
                               poly |> List.map(v -> Vec2.add(placed#at, v))),
                           time = s#t, zIndex = s#zIndex, blend = s#blend })
                case _ => None
            }
        })

    /// GL の無い経路（bake / SoftRaster）が ShaderEval で面を焼くための純データ。
    /// drawShaders（GL 用・program ハンドル入り）の headless 版 — バックエンドに依らない値だけ持つ。
    pub type alias ShaderSurface = {
        rect = Rect2.Rect2, spec = ShaderDoc.Spec, time = Float64,
        mask = List[List[Vec2.Vec2]], zIndex = Int32, blend = DrawCmd.BlendMode }

    /// Shader 面を純データ（ShaderSurface）で取り出す（bake / SoftRaster 用）。
    /// 座標の扱いは drawShaders と同一: 位置は placed#at、mask は rect 左上相対 + at。
    /// これを SoftRaster の surfaces に渡すと、draw の代表色ベタ塗りの代わりに
    /// ShaderEval の画素評価で焼ける（draw 側からは withoutShaders で外して二重にしない）。
    pub def shaderSurfaces(items: List[PlacedItem]): List[ShaderSurface] =
        items |> List.filterMap(placed -> {
            let (leaf, _clip) = unwrapClip(placed#item, None);
            match leaf {
                case Item.Shader(s) =>
                    Some({ rect = { position = placed#at, size = s#rect#size },
                           spec = s#spec, time = s#t,
                           mask = s#mask |> List.map(poly ->
                               poly |> List.map(v -> Vec2.add(placed#at, v))),
                           zIndex = s#zIndex, blend = s#blend })
                case _ => None
            }
        })

    /// Shader 面を除いた PlacedItem 列（GL 経路で draw に渡す前に外す — 本物のシェーダーは
    /// drawShaders + eff Shader が別チャンネルで描くので、draw の代表色ベタ塗りと二重にしない）。
    pub def withoutShaders(items: List[PlacedItem]): List[PlacedItem] =
        items |> List.filter(placed -> {
            let (leaf, _clip) = unwrapClip(placed#item, None);
            match leaf {
                case Item.Shader(_) => false
                case _              => true
            }
        })

    /// draw / drawWith の共通トラバーサル。Clipped を剥がして有効な窓（入れ子は交差）を決め、
    /// 葉を Drawable / PolygonRenderCmd へ振り分けてから窓を刻む。振り分けの分岐を 1 本に
    /// しておかないと、Clipped の扱いが 2 経路で割れる。
    /// 2 列は 1 回の走査で同時に積む。列ごとに走査を分けると、描く物 1 個につき
    /// Clipped の剥がしと葉の振り分けが 2 度ずつ走る（物量の多い画面では、その 2 度目が
    /// そのままフレーム時間に乗る）。積むのは逆順の cons で、最後に一度ずつ戻す。
    def drawInto(toDs: (Item, Vec2.Vec2) -> List[GameEngine.Drawable] \ ef,
                 items: List[PlacedItem]): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) \ ef =
        let (dsRev, psRev) = items |> List.foldLeft((acc, placed) -> {
            let (ds, ps) = acc;
            let (leaf, clip) = unwrapClip(placed#item, None);
            // 窓が無いときは刻まない。作りたての Drawable / 描画命令は clip = None なので、
            // ここで None を書き直すと、同じ値を入れ直すためだけにフィールドの
            // 抜き差しが描く物の数だけ走る（窓を使う画面はごく一部）。
            match (leaf, clip) {
                case (Item.Poly(p), None)    => (ds, polyCmd(placed#at, p) :: ps)
                case (Item.Poly(p), Some(_)) => (ds, { clip = clip | polyCmd(placed#at, p) } :: ps)
                case (other, None)           =>
                    (toDs(other, placed#at)
                        |> List.foldLeft((rest, d) -> d :: rest, ds), ps)
                case (other, Some(_))        =>
                    (toDs(other, placed#at)
                        |> List.foldLeft((rest, d) -> { clip = clip | d } :: rest, ds), ps)
            }
        }, ((Nil, Nil): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd])));
        (List.reverse(dsRev), List.reverse(psRev))

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
                     blend = DrawCmd.BlendMode, grad = Option[List[DrawCmd.VertexTint]] }): GameEngine.PolygonRenderCmd =
        { vertices = List.map(v -> Vec2.add(v, pos), p#vertices),
          color = p#color, alpha = p#alpha, zIndex = p#zIndex, clip = None, blend = p#blend,
          grad = p#grad }

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
                textDrawables(t#text, t#fontAtlas, t#fontSize, t#tint, t#rotation, t#zIndex, pos)
            case Item.Box(b) =>
                boxDrawable(b#size, b#color, b#alpha, b#rotation, b#style, b#zIndex, b#blend, pos) :: Nil
            case Item.Poly(_) =>
                bug!("Render.toDrawables: Poly は Drawable にならない（draw が PolygonRenderCmd へ振り分ける）")
            case Item.Shader(s) =>
                // GL の無い経路（SoftRaster / F8 注釈）向けの代表色ベタ塗り。本物のシェーダーは
                // eff Shader が別チャンネルで描くので、ここは「面がそこにある」ことだけ残す。
                boxDrawable(s#rect#size, ShaderDoc.representativeColor(s#spec), 1.0f32, 0.0, None,
                            s#zIndex, s#blend, s#rect#position) :: Nil
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
                   rotation = radiansOf(s#rotation), color = s#tint, alpha = s#alpha, centered = s#centered,
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
                  rotation = radiansOf(rotation),
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

    /// 回転数（1 周 = 1.0）→ 描画命令のラジアン。単位の境目はここ 1 か所だけ。
    def radiansOf(turns: Float64): Float64 = Vec2.tau() * turns

    def textDrawables(content: String, fontAtlas: FontAtlas, fontSize: Float64,
                      tint: Color, rotation: Float64, zIndex: Int32,
                      pos: Vec2.Vec2): List[GameEngine.Drawable] =
        // engine の public 純粋射影に委譲。Drawable の color を tint で上書きして文字色にする
        // （SDF 描画では color がそのまま文字色になる）。
        let ds = Text.toDrawables(Text.make(content, fontAtlas, fontSize), pos)
            |> List.map(d -> {color = tint, zIndex = zIndex | d});
        if (rotation == 0.0) ds
        else ds |> List.map(turnGlyph(rotation, fontAtlas#textureSize, pos))

    /// 文字 1 つぶんの四角を、文字列の置き場所 pivot のまわりに回して置き直す。
    /// 描画側は四角を自分の中心で回すので、中心を公転させたうえで同じ角度を持たせると
    /// 文字列全体が 1 枚の板のように回る。グリフの四角の大きさは
    /// scale × アトラス辺長（Text.toDrawables がそう組んでいる）。
    def turnGlyph(t: Float64, textureSize: Float64, pivot: Vec2.Vec2,
                  d: GameEngine.Drawable): GameEngine.Drawable =
        let size = { x = d#scale#x * textureSize, y = d#scale#y * textureSize };
        let half = Vec2.div(size, 2.0);
        let moved = rotAbout(t, pivot, Vec2.add(d#position, half));
        { position = Vec2.sub(moved, half), rotation = radiansOf(t) | d }

    def boxDrawable(size: Vec2.Vec2, color: Color, alpha: Float32, rotation: Float64,
                    style: Option[GameEngine.BoxStyle], zIndex: Int32, blend: DrawCmd.BlendMode,
                    pos: Vec2.Vec2): GameEngine.Drawable =
        // texture=""・centered=false・position=左上・scale=ピクセルサイズ・style=Some で単色塗り。
        { texture  = "",
          position = pos,
          scale    = size,
          rotation = radiansOf(rotation),
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
