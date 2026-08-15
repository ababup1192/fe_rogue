// PreviewSprite — POST /preview/sprite。編集中の *.sprite.json (メモリ上の doc、または
// プロジェクト内のファイル path) をヘッドレスで PNG に描いて返す。
//
// studio 統合の原則に従う: これは「スプライト専用エディタ」ではなく特化ビューの 1 適用例 —
// 状態を持たず、常にファイル (または編集中バッファ) が正。表現は Doc の本来の形 = マス目。
//
// モード:
//   - "frame": 指定コマ (sprite/frame) 1 枚の拡大レンダ。
//   - "sheet": 全スプライト×全コマ×全テーマのコンタクトシート (sprite を与えると 1 体に絞る —
//              クリップ再生の代替はこの「静止コマ列」で行う)。
// 色は意味色キー → 実色の resolver で解決する。リクエストの themes ([{name?, colors:{key:"#rrggbb"}}])
// が資産のテーマに相当し、無ければ既定 1 テーマ (キーごとの決定的なフォールバック色) で描く。
// legend のキーが colors に無いのは正常 (fail-open) — キーから導いた決定的な色で塗る。
// 失敗の返し分けは PreviewUi と同じ: 封筒が壊れているときだけ HTTP 400、
// ドキュメント側の問題は HTTP 200 の ok:false + error{message, path}。
mod PreviewSprite {
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JString, JNumber, JBool, JNull}

    /// リクエストボディを解いて (HTTP status, 応答 JSON) を作る。
    /// body: {path?, doc?, mode?, sprite?, frame?, scale?, themes?}。doc が path より優先。
    pub def respond(dir: String, caches: Caches.Caches, body: String): (Int32, Json) \ IO =
        match (DocJson.parse(body) |> Option.flatMap(JsonCodec.expectObject)) {
            case None      => (400, envelopeError("body must be a JSON object {path?, doc?, mode?, sprite?, frame?, scale?, themes?}"))
            case Some(obj) =>
                let scale = PreviewUi.clampScale(JsonCodec.intOr("scale", 4, obj));
                let spriteOpt = Map.get("sprite", obj) |> Option.flatMap(JsonCodec.expectString);
                let frameOpt = Map.get("frame", obj) |> Option.flatMap(JsonCodec.expectString);
                let mode = Map.get("mode", obj) |> Option.flatMap(JsonCodec.expectString)
                    |> Option.getWithDefault(if (Option.nonEmpty(frameOpt)) "frame" else "sheet");
                match PreviewUi.docJsonOf(dir, obj) {
                    case Err(PreviewUi.BadRequest.Envelope(message)) => (400, envelopeError(message))
                    case Err(PreviewUi.BadRequest.Doc(message))      => (200, failJson(message))
                    case Ok(docJson)                                 =>
                        match PxSpriteDoc.fromJsonValue(docJson) {
                            case None      => (200, failJson("doc is not a JSON object (sprite.json)"))
                            case Some(doc) =>
                                if (Map.isEmpty(doc#sprites))
                                    (200, failJson("no sprites in doc (sprites が空か全て壊れている)"))
                                else
                                    render(dir, caches, doc, {
                                        mode = mode, sprite = spriteOpt, frame = frameOpt,
                                        scale = scale, themes = themesOf(obj) })
                        }
                }
        }

    // ════════════════════════════════════════════════════════
    // テーマ (意味色キー → 実色)
    // ════════════════════════════════════════════════════════

    /// themes: [{name?, colors: {key: "#rrggbb"}}] → (名前, resolver) の列。
    /// 無ければ既定 1 テーマ。壊れた要素は捨てる (全滅したら既定へ)。
    def themesOf(obj: Map[String, Json]): List[(String, String -> Color)] =
        let parsed = match Map.get("themes", obj) {
            case Some(JArray(entries)) => entries
                |> Vector.toList
                |> List.zipWithIndex
                |> List.filterMap(entry -> {
                    let (i, json) = entry;
                    JsonCodec.expectObject(json) |> Option.map(theme -> {
                        let name = Map.get("name", theme) |> Option.flatMap(JsonCodec.expectString)
                            |> Option.getWithDefault("theme${i}");
                        let colors = Map.get("colors", theme)
                            |> Option.flatMap(JsonCodec.expectObject)
                            |> Option.map(colorMapOf)
                            |> Option.getWithDefault(Map.empty());
                        (name, resolverOf(colors))
                    })
                })
            case _ => Nil
        };
        if (List.isEmpty(parsed)) ("default", resolverOf(Map.empty())) :: Nil else parsed

    /// {"key": "#rrggbb"} → Map[String, Color]。読めない値は捨てる (fail-open)。
    def colorMapOf(colors: Map[String, Json]): Map[String, Color] =
        colors |> Map.toList |> List.filterMap(entry -> {
            let (key, json) = entry;
            JsonCodec.expectString(json) |> Option.flatMap(hexColor) |> Option.map(c -> (key, c))
        }) |> List.toMap

    /// "#rrggbb" → Color。# 無し・桁違いは None。
    def hexColor(text: String): Option[Color] =
        let hex = if (String.startsWith(prefix = "#", text)) String.dropLeft(1, text) else text;
        if (String.length(hex) != 6) None
        else forM (
            r <- Int32.parse(16, String.takeLeft(2, hex)) |> Result.toOption;
            g <- Int32.parse(16, String.slice(start = 2, end = 4, hex)) |> Result.toOption;
            b <- Int32.parse(16, String.dropLeft(4, hex)) |> Result.toOption
        ) yield ({ r = Int32.toFloat64(r) / 255.0,
                   g = Int32.toFloat64(g) / 255.0,
                   b = Int32.toFloat64(b) / 255.0 }: Color)

    /// colors に無いキーは決定的なフォールバック色 (キーの文字列ハッシュから導く —
    /// 同じキーは常に同じ色なので、テーマ未指定でも部位の区別がつく)。
    def resolverOf(colors: Map[String, Color]): String -> Color =
        key -> match Map.get(key, colors) {
            case Some(c) => c
            case None    => fallbackColor(key)
        }

    /// キー → 落ち着いた決定的な色。ハッシュの下位ビットで RGB を 0.25..0.85 に散らす。
    pub def fallbackColor(key: String): Color =
        let h = String.toList(key) |> List.foldLeft((acc, ch) ->
            Int32.bitwiseAnd(acc * 31 + Char.toBmpCodePoint(ch), 16777215), 7);
        let chan = shift -> {
            let v = Int32.bitwiseAnd(Int32.logicalRightShift(dist = shift, h), 255);
            0.25 + 0.6 * Int32.toFloat64(v) / 255.0
        };
        { r = chan(16), g = chan(8), b = chan(0) }

    // ════════════════════════════════════════════════════════
    // レイアウト (純粋 — テストの入口)
    // ════════════════════════════════════════════════════════

    /// セル 1 個 = (スプライト名, コマ名, テーマ index)。sheet の並び:
    /// 行 = スプライト、列 = コマ×テーマ (コマ内でテーマが隣り合う)。
    pub type alias Cell = { sprite = String, frame = String, theme = Int32 }

    /// sheet の全セル (sprite で絞れる)。スプライト・コマとも名前順で決定的。
    pub def sheetCells(doc: PxSpriteDoc.Doc, spriteFilter: Option[String], themeCount: Int32): List[List[Cell]] =
        doc#sprites |> Map.toList
            |> List.filter(entry -> {
                let (name, _) = entry;
                match spriteFilter { case None => true case Some(s) => s == name }
            })
            |> List.map(entry -> {
                let (name, sp) = entry;
                sp#frames |> Map.toList |> List.flatMap(fr -> {
                    let (frame, _) = fr;
                    List.range(0, themeCount) |> List.map(t ->
                        ({ sprite = name, frame = frame, theme = t }: Cell))
                })
            })

    /// 格子寸法 (w = 最長行, h = 行数)。
    pub def gridSize(doc: PxSpriteDoc.Doc, sprite: String, frame: String): (Int32, Int32) =
        match Map.get(sprite, doc#sprites) {
            case None     => (0, 0)
            case Some(sp) => match Map.get(frame, sp#frames) {
                case None       => (0, 0)
                case Some(rows) =>
                    (rows |> List.foldLeft((acc, row) -> Int32.max(acc, String.length(row)), 0),
                     List.length(rows))
            }
        }

    // ════════════════════════════════════════════════════════
    // 描画 → 応答
    // ════════════════════════════════════════════════════════

    type alias Req = { mode = String, sprite = Option[String], frame = Option[String],
                       scale = Int32, themes = List[(String, String -> Color)] }

    def render(dir: String, caches: Caches.Caches, doc: PxSpriteDoc.Doc, req: Req): (Int32, Json) \ IO =
        HeadlessFont.ensureHeadless();
        match ProjectCtx.load(dir) {
            case Err(message) => (200, failJson("project.json: ${message}"))
            case Ok(ctx)      =>
                let fonts = ProjectCtx.fontSetup(Nil, dir, caches, ctx);
                match fonts#primary {
                    case None          =>
                        (200, failJson(Option.getWithDefault("no font available for preview", List.head(fonts#warnings))))
                    case Some(primary) =>
                        let bgc: Color = { r = 0.09, g = 0.10, b = 0.11 };
                        let built =
                            if (req#mode == "frame") buildFrame(doc, req, primary#atlas)
                            else buildSheet(doc, req, primary#atlas);
                        match built {
                            case None => (200, failJson("sprite/frame not found (mode=${req#mode})"))
                            case Some((design, items)) =>
                                let (drawables, polygons) =
                                    Render.drawWith(_ -> (None: Option[GameEngine.TextureInfo]), items);
                                let image = SoftRaster.renderToImage({
                                    drawables = drawables, polygons = polygons,
                                    design = design, scale = 1, background = bgc,
                                    texturePath = Map.empty(),
                                    fontTtf = primary#path, fontAtlas = primary#atlas,
                                    // マス目を 1 個ずつ塗る絵なので面の縁はならさない — ならすと
                                    // doc の legend に無い中間色がマスの境に湧き、編集画面の色と
                                    // 実機の色が食い違う。見出しの字は読めないと困るので残す。
                                    outPath = "", shapeAntialias = false, textAntialias = true });
                                (200, JObject(Map#{
                                    "ok"       => JBool(true),
                                    "png"      => JString(PngBase64.encode(image)),
                                    "width"    => JNumber(JsonCodec.intToBd(image.getWidth())),
                                    "height"   => JNumber(JsonCodec.intToBd(image.getHeight())),
                                    "scale"    => JNumber(JsonCodec.intToBd(req#scale)),
                                    "mode"     => JString(req#mode),
                                    "themes"   => JsonCodec.encodeList(t -> { let (name, _) = t; JString(name) }, req#themes),
                                    "sprites"  => spritesMeta(doc),
                                    "warnings" => JsonCodec.encodeList(w -> JString(w), fonts#warnings),
                                    "error"    => JNull
                                }))
                        }
                }
        }

    /// "frame" モード: 1 コマを scale 倍で中央に置く (余白 2 セル)。テーマは先頭を使う。
    def buildFrame(doc: PxSpriteDoc.Doc, req: Req,
                   _atlas: FontAtlas): Option[(Vec2.Vec2, List[Render.PlacedItem])] =
        forM (
            sprite <- orElse(req#sprite, firstSprite(doc));
            frame  <- orElse(req#frame, firstFrame(doc, sprite));
            resolver <- List.head(req#themes) |> Option.map(t -> { let (_, r) = t; r })
        ) yield {
            let (w, h) = gridSize(doc, sprite, frame);
            let s = Int32.toFloat64(req#scale);
            let pad = 2.0 * s;
            let anchor = anchorOf(doc, sprite);
            let design: Vec2.Vec2 = { x = pad * 2.0 + Int32.toFloat64(w) * s,
                                      y = pad * 2.0 + Int32.toFloat64(h) * s };
            let at: Vec2.Vec2 = { x = pad + anchor#x * s, y = pad + anchor#y * s };
            (design, PxSprite.draw(doc, sprite, frame, at, false, req#scale, resolver, 10))
        }

    /// "sheet" モード: 行 = スプライト (左に名前ラベル)、列 = コマ×テーマ。
    /// セル寸法は全コマの最大格子で揃える (格子はスプライトごとに違うため)。
    def buildSheet(doc: PxSpriteDoc.Doc, req: Req,
                   atlas: FontAtlas): Option[(Vec2.Vec2, List[Render.PlacedItem])] =
        let rows = sheetCells(doc, req#sprite, List.length(req#themes));
        let cells = List.flatten(rows);
        if (List.isEmpty(cells)) None
        else {
            let s = Int32.toFloat64(req#scale);
            let (maxW, maxH) = cells |> List.foldLeft((acc, c) -> {
                let (aw, ah) = acc;
                let (w, h) = gridSize(doc, c#sprite, c#frame);
                (Int32.max(aw, w), Int32.max(ah, h))
            }, (1, 1));
            let gap = 4.0;
            let label = 64.0;
            let cellW = Int32.toFloat64(maxW) * s + gap;
            let cellH = Int32.toFloat64(maxH) * s + gap;
            let cols = rows |> List.foldLeft((acc, r) -> Int32.max(acc, List.length(r)), 1);
            let design: Vec2.Vec2 = {
                x = label + gap + Int32.toFloat64(cols) * cellW + gap,
                y = gap + Int32.toFloat64(List.length(rows)) * cellH + gap };
            let items = rows |> List.zipWithIndex |> List.flatMap(rowEntry -> {
                let (rowIdx, row) = rowEntry;
                let y0 = gap + Int32.toFloat64(rowIdx) * cellH;
                let name = match List.head(row) { case Some(c) => c#sprite case None => "" };
                let labelItem: Render.PlacedItem =
                    { at = { x = gap, y = y0 + cellH / 2.0 },
                      item = Render.textTinted(name, atlas, 10.0,
                          { r = 0.85, g = 0.85, b = 0.80 }, 50) };
                let cellItems = row |> List.zipWithIndex |> List.flatMap(cellEntry -> {
                    let (colIdx, cell) = cellEntry;
                    let resolver = req#themes |> List.drop(cell#theme) |> List.head
                        |> Option.map(t -> { let (_, r) = t; r })
                        |> Option.getWithDefault(k -> fallbackColor(k));
                    let anchor = anchorOf(doc, cell#sprite);
                    let at: Vec2.Vec2 = {
                        x = label + gap + Int32.toFloat64(colIdx) * cellW + anchor#x * s,
                        y = y0 + anchor#y * s };
                    PxSprite.draw(doc, cell#sprite, cell#frame, at, false, req#scale, resolver, 10)
                });
                labelItem :: cellItems
            });
            Some((design, items))
        }

    /// 前者があれば前者、無ければ後者。
    def orElse(a: Option[a], b: Option[a]): Option[a] =
        match a { case Some(_) => a case None => b }

    def anchorOf(doc: PxSpriteDoc.Doc, sprite: String): Vec2.Vec2 =
        Map.get(sprite, doc#sprites)
            |> Option.map(sp -> sp#anchor)
            |> Option.getWithDefault({ x = 0.0, y = 0.0 })

    def firstSprite(doc: PxSpriteDoc.Doc): Option[String] =
        doc#sprites |> Map.toList |> List.head |> Option.map(entry -> { let (n, _) = entry; n })

    def firstFrame(doc: PxSpriteDoc.Doc, sprite: String): Option[String] =
        Map.get(sprite, doc#sprites)
            |> Option.flatMap(sp -> sp#frames |> Map.toList |> List.head)
            |> Option.map(entry -> { let (n, _) = entry; n })

    /// 応答メタ: [{name, anchor{x,y}, frames: [{name, w, h}]}] — エディタの一覧・逆引きの種。
    def spritesMeta(doc: PxSpriteDoc.Doc): Json =
        JsonCodec.encodeList(entry -> {
            let (name, sp) = entry;
            JObject(Map#{
                "name"   => JString(name),
                "anchor" => JObject(Map#{
                    "x" => JNumber(JsonCodec.floatToBd(sp#anchor#x)),
                    "y" => JNumber(JsonCodec.floatToBd(sp#anchor#y))
                }),
                "frames" => JsonCodec.encodeList(fr -> {
                    let (fname, _) = fr;
                    let (w, h) = gridSize(doc, name, fname);
                    JObject(Map#{
                        "name" => JString(fname),
                        "w"    => JNumber(JsonCodec.intToBd(w)),
                        "h"    => JNumber(JsonCodec.intToBd(h))
                    })
                }, sp#frames |> Map.toList)
            })
        }, doc#sprites |> Map.toList)

    /// ドキュメント側の失敗応答 (HTTP 200)。形は PreviewFx と同じ。
    def failJson(message: String): Json =
        let (pathOpt, text) = PreviewUi.splitNodePath(message);
        JObject(Map#{
            "ok"       => JBool(false),
            "png"      => JNull,
            "warnings" => JArray(Vector#{}),
            "error"    => JObject(Map#{
                "message" => JString(text),
                "path"    => match pathOpt { case None => JNull case Some(p) => JString(p) }
            })
        })

    /// 封筒不正 (400) の本文。
    def envelopeError(message: String): Json =
        JObject(Map#{"ok" => JBool(false), "error" => JString(message)})
}
