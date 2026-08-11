// PreviewHitbox — POST /preview/hitbox。hitbox.json (メモリ上の doc、またはプロジェクト内の
// ファイル path) の当たり形を、エンティティごとのマス目に並べた 1 枚の PNG にして返す。
// キャンバス寸法 (design) はゲームの設計解像度ではなくマス目全体の大きさ —
// 当たり形は数 px の小物が多く、ゲーム画面の縮尺に置くと読めないため。
// 失敗の返し分けは PreviewUi と同じ: 封筒不正だけ HTTP 400、ドキュメント側の問題は 200 の ok:false。

mod PreviewHitbox {
    import java.awt.image.BufferedImage

    use Hit.HitShape
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JString, JNumber, JBool, JNull}

    /// リクエストボディを解いて (HTTP status, 応答 JSON) を作る。
    pub def respond(dir: String, caches: Caches.Caches, body: String): (Int32, Json) \ IO =
        match (DocJson.parse(body) |> Option.flatMap(JsonCodec.expectObject)) {
            case None      => (400, envelopeError("body must be a JSON object {path?, doc?, scale?}"))
            case Some(obj) =>
                let scale = PreviewUi.clampScale(JsonCodec.intOr("scale", 1, obj));
                match PreviewUi.docJsonOf(dir, obj) {
                    case Err(PreviewUi.BadRequest.Envelope(message)) => (400, envelopeError(message))
                    case Err(PreviewUi.BadRequest.Doc(message))      => (200, failJson(message))
                    case Ok(docJson) => match HitDoc.parse(docJson) {
                        case Err(e)    => (200, failJson(DocJson.describe(e)))
                        case Ok(sheet) => preview(dir, caches, docJson, sheet, scale)
                    }
                }
        }

    /// プロジェクト設定とフォントを引いてから絵と応答を組む。フォントはラベル用と
    /// ラスタライザ用の両方 — ラスタライザが TTF を必ず 1 本要求するため、プロジェクトに
    /// TTF が 1 本も無いときはラベル省略でなく ok:false で理由を返す。
    def preview(dir: String, caches: Caches.Caches, docJson: Json, sheet: HitDoc.Sheet, scale: Int32): (Int32, Json) \ IO =
        HeadlessFont.ensureHeadless();
        match ProjectCtx.load(dir) {
            case Err(message) => (200, failJson("project.json: ${message}"))
            case Ok(ctx)      =>
                let fonts = ProjectCtx.fontSetup(Nil, dir, caches, ctx);
                match fonts#primary {
                    case None          =>
                        (200, failJson(Option.getWithDefault("no font available for preview", List.head(fonts#warnings))))
                    case Some(primary) =>
                        (200, okJson(ctx, primary, fonts#warnings, docJson, sheet, scale))
                }
        }

    /// マス目を組んで描き、成功応答を作る。エンティティは名前順 (Map のキー順) で並べる。
    def okJson(ctx: ProjectCtx.Ctx, primary: {path = String, atlas = FontAtlas},
               warnings: List[String], docJson: Json, sheet: HitDoc.Sheet, scale: Int32): Json \ IO =
        let entities = Map.toList(sheet);
        let n = List.length(entities);
        let columns = columnsOf(n);
        let side = cellSideOf(sheet);
        let design = designOf(n, columns, side);
        let (docNote, entityNotes) = notesOf(docJson);
        let indexed = List.zip(List.range(0, n), entities);
        let items = indexed |> List.flatMap(match (index, (name, shapes)) ->
            cellItems(primary#atlas, cellRectOf(index, columns, side), name, shapes));
        let (drawables, polygons) = Render.draw(items);
        let image = SoftRaster.renderToImage({
            drawables = drawables, polygons = polygons,
            design = design, scale = scale, background = ctx#clearColor,
            texturePath = Map.empty(),
            fontTtf = primary#path, fontAtlas = primary#atlas,
            outPath = "" });
        JObject(Map#{
            "ok"       => JBool(true),
            "png"      => JString(PngBase64.encode(image)),
            "width"    => JNumber(JsonCodec.intToBd(image.getWidth())),
            "height"   => JNumber(JsonCodec.intToBd(image.getHeight())),
            "scale"    => JNumber(JsonCodec.intToBd(scale)),
            "design"   => JObject(Map#{"w" => num(design#x), "h" => num(design#y)}),
            "note"     => optString(docNote),
            "entities" => JArray(indexed |> List.map(match (index, (name, shapes)) ->
                              entityJson(Map.get(name, entityNotes),
                                         cellRectOf(index, columns, side), name, shapes))
                              |> List.toVector),
            "gaps"     => JsonCodec.encodeList(gap -> JString(gap), HitDoc.gaps(Nil, sheet)),
            "warnings" => JsonCodec.encodeList(warning -> JString(warning), warnings),
            "error"    => JNull
        })

    // ════════════════════════════════════════════════════════
    // マス目の割り付け (純関数 — テスト対象)
    // ════════════════════════════════════════════════════════

    /// セルの中の余白 (px)。形がセル枠に触れると隣のセルと溶けて見えるので離す。
    def cellMargin(): Float64 = 16.0

    /// セル辺の最小 (px)。小さな形しか無くても名前ラベルが収まる広さは確保する。
    def minCellSide(): Float64 = 48.0

    /// n 個を並べる列数。正方形に近いマス目になる ceil(sqrt(n))。
    pub def columnsOf(n: Int32): Int32 =
        if (n <= 1) 1 else columnsFrom(1, n)

    /// c×c マスに n 個が収まる最小の c。
    def columnsFrom(c: Int32, n: Int32): Int32 =
        if (c * c >= n) c else columnsFrom(c + 1, n)

    /// 形 1 個が持ち主の中心からどこまで届くか (x/y 方向の遠い方、px)。
    pub def reachOf(shape: HitShape): Float64 =
        match shape {
            case HitShape.CircleH(c) => Float64.max(Float64.abs(c#dx), Float64.abs(c#dy)) + c#r
            case HitShape.BoxH(b)    => Float64.max(Float64.abs(b#dx) + b#w / 2.0,
                                                    Float64.abs(b#dy) + b#h / 2.0)
        }

    /// セル 1 辺 (px)。全エンティティ中で一番遠くまで届く形が余白込みで収まる広さ、最小 48。
    /// 全セル同寸にするのは、セルごとの縮尺差で形の大小を読み違えないため。
    pub def cellSideOf(sheet: HitDoc.Sheet): Float64 =
        let maxReach = sheet
            |> Map.valuesOf
            |> List.flatten
            |> List.map(reachOf)
            |> List.foldLeft(Float64.max, 0.0);
        Float64.max(minCellSide(), maxReach * 2.0 + cellMargin())

    /// index 番目 (名前順・0 始まり) のセル矩形 (design 座標)。
    pub def cellRectOf(index: Int32, columns: Int32, side: Float64): Rect2.Rect2 =
        { position = { x = Int32.toFloat64(Int32.modulo(index, columns)) * side,
                       y = Int32.toFloat64(index / columns) * side },
          size = { x = side, y = side } }

    /// マス目全体のキャンバス寸法。n = 0 でも 1 セルぶんは確保する (0px の PNG を作らない)。
    pub def designOf(n: Int32, columns: Int32, side: Float64): Vec2.Vec2 =
        let rows = Int32.max(1, (n + columns - 1) / columns);
        { x = Int32.toFloat64(columns) * side, y = Int32.toFloat64(rows) * side }

    /// 中心 center に置いた形の外接矩形 (design 座標)。hitbox の座標系は
    /// 「エンティティ中心が原点・y 下が正」で画面座標と同じ向きなので、dx/dy はそのまま足せる。
    pub def shapeRectOf(center: Vec2.Vec2, shape: HitShape): Rect2.Rect2 =
        match shape {
            case HitShape.CircleH(c) =>
                { position = { x = center#x + c#dx - c#r, y = center#y + c#dy - c#r },
                  size = { x = c#r * 2.0, y = c#r * 2.0 } }
            case HitShape.BoxH(b) =>
                { position = { x = center#x + b#dx - b#w / 2.0, y = center#y + b#dy - b#h / 2.0 },
                  size = { x = b#w, y = b#h } }
        }

    // ════════════════════════════════════════════════════════
    // "//" 注釈の収集 (純関数 — テスト対象)
    // ════════════════════════════════════════════════════════

    /// 生 JSON から注釈を拾う (HitDoc は "//" キーをコメントとして読み飛ばすので、こちらで別途拾う)。
    /// トップの "//" が全体注釈、"hit" の中の "//名前" がそのエンティティの注釈。
    /// 名前の付かない "hit" 内の "//" はどのエンティティの物でもないので拾わない。
    pub def notesOf(docJson: Json): (Option[String], Map[String, String]) =
        let objOpt = JsonCodec.expectObject(docJson);
        let docNote = objOpt
            |> Option.flatMap(obj -> Map.get("//", obj))
            |> Option.flatMap(JsonCodec.expectString);
        let entityNotes = objOpt
            |> Option.flatMap(obj -> Map.get("hit", obj))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(hit -> hit
                |> Map.toList
                |> List.filterMap(match (key, value) ->
                    if (String.startsWith(prefix = "//", key) and String.length(key) > 2)
                        JsonCodec.expectString(value) |> Option.map(text -> (String.drop(2, key), text))
                    else None)
                |> List.toMap)
            |> Option.getWithDefault(Map.empty());
        (docNote, entityNotes)

    // ════════════════════════════════════════════════════════
    // セルの絵 (十字 → 形 → 名前ラベル)
    // ════════════════════════════════════════════════════════

    /// 形の塗り色。ゲーム側の H デバッグ表示 (半透明の赤) と同じ見た目に揃える。
    def hitColor(): Color = Color.hsv({ h = 0.0, s = 0.85, v = 1.00 })

    def crossColor(): Color = { r = 1.0f32, g = 1.0f32, b = 1.0f32 }
    def labelColor(): Color = { r = 0.85f32, g = 0.85f32, b = 0.85f32 }

    def zCross(): Int32 = 1
    def zShape(): Int32 = 2
    def zLabel(): Int32 = 3

    /// セル 1 個ぶんの描画物。十字 (原点の目印) の上に形を重ね、左上に名前を置く。
    def cellItems(atlas: FontAtlas, cell: Rect2.Rect2, name: String,
                  shapes: List[HitShape]): List[Render.PlacedItem] =
        let center = Rect2.center(cell);
        crossItems(center, cell#size#x)
            ::: List.flatMap(shape -> shapeItems(center, shape), shapes)
            ::: labelItems(atlas, cell, name)

    /// 原点 (エンティティ中心) を示す薄い十字。形が dx/dy でどれだけずれているかの物差しになる。
    def crossItems(center: Vec2.Vec2, side: Float64): List[Render.PlacedItem] =
        let arm = side * 0.35;
        (RawDraw.lineSeg({ x = center#x - arm, y = center#y },
                        { x = center#x + arm, y = center#y }, 1.0, crossColor(), zCross())
            :: RawDraw.lineSeg({ x = center#x, y = center#y - arm },
                              { x = center#x, y = center#y + arm }, 1.0, crossColor(), zCross())
            :: Nil)
            |> List.map(seg -> { item = Render.fade(0.25, seg#item) | seg })

    /// 形 1 個の絵。塗りは薄く、箱には枠線をつけて重なった箱どうしの輪郭を読めるようにする。
    def shapeItems(pos: Vec2.Vec2, shape: HitShape): List[Render.PlacedItem] =
        match shape {
            case HitShape.CircleH(c) =>
                let fill = RawDraw.circleAt(Vec2.add(pos, { x = c#dx, y = c#dy }), c#r, hitColor(), zShape());
                ({ item = Render.fade(0.35, fill#item) | fill }) :: Nil
            case HitShape.BoxH(b) =>
                let fill = RawDraw.boxAt(Vec2.add(pos, { x = b#dx, y = b#dy }),
                                        { x = b#w, y = b#h }, hitColor(), zShape());
                ({ item = fill#item |> Render.fade(0.35) |> Render.outline(hitColor(), 1.0) | fill }) :: Nil
        }

    /// セル左上のエンティティ名ラベル。
    def labelItems(atlas: FontAtlas, cell: Rect2.Rect2, name: String): List[Render.PlacedItem] =
        ({ at = Vec2.add(cell#position, { x = 2.0, y = 2.0 }),
           item = Render.textTinted(name, atlas, 7.0, labelColor(), zLabel()) }) :: Nil

    // ════════════════════════════════════════════════════════
    // 応答 JSON の組み立て
    // ════════════════════════════════════════════════════════

    /// エンティティ 1 件。rect はセル矩形、shapes には形ごとの外接矩形も添える
    /// (編集画面が形をクリックで選べるように)。
    def entityJson(note: Option[String], cell: Rect2.Rect2, name: String,
                   shapes: List[HitShape]): Json =
        let center = Rect2.center(cell);
        JObject(Map#{
            "name"   => JString(name),
            "note"   => optString(note),
            "rect"   => rectJson(cell),
            "shapes" => JArray(shapes |> List.map(shape -> shapeJson(center, shape)) |> List.toVector)
        })

    /// 形 1 件。宣言の値 (dx/dy と寸法) と、design 座標の外接矩形の両方を返す。
    def shapeJson(center: Vec2.Vec2, shape: HitShape): Json =
        match shape {
            case HitShape.CircleH(c) => JObject(Map#{
                "shape" => JString("circle"),
                "dx"    => num(c#dx), "dy" => num(c#dy), "r" => num(c#r),
                "rect"  => rectJson(shapeRectOf(center, shape))
            })
            case HitShape.BoxH(b) => JObject(Map#{
                "shape" => JString("box"),
                "dx"    => num(b#dx), "dy" => num(b#dy), "w" => num(b#w), "h" => num(b#h),
                "rect"  => rectJson(shapeRectOf(center, shape))
            })
        }

    def rectJson(rect: Rect2.Rect2): Json =
        JArray(Vector#{num(rect#position#x), num(rect#position#y), num(rect#size#x), num(rect#size#y)})

    def num(value: Float64): Json =
        JNumber(JsonCodec.floatToBd(value))

    def optString(opt: Option[String]): Json =
        match opt {
            case None    => JNull
            case Some(s) => JString(s)
        }

    /// ドキュメント側の失敗応答 (HTTP 200 で返す)。エラー文言の "at 位置: 本文" 分解は PreviewUi と共通。
    def failJson(message: String): Json =
        let (pathOpt, text) = PreviewUi.splitNodePath(message);
        JObject(Map#{
            "ok"       => JBool(false),
            "png"      => JNull,
            "note"     => JNull,
            "entities" => JNull,
            "gaps"     => JArray(Vector#{}),
            "warnings" => JArray(Vector#{}),
            "error"    => JObject(Map#{
                "message" => JString(text),
                "path"    => optString(pathOpt)
            })
        })

    /// 封筒不正 (400) の本文。Editor の他エンドポイントの失敗形と同じ {ok:false, error}。
    def envelopeError(message: String): Json =
        JObject(Map#{"ok" => JBool(false), "error" => JString(message)})
}
