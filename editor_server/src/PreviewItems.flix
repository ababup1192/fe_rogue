// PreviewItems — POST /preview/items。エディタのプラグインが送る「プリミティブの宣言列」
// (箱・円・線・文字・スプライト) を 1 枚の PNG に描いて返す汎用プレビュー口。
// プラグイン側は絵を描かない — 描くのは常にエンジン (Render + SoftRaster) で、
// ゲーム画面とプレビューの見た目が食い違わないようにする。
// 座標は design 座標 (左上原点)。キャンバス寸法は body の design、無ければ project.json の値。
// 失敗の返し分けは PreviewUi と同じ: 封筒不正だけ HTTP 400、内容の問題は 200 の ok:false。

mod PreviewItems {
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JString, JNumber, JBool, JNull}

    /// 宣言 1 個ぶんの描き物。id を付けた物だけ、応答の rects に外接矩形を返す
    /// (編集画面がクリックで選ぶための当たり枠)。
    pub enum Item {
        /// 左上 (x, y) から w×h の塗り箱。outline があれば枠線も引く。
        case BoxI({ id = Option[String], x = Float64, y = Float64, w = Float64, h = Float64,
                    color = Color, alpha = Float32, z = Int32, outline = Option[Color] })
        /// 中心 (x, y)・半径 r の塗り円。
        case CircleI({ id = Option[String], x = Float64, y = Float64, r = Float64,
                       color = Color, alpha = Float32, z = Int32 })
        /// 端点 a→b を太さ width で結ぶ線。
        case LineI({ id = Option[String], a = Vec2.Vec2, b = Vec2.Vec2, width = Float64,
                     color = Color, alpha = Float32, z = Int32 })
        /// 左上 (x, y) に字の高さ size で置く文字列。
        case TextI({ id = Option[String], x = Float64, y = Float64, size = Float64,
                     text = String, color = Color, z = Int32 })
        /// 左上 (x, y) から w×h に伸縮して置くテクスチャ。texture は project.json の manifest 名。
        case SpriteI({ id = Option[String], x = Float64, y = Float64, w = Float64, h = Float64,
                       texture = String, alpha = Float32, z = Int32 })
    }

    /// リクエストボディを解いて (HTTP status, 応答 JSON) を作る。
    /// body: {items, design?, scale?}。items の中身の問題は 200 の ok:false で返す。
    pub def respond(dir: String, caches: Caches.Caches, body: String): (Int32, Json) \ IO =
        match (DocJson.parse(body) |> Option.flatMap(JsonCodec.expectObject)) {
            case None      => (400, envelopeError("body must be a JSON object {items, design?, scale?}"))
            case Some(obj) => match Map.get("items", obj) {
                case None            => (400, envelopeError("body must contain items (array of primitives)"))
                case Some(itemsJson) =>
                    let scale = PreviewUi.clampScale(JsonCodec.intOr("scale", 2, obj));
                    match itemsFromJson(itemsJson) {
                        case Err(message) => (200, failJson(message))
                        case Ok(items)    => preview(dir, caches, obj, items, scale)
                    }
            }
        }

    // ════════════════════════════════════════════════════════
    // 宣言列のパース (純関数 — テスト対象)
    // ════════════════════════════════════════════════════════

    /// items の JSON 配列を描き物の列に解く。1 個でも読めない要素があれば、
    /// どの item かが分かる文言の Err で全体を止める (黙って描き落とさない)。
    pub def itemsFromJson(json: Json): Result[String, List[Item]] =
        match json {
            case JArray(elements) =>
                List.zip(List.range(0, Vector.length(elements)), Vector.toList(elements))
                    |> Result.traverse(match (index, element) -> itemFromJson(index, element))
            case _ => Err("items は配列で送ってください")
        }

    /// index 番目の要素を 1 個の描き物に解く。
    def itemFromJson(index: Int32, json: Json): Result[String, Item] =
        match JsonCodec.expectObject(json) {
            case None      => Err("items[${index}] がオブジェクトではありません")
            case Some(obj) => match JsonCodec.stringOr("type", "(なし)", obj) {
                case "box"      => boxFromJson("items[${index}] (box)", obj)
                case "circle"   => circleFromJson("items[${index}] (circle)", obj)
                case "line"     => lineFromJson("items[${index}] (line)", obj)
                case "text"     => textFromJson("items[${index}] (text)", obj)
                case "sprite"   => spriteFromJson("items[${index}] (sprite)", obj)
                case typeName   =>
                    Err("items[${index}]: type '${typeName}' は知らない種類です (box / circle / line / text / sprite)")
            }
        }

    def boxFromJson(loc: String, obj: Map[String, Json]): Result[String, Item] =
        forM (
            x       <- floatField(loc, "x", obj);
            y       <- floatField(loc, "y", obj);
            w       <- floatField(loc, "w", obj);
            h       <- floatField(loc, "h", obj);
            color   <- colorField(loc, "color", obj);
            outline <- outlineField(loc, obj)
        ) yield Item.BoxI({ id = idField(obj), x = x, y = y, w = w, h = h,
                            color = color, alpha = alphaField(obj), z = zField(obj), outline = outline })

    def circleFromJson(loc: String, obj: Map[String, Json]): Result[String, Item] =
        forM (
            x     <- floatField(loc, "x", obj);
            y     <- floatField(loc, "y", obj);
            r     <- floatField(loc, "r", obj);
            color <- colorField(loc, "color", obj)
        ) yield Item.CircleI({ id = idField(obj), x = x, y = y, r = r,
                               color = color, alpha = alphaField(obj), z = zField(obj) })

    def lineFromJson(loc: String, obj: Map[String, Json]): Result[String, Item] =
        forM (
            x1    <- floatField(loc, "x1", obj);
            y1    <- floatField(loc, "y1", obj);
            x2    <- floatField(loc, "x2", obj);
            y2    <- floatField(loc, "y2", obj);
            color <- colorField(loc, "color", obj)
        ) yield Item.LineI({ id = idField(obj), a = { x = x1, y = y1 }, b = { x = x2, y = y2 },
                             width = JsonCodec.floatOr("width", 1.0, obj),
                             color = color, alpha = alphaField(obj), z = zField(obj) })

    def textFromJson(loc: String, obj: Map[String, Json]): Result[String, Item] =
        forM (
            x       <- floatField(loc, "x", obj);
            y       <- floatField(loc, "y", obj);
            content <- stringField(loc, "text", obj);
            color   <- colorField(loc, "color", obj)
        ) yield Item.TextI({ id = idField(obj), x = x, y = y,
                             size = JsonCodec.floatOr("size", 8.0, obj),
                             text = content, color = color, z = zField(obj) })

    def spriteFromJson(loc: String, obj: Map[String, Json]): Result[String, Item] =
        forM (
            x       <- floatField(loc, "x", obj);
            y       <- floatField(loc, "y", obj);
            w       <- floatField(loc, "w", obj);
            h       <- floatField(loc, "h", obj);
            texture <- stringField(loc, "texture", obj)
        ) yield Item.SpriteI({ id = idField(obj), x = x, y = y, w = w, h = h,
                               texture = texture, alpha = alphaField(obj), z = zField(obj) })

    /// 必須の数値フィールド。無い・数値でないは、どの item のどのキーかが分かる Err。
    def floatField(loc: String, key: String, obj: Map[String, Json]): Result[String, Float64] =
        match Map.get(key, obj) {
            case None       => Err("${loc}: ${key} がありません")
            case Some(json) => JsonCodec.expectFloat(json) |> Option.toOk("${loc}: ${key} が数値ではありません")
        }

    /// 必須の文字列フィールド。
    def stringField(loc: String, key: String, obj: Map[String, Json]): Result[String, String] =
        match Map.get(key, obj) {
            case None       => Err("${loc}: ${key} がありません")
            case Some(json) => JsonCodec.expectString(json) |> Option.toOk("${loc}: ${key} が文字列ではありません")
        }

    /// 色フィールド。省略は白 (text の契約に合わせ、他の種類も同じ既定にする)。
    /// 表記の解釈は ui.json と同じ UiDoc.colorOf に寄せる (色方言を増やさない)。
    def colorField(loc: String, key: String, obj: Map[String, Json]): Result[String, Color] =
        match Map.get(key, obj) {
            case None       => Ok({ r = 1.0f32, g = 1.0f32, b = 1.0f32 })
            case Some(json) => UiDoc.colorOf(Map.empty(), key, json)
                |> Result.mapErr(_ -> "${loc}: ${key} は \"#rrggbb\" の形で書いてください")
        }

    /// outline は省略可 (無ければ枠線なし)。
    def outlineField(loc: String, obj: Map[String, Json]): Result[String, Option[Color]] =
        match Map.get("outline", obj) {
            case None       => Ok(None)
            case Some(json) => UiDoc.colorOf(Map.empty(), "outline", json)
                |> Result.map(color -> Some(color))
                |> Result.mapErr(_ -> "${loc}: outline は \"#rrggbb\" の形で書いてください")
        }

    def idField(obj: Map[String, Json]): Option[String] =
        Map.get("id", obj) |> Option.flatMap(JsonCodec.expectString)

    def alphaField(obj: Map[String, Json]): Float32 =
        JsonCodec.floatOr("alpha", 1.0, obj) |> Float64.truncateToFloat32

    def zField(obj: Map[String, Json]): Int32 =
        JsonCodec.intOr("z", 0, obj)

    // ════════════════════════════════════════════════════════
    // 外接矩形 (純関数 — テスト対象)
    // ════════════════════════════════════════════════════════

    /// 描き物 1 個の外接矩形 (design 座標)。応答の rects に使う。
    // WhyNot: text の幅はフォントを見ない 0.6em/字 の概算 — rects は編集画面のクリック
    // 当たり枠用途で、正確な字幅のためだけに rectOf へ atlas を配管する価値がないため。
    pub def rectOf(item: Item): Rect2.Rect2 =
        match item {
            case Item.BoxI(box)       =>
                { position = { x = box#x, y = box#y }, size = { x = box#w, y = box#h } }
            case Item.CircleI(circle) =>
                { position = { x = circle#x - circle#r, y = circle#y - circle#r },
                  size = { x = circle#r * 2.0, y = circle#r * 2.0 } }
            case Item.LineI(line)     =>
                boundsOf(Render.lineQuad(line#a, line#b, line#width))
            case Item.TextI(text)     =>
                { position = { x = text#x, y = text#y },
                  size = { x = text#size * 0.6 * Int32.toFloat64(String.length(text#text)), y = text#size } }
            case Item.SpriteI(sprite) =>
                { position = { x = sprite#x, y = sprite#y }, size = { x = sprite#w, y = sprite#h } }
        }

    /// 描き物の id (無名は None — rects に載せない)。
    pub def idOf(item: Item): Option[String] =
        match item {
            case Item.BoxI(box)       => box#id
            case Item.CircleI(circle) => circle#id
            case Item.LineI(line)     => line#id
            case Item.TextI(text)     => text#id
            case Item.SpriteI(sprite) => sprite#id
        }

    /// 頂点列の外接矩形。空列は 0 寸の矩形 (lineQuad は常に 4 点返すので実際は来ない)。
    def boundsOf(vertices: List[Vec2.Vec2]): Rect2.Rect2 =
        match vertices {
            case Nil          => { position = Vec2.zero(), size = Vec2.zero() }
            case first :: rest =>
                let low  = rest |> List.foldLeft((acc, v) ->
                    { x = Float64.min(acc#x, v#x), y = Float64.min(acc#y, v#y) }, first);
                let high = rest |> List.foldLeft((acc, v) ->
                    { x = Float64.max(acc#x, v#x), y = Float64.max(acc#y, v#y) }, first);
                { position = low, size = Vec2.sub(high, low) }
        }

    // ════════════════════════════════════════════════════════
    // 描画 → 応答
    // ════════════════════════════════════════════════════════

    /// プロジェクト設定とフォントを引いてから絵と応答を組む。文字が 1 つも無くても
    /// ラスタライザが TTF を 1 本要求するため、無いときは ok:false で理由を返す
    /// (PreviewHitbox と同じ流儀)。
    def preview(dir: String, caches: Caches.Caches, obj: Map[String, Json],
                items: List[Item], scale: Int32): (Int32, Json) \ IO =
        HeadlessFont.ensureHeadless();
        match ProjectCtx.load(dir) {
            case Err(message) => (200, failJson("project.json: ${message}"))
            case Ok(ctx)      =>
                let fonts = ProjectCtx.fontSetup(Nil, dir, caches, ctx);
                match fonts#primary {
                    case None          =>
                        (200, failJson(Option.getWithDefault("no font available for preview", List.head(fonts#warnings))))
                    case Some(primary) =>
                        (200, okJson(caches, ctx, primary, fonts#warnings, obj, items, scale))
                }
        }

    /// 宣言列を描いて成功応答を組む。manifest に無いテクスチャの sprite は描かず、
    /// textureSetup の warning で編集画面へ伝える (プレビュー全体は止めない)。
    def okJson(caches: Caches.Caches, ctx: ProjectCtx.Ctx, primary: {path = String, atlas = FontAtlas},
               fontWarnings: List[String], obj: Map[String, Json], items: List[Item], scale: Int32): Json \ IO =
        let design = designOf(obj, ctx);
        let designVec: Vec2.Vec2 = { x = Int32.toFloat64(design#w), y = Int32.toFloat64(design#h) };
        let usedTextures = items |> List.filterMap(item -> match item {
            case Item.SpriteI(sprite) => Some(sprite#texture)
            case _                    => None
        });
        let textures = ProjectCtx.textureSetup(usedTextures, caches, ctx);
        let textureInfoOf = name -> Map.get(name, textures#infos);
        let placed = items |> List.flatMap(item -> placedOf(textureInfoOf, primary#atlas, item));
        let (drawables, polygons) = Render.drawWith(textureInfoOf, placed);
        let image = SoftRaster.renderToImage({
            drawables = drawables, polygons = polygons,
            design = designVec, scale = scale, background = ctx#clearColor,
            texturePath = ProjectCtx.texturePaths(ctx),
            fontTtf = primary#path, fontAtlas = primary#atlas,
            outPath = "" });
        JObject(Map#{
            "ok"       => JBool(true),
            "png"      => JString(PngBase64.encode(image)),
            "width"    => JNumber(JsonCodec.intToBd(image.getWidth())),
            "height"   => JNumber(JsonCodec.intToBd(image.getHeight())),
            "scale"    => JNumber(JsonCodec.intToBd(scale)),
            "design"   => JObject(Map#{
                "w" => JNumber(JsonCodec.intToBd(design#w)),
                "h" => JNumber(JsonCodec.intToBd(design#h))
            }),
            "rects"    => rectsJson(items),
            "warnings" => JsonCodec.encodeList(warning -> JString(warning), fontWarnings ::: textures#warnings),
            "error"    => JNull
        })

    /// キャンバス寸法。body の design {w, h} が無い・欠けたキーは project.json の設計解像度で埋める。
    def designOf(obj: Map[String, Json], ctx: ProjectCtx.Ctx): {w = Int32, h = Int32} =
        let designObj = Map.get("design", obj)
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.getWithDefault(Map.empty());
        { w = JsonCodec.intOr("w", ctx#designW, designObj),
          h = JsonCodec.intOr("h", ctx#designH, designObj) }

    /// 描き物 1 個の絵。宣言 (design 座標・左上原点) を Render の語彙へ写す。
    def placedOf(textureInfoOf: String -> Option[GameEngine.TextureInfo],
                 atlas: FontAtlas, item: Item): List[Render.PlacedItem] =
        match item {
            case Item.BoxI(box)       =>
                let body = Render.box({ x = box#w, y = box#h }, box#color, box#z)
                    |> Render.fade(box#alpha);
                let framed = match box#outline {
                    case None        => body
                    case Some(color) => body |> Render.outline(color, 1.0)
                };
                ({ at = { x = box#x, y = box#y }, item = framed }) :: Nil
            case Item.CircleI(circle) =>
                let filled = Render.circleAt({ x = circle#x, y = circle#y }, circle#r, circle#color, circle#z);
                ({ item = Render.fade(circle#alpha, filled#item) | filled }) :: Nil
            case Item.LineI(line)     =>
                let seg = Render.lineSeg(line#a, line#b, line#width, line#color, line#z);
                ({ item = Render.fade(line#alpha, seg#item) | seg }) :: Nil
            case Item.TextI(text)     =>
                ({ at = { x = text#x, y = text#y },
                   item = Render.textTinted(text#text, atlas, text#size, text#color, text#z) }) :: Nil
            case Item.SpriteI(sprite) => match textureInfoOf(sprite#texture) {
                // manifest に無い・読めないテクスチャ: textureSetup が warnings に書くので、ここは飛ばすだけ。
                case None       => Nil
                case Some(info) =>
                    // WhyNot: smart constructor でなく Item.Sprite を直接組む — 宣言の w×h へ
                    // 合わせる伸縮は縦横で倍率が違い、一様倍率しか無い Render.scaled では書けない。
                    ({ at = { x = sprite#x + sprite#w / 2.0, y = sprite#y + sprite#h / 2.0 },
                       item = Render.Item.Sprite({
                           texture = sprite#texture, tint = { r = 1.0f32, g = 1.0f32, b = 1.0f32 },
                           alpha = sprite#alpha,
                           scale = { x = sprite#w / info#width, y = sprite#h / info#height },
                           rotation = 0.0, centered = true, flipH = false, flipV = false,
                           regionRect = None, zIndex = sprite#z,
                           blend = DrawCmd.BlendMode.Normal }) }) :: Nil
            }
        }

    // ════════════════════════════════════════════════════════
    // 応答 JSON の組み立て
    // ════════════════════════════════════════════════════════

    /// id 付きの描き物だけを {id: [x, y, w, h]} に並べる。同じ id は後の物が勝つ。
    def rectsJson(items: List[Item]): Json =
        JObject(items
            |> List.filterMap(item -> idOf(item) |> Option.map(id -> (id, rectJson(rectOf(item)))))
            |> List.toMap)

    def rectJson(rect: Rect2.Rect2): Json =
        JArray(Vector#{num(rect#position#x), num(rect#position#y), num(rect#size#x), num(rect#size#y)})

    def num(value: Float64): Json =
        JNumber(JsonCodec.floatToBd(value))

    /// 内容側の失敗応答 (HTTP 200)。成功時と同じキーを並べ、編集画面が形で分岐しなくて済むようにする。
    def failJson(message: String): Json =
        JObject(Map#{
            "ok"       => JBool(false),
            "png"      => JNull,
            "rects"    => JObject(Map.empty()),
            "warnings" => JArray(Vector#{}),
            "error"    => JObject(Map#{
                "message" => JString(message),
                "path"    => JNull
            })
        })

    /// 封筒不正 (400) の本文。他エンドポイントの失敗形と同じ {ok:false, error}。
    def envelopeError(message: String): Json =
        JObject(Map#{"ok" => JBool(false), "error" => JString(message)})
}
