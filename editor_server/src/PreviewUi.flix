// PreviewUi — POST /preview/ui。編集中の ui.json (メモリ上の doc、またはプロジェクト内の
// ファイル path) をヘッドレスで 1 枚の PNG に描き、レイアウト矩形とノード木を添えて返す。
// 失敗の返し分け: リクエストの封筒が壊れている (JSON でない / doc も path も無い) ときだけ
// HTTP 400。ドキュメント側の問題 (パース失敗・参照切れ等) は HTTP 200 の ok:false —
// 編集画面はタイピング途中の壊れた JSON を送り続けるので、それを HTTP エラーにしない。

mod PreviewUi {
    import java.awt.image.BufferedImage

    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JString, JNumber, JBool, JNull}

    /// リクエスト解釈の失敗種別。Envelope は 400、Doc は 200 の ok:false で返す。
    /// PreviewHitbox も同じ封筒 {path?, doc?, ...} を受けるので、ここの解釈を共用する。
    pub enum BadRequest {
        case Envelope(String)
        case Doc(String)
    }

    /// 絵をどの経路で作るか。StorePath = UiStore 投影 (hover が効く・通常)。
    /// FlexPath = UiDoc の静的経路 — UiStore が断る poly rotation/pivot 付きドキュメントの
    /// 逃げ道で、回転は正しく描けるが hover は効かない。
    enum DrawPath {
        case StorePath
        case FlexPath
    }

    /// リクエストボディを解いて (HTTP status, 応答 JSON) を作る。
    pub def respond(dir: String, body: String): (Int32, Json) \ IO =
        match (JsonCompat.parse(body) |> Option.flatMap(JsonCodec.expectObject)) {
            case None      => (400, envelopeError("body must be a JSON object {path?, doc?, hovered?, scale?}"))
            case Some(obj) =>
                let scale = clampScale(JsonCodec.intOr("scale", 1, obj));
                let hovered = Map.get("hovered", obj) |> Option.flatMap(JsonCodec.expectString);
                match docJsonOf(dir, obj) {
                    case Err(BadRequest.Envelope(message)) => (400, envelopeError(message))
                    case Err(BadRequest.Doc(message))      => (200, failJson(message))
                    case Ok(docJson)                       => preview(dir, docJson, hovered, scale)
                }
        }

    /// scale は 1..8 に収める (0 以下は真っ黒な点、大きすぎは巨大 PNG になるだけ)。
    pub def clampScale(scale: Int32): Int32 =
        Int32.max(1, Int32.min(8, scale))

    /// 描く対象のドキュメント JSON を決める。doc があれば path より優先する
    /// (編集中の未保存バッファがディスクの旧内容に負けないため)。
    pub def docJsonOf(dir: String, obj: Map[String, Json]): Result[BadRequest, Json] \ IO =
        match (Map.get("doc", obj), Map.get("path", obj) |> Option.flatMap(JsonCodec.expectString)) {
            case (Some(JString(text)), _) =>
                // 文字列で来たら編集中バッファの生テキストなので、ここで JSON として解く。
                JsonCompat.parse(text) |> Option.toOk(BadRequest.Doc("doc is not valid JSON"))
            case (Some(docJson), _)       => Ok(docJson)
            case (None, Some(relPath))    => match FileIndex.readInside(dir, relPath) {
                case Err(message) => Err(BadRequest.Doc(message))
                case Ok(content)  => JsonCompat.parse(String.trim(content))
                    |> Option.toOk(BadRequest.Doc("JSON parse failed: ${relPath}"))
            }
            case (None, None)             => Err(BadRequest.Envelope("either 'doc' or 'path' is required"))
        }

    /// プロジェクト設定を読み、ドキュメントを 2 経路 (描画用 UiSpec / 木情報用 UiDoc) でパースする。
    /// UiDoc.Spec を別途取るのは note/origin (エディタ向け情報) が UiSpec.Spec に無いため。
    def preview(dir: String, docJson: Json, hovered: Option[String], scale: Int32): (Int32, Json) \ IO =
        HeadlessFont.ensureHeadless();
        match ProjectCtx.load(dir) {
            case Err(message) => (200, failJson("project.json: ${message}"))
            case Ok(ctx)      =>
                let specRes = run { UiSpec.parseAt(dir, docJson) } with Fs.FileRead.runWithIO;
                let docRes  = run { UiDoc.parseAt(dir, docJson) } with Fs.FileRead.runWithIO;
                match (specRes, docRes) {
                    case (Ok(spec), Ok(docSpec)) =>
                        render(dir, ctx, spec, docSpec, hovered, scale, DrawPath.StorePath)
                    case (Err(e), Ok(docSpec))   =>
                        if (isRotationErr(e)) rotationFallback(dir, ctx, docJson, docSpec, hovered, scale, e)
                        else (200, failJson(JsonCompat.describe(e)))
                    case (_, Err(e))             => (200, failJson(JsonCompat.describe(e)))
                }
        }

    /// poly rotation/pivot 付きドキュメントの逃げ道。回転はレイアウト矩形を変えないので、
    /// rects と名前表は rotation/pivot を落とした写しの UiStore から取り、絵は Flex 経路が
    /// 回転込みで描く。写しでも通らなければ元のエラーをそのまま返す。
    def rotationFallback(dir: String, ctx: ProjectCtx.Ctx, docJson: Json, docSpec: UiDoc.Spec,
                         hovered: Option[String], scale: Int32,
                         original: Util.Json.JsonError): (Int32, Json) \ IO =
        let strippedRes = run { UiSpec.parseAt(dir, stripRotation(docJson)) } with Fs.FileRead.runWithIO;
        match strippedRes {
            case Ok(spec) => render(dir, ctx, spec, docSpec, hovered, scale, DrawPath.FlexPath)
            case Err(_)   => (200, failJson(JsonCompat.describe(original)))
        }

    /// UiSpec 経路が poly rotation/pivot を断ったエラーか (文言で見分ける)。
    def isRotationErr(e: Util.Json.JsonError): Bool =
        String.contains(substr = "poly rotation/pivot is not supported", JsonCompat.describe(e))

    /// JSON 木から "rotation"/"pivot" キーを全部落とす。ui.json 方言でこの 2 キーを読むのは
    /// poly だけなので、木全体から落としても他の widget の意味は変わらない。
    def stripRotation(json: Json): Json =
        match json {
            case JObject(m) => JObject(m |> Map.remove("rotation") |> Map.remove("pivot")
                                         |> Map.map(v -> stripRotation(v)))
            case JArray(vs) => JArray(Vector.map(v -> stripRotation(v), vs))
            case other      => other
        }

    /// パース済みドキュメントを spawn → レイアウト → ラスタライズして成功応答を組む。
    def render(dir: String, ctx: ProjectCtx.Ctx, spec: UiSpec.Spec, docSpec: UiDoc.Spec,
               hovered: Option[String], scale: Int32, drawPath: DrawPath): (Int32, Json) \ IO =
        let (rootId, spawned) = UiSpec.spawnRoot(spec, UiStore.empty());
        // 画面系の文書は「隠して開始→ゲームが表示を切り替える」作りが多い。プレビューは
        // 初期表示状態の再現でなく文書を見る場なので、root だけ強制表示する(子孫の hidden は
        // 条件付き UI なので尊重する)。
        let shown = UiStore.setVisible(UiDoc.nameOf(docSpec), true, spawned);
        let ui = UiStore.setHovered(hovered, shown);
        let usedFonts = ui#texts |> Map.valuesOf |> List.map(text -> text#font);
        let fonts = ProjectCtx.fontSetup(usedFonts, dir, ctx);
        match fonts#primary {
            case None          =>
                (200, failJson(Option.getWithDefault("no font available for preview", List.head(fonts#warnings))))
            case Some(primary) =>
                let atlasOf = name -> Option.getWithDefault(primary#atlas, Map.get(name, fonts#atlases));
                let usedTextures = ui#sprites |> Map.valuesOf |> List.map(sprite -> sprite#texture);
                let textures = ProjectCtx.textureSetup(usedTextures, ctx);
                let textureInfoOf = name -> Map.get(name, textures#infos);
                let design: Vec2.Vec2 = { x = Int32.toFloat64(ctx#designW), y = Int32.toFloat64(ctx#designH) };
                let rootRect: Rect2.Rect2 = { position = Vec2.zero(), size = design };
                let measures = UiExtract.measureTexts(ui#texts, atlasOf);
                let rects = UiLayout.computeLayout(
                    { styles = ui#styles, parents = ui#parents, order = ui#order,
                      measures = measures, visible = ui#visible },
                    rootId, rootRect);
                let out = match drawPath {
                    case DrawPath.StorePath => UiRender.renderUiWith(atlasOf, textureInfoOf, ui, design)
                    case DrawPath.FlexPath  =>
                        // Store 経路と同じ理由で root を強制表示(こちらは Spec 直読みなので Spec 側を書き換える)。
                        let UiDoc.Spec.Spec(rootNode) = docSpec;
                        let shownDoc = UiDoc.Spec.Spec({ visible = true | rootNode });
                        let placed = UiDoc.renderWith(atlasOf, textureInfoOf, shownDoc, rootRect);
                        let (drawables, polygons) = Render.drawWith(textureInfoOf, placed);
                        {drawables = drawables, polygons = polygons}
                };
                let image = SoftRaster.renderToImage({
                    drawables = out#drawables, polygons = out#polygons,
                    design = design, scale = scale, background = ctx#clearColor,
                    texturePath = ProjectCtx.texturePaths(ctx),
                    fontTtf = primary#path, fontAtlas = primary#atlas,
                    outPath = "" });
                let pathWarnings = match (drawPath, hovered) {
                    case (DrawPath.FlexPath, Some(_)) =>
                        "hover is not applied — documents using poly rotation render via the static path" :: Nil
                    case _                            => Nil
                };
                let warnings = fonts#warnings ::: textures#warnings
                    ::: hoverWarnings(hovered, ui) ::: pathWarnings;
                (200, JObject(Map#{
                    "ok"       => JBool(true),
                    "png"      => JString(PngBase64.encode(image)),
                    "width"    => JNumber(JsonCodec.intToBd(image.getWidth())),
                    "height"   => JNumber(JsonCodec.intToBd(image.getHeight())),
                    "scale"    => JNumber(JsonCodec.intToBd(scale)),
                    "design"   => JObject(Map#{
                        "w" => JNumber(JsonCodec.intToBd(ctx#designW)),
                        "h" => JNumber(JsonCodec.intToBd(ctx#designH))
                    }),
                    "rects"    => rectsJson(ui, rects),
                    "tree"     => treeJson("", docSpec),
                    "warnings" => JsonCodec.encodeList(warning -> JString(warning), warnings),
                    "error"    => JNull
                }))
        }

    /// hovered の名前パスが木のどのノードにも当たらないときだけ warning にする
    /// (絵が変わらない理由を編集画面へ伝える。当たれば絵の変化そのものが答え)。
    def hoverWarnings(hovered: Option[String], ui: UiStore.UiWorld): List[String] =
        match hovered {
            case None       => Nil
            case Some(path) =>
                if (Option.isEmpty(UiStore.idOf(path, ui)))
                    "hovered '${path}' does not match any node" :: Nil
                else Nil
        }

    // ════════════════════════════════════════════════════════
    // 応答 JSON の組み立て
    // ════════════════════════════════════════════════════════

    /// 名前パス → [x, y, w, h] (design 座標)。レイアウトで矩形が確定したノードだけ載る。
    def rectsJson(ui: UiStore.UiWorld, rects: Map[EntityId, Rect2.Rect2]): Json =
        JObject(ui#names |> Map.foldLeftWithKey((acc, path, id) -> match Map.get(id, rects) {
            case None       => acc
            case Some(rect) => Map.insert(path, rectJson(rect), acc)
        }, Map.empty()))

    def rectJson(rect: Rect2.Rect2): Json =
        JArray(Vector#{num(rect#position#x), num(rect#position#y), num(rect#size#x), num(rect#size#y)})

    def num(value: Float64): Json =
        JNumber(JsonCodec.floatToBd(value))

    /// UiDoc.Spec のノード木をエディタ向けの JSON に写す。path は名前を "/" で繋いで組む。
    def treeJson(parentPath: String, spec: UiDoc.Spec): Json =
        let UiDoc.Spec.Spec(node) = spec;
        let path = if (parentPath == "") node#name else "${parentPath}/${node#name}";
        JObject(Map#{
            "name"     => JString(node#name),
            "path"     => JString(path),
            "widget"   => JString(widgetName(node#widget)),
            "note"     => optString(node#note),
            "instance" => optString(node#origin),
            "visible"  => JBool(node#visible),
            "bind"     => optString(node#binding),
            "meta"     => optString(node#meta),
            "hasHover" => JBool(not Option.isEmpty(node#hover)),
            "children" => JArray(node#children |> List.map(child -> treeJson(path, child)) |> List.toVector)
        })

    /// widget を種別名 1 語に畳む (図形の詳細パラメータはプレビュー画像側が語る)。
    def widgetName(widget: UiDoc.Widget): String =
        match widget {
            case UiDoc.Widget.NoneW      => "none"
            case UiDoc.Widget.BoxW(_)    => "box"
            case UiDoc.Widget.TextW(_)   => "text"
            case UiDoc.Widget.SpriteW(_) => "sprite"
            case UiDoc.Widget.PolyW(_)   => "poly"
            case UiDoc.Widget.ShapeW(_)  => "shape"
        }

    def optString(opt: Option[String]): Json =
        match opt {
            case None    => JNull
            case Some(s) => JString(s)
        }

    /// ドキュメント側の失敗応答 (HTTP 200 で返す)。
    def failJson(message: String): Json =
        let (pathOpt, text) = splitNodePath(message);
        JObject(Map#{
            "ok"       => JBool(false),
            "png"      => JNull,
            "rects"    => JNull,
            "tree"     => JNull,
            "warnings" => JArray(Vector#{}),
            "error"    => JObject(Map#{
                "message" => JString(text),
                "path"    => optString(pathOpt)
            })
        })

    /// エラー文言 "at <位置>: <本文>" を (位置, 本文) に分解する。
    /// 形が違う文言 (プロジェクト設定エラー等) は path 無しの全文のまま返す。
    pub def splitNodePath(message: String): (Option[String], String) =
        if (String.startsWith(prefix = "at ", message)) {
            let rest = String.drop(3, message);
            match String.indexOfLeft(substr = ": ", rest) {
                case Some(i) => (Some(String.take(i, rest)), String.drop(i + 2, rest))
                case None    => (None, message)
            }
        } else (None, message)

    /// 封筒不正 (400) の本文。Editor の他エンドポイントの失敗形と同じ {ok:false, error}。
    def envelopeError(message: String): Json =
        JObject(Map#{"ok" => JBool(false), "error" => JString(message)})
}
