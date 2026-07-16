// PreviewUi — POST /preview/ui。編集中の ui.json (メモリ上の doc、またはプロジェクト内の
// ファイル path) をヘッドレスで 1 枚の PNG に描き、レイアウト矩形とノード木を添えて返す。
// 追加の入力 (どれも任意・無ければ従来どおり):
//   data    — 主 doc の bind 済みノードへ流し込むサンプル文字列 { bindKey: text, ... }
//   compose — 主 doc の背面に重ねる保存済み文書列 [{path, data?}, ...] (配列順 = 奥→手前)
//   sidecar — 主 doc を path 指定したとき、隣の <名前>.preview.json があれば
//             { data, compose } の既定値として自動適用 (リクエスト明示がフィールド丸ごと優先)
// 失敗の返し分け: リクエストの封筒が壊れている (JSON でない / doc も path も無い /
// data・compose の形違い) ときだけ HTTP 400。ドキュメント側の問題 (パース失敗・参照切れ・
// 合成先が読めない等) は HTTP 200 の ok:false — 編集画面はタイピング途中の壊れた JSON を
// 送り続けるので、それを HTTP エラーにしない。

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

    /// 合成 1 文書ぶんの指定。`path` はプロジェクト相対の保存済み ui.json (doc インラインは
    /// 主 doc だけの特権 — 合成側まで未保存バッファを受けると封筒が際限なく太る)。
    /// `data` はその文書の bind へ流す値。
    pub type alias ComposeEntry = { path = String, data = Map[String, String] }

    /// spawn 直前まで解決済みの 1 文書。主 doc も合成文書もこの形に揃えて同じ道を通す。
    pub type alias DocToSpawn = { path = String, spec = UiSpec.Spec, data = Map[String, String] }

    /// spawn 済み root の台帳 1 行 (応答の composed とレイアウトの入口に使う)。
    pub type alias SpawnedRoot = { path = String, root = String, id = EntityId }

    /// data / compose の解決済み入力 (リクエスト明示 > sidecar > 空)。
    type alias PreviewInput = { data = Map[String, String], compose = List[ComposeEntry] }

    /// リクエストボディを解いて (HTTP status, 応答 JSON) を作る。
    pub def respond(dir: String, caches: Caches.Caches, body: String): (Int32, Json) \ IO =
        match (JsonCompat.parse(body) |> Option.flatMap(JsonCodec.expectObject)) {
            case None      => (400, envelopeError("body must be a JSON object {path?, doc?, hovered?, scale?, data?, compose?}"))
            case Some(obj) =>
                let scale = clampScale(JsonCodec.intOr("scale", 1, obj));
                let hovered = Map.get("hovered", obj) |> Option.flatMap(JsonCodec.expectString);
                match requestExtras(obj) {
                    case Err(message) => (400, envelopeError(message))
                    case Ok(extras)   => match docJsonOf(dir, obj) {
                        case Err(BadRequest.Envelope(message)) => (400, envelopeError(message))
                        case Err(BadRequest.Doc(message))      => (200, failJson(message))
                        case Ok(docJson)                       =>
                            let (input, sidecarWarnings) = resolveInput(dir, obj, extras);
                            preview(dir, caches, docJson, hovered, scale, input, sidecarWarnings)
                    }
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

    // ════════════════════════════════════════════════════════
    // data / compose / sidecar の解釈
    // ════════════════════════════════════════════════════════

    /// リクエストの data / compose を解く。キーが無いのは正常 (None)。形違いは封筒不正 (400) —
    /// タイポで data が黙って無視されるより、その場で形を正してもらう方が早い。
    def requestExtras(obj: Map[String, Json]):
            Result[String, {data = Option[Map[String, String]], compose = Option[List[ComposeEntry]]}] =
        forM (
            data    <- optField("data", json -> dataFromJson(json), "'data' must be an object of string values", obj);
            compose <- optField("compose", json -> composeFromJson(json), "'compose' must be an array of {path, data?}", obj)
        ) yield { data = data, compose = compose }

    /// キーが無ければ Ok(None)、あれば decode に通す (解けなければ message で Err)。
    def optField(key: String, decode: Json -> Option[a], message: String, obj: Map[String, Json]): Result[String, Option[a]] =
        match Map.get(key, obj) {
            case None       => Ok(None)
            case Some(json) => decode(json) |> Option.map(v -> Some(v)) |> Option.toOk(message)
        }

    /// {"key": "text", ...} を Map にする。文字列以外の値が混ざれば None
    /// (数値の暗黙変換はしない — 表示文字列は呼び手が決める契約)。
    pub def dataFromJson(json: Json): Option[Map[String, String]] =
        JsonCodec.expectObject(json) |> Option.flatMap(obj ->
            obj |> Map.foldLeftWithKey((accOpt, key, value) ->
                forM (acc <- accOpt; text <- JsonCodec.expectString(value))
                yield Map.insert(key, text, acc), Some(Map.empty())))

    /// [{"path": "...", "data": {...}?}, ...] を読む。path 欠け・形違いの要素が 1 つでもあれば None。
    pub def composeFromJson(json: Json): Option[List[ComposeEntry]] =
        match json {
            case JArray(entries) => entries
                |> Vector.toList
                |> List.map(entry -> composeEntryFromJson(entry))
                |> List.foldRight((entryOpt, accOpt) ->
                    forM (entry <- entryOpt; acc <- accOpt) yield entry :: acc, Some(Nil))
            case _               => None
        }

    def composeEntryFromJson(json: Json): Option[ComposeEntry] =
        forM (
            obj  <- JsonCodec.expectObject(json);
            path <- Map.get("path", obj) |> Option.flatMap(JsonCodec.expectString);
            data <- match Map.get("data", obj) {
                case None            => Some(Map.empty())
                case Some(dataJson)  => dataFromJson(dataJson)
            }
        ) yield ({ path = path, data = data }: ComposeEntry)

    /// 主 doc の隣に置く既定プレビュー設定 (sidecar) のパス。
    /// *.ui.json 以外は sidecar 規約の対象外なので None。
    pub def sidecarPathOf(path: String): Option[String] =
        if (String.endsWith(suffix = ".ui.json", path))
            Some("${String.take(String.length(path) - 8, path)}.preview.json")
        else None

    /// data / compose の最終値を決める。主 doc が path 指定なら sidecar を既定値として読み、
    /// リクエストに明示があればフィールド丸ごとそちらが勝つ (キー単位で混ぜると
    /// どこから来た値か追えなくなる)。
    def resolveInput(dir: String, obj: Map[String, Json],
                     extras: {data = Option[Map[String, String]], compose = Option[List[ComposeEntry]]}):
                    (PreviewInput, List[String]) \ IO =
        let bothExplicit = not Option.isEmpty(extras#data) and not Option.isEmpty(extras#compose);
        let sidecarPath =
            if (bothExplicit or not Option.isEmpty(Map.get("doc", obj))) None
            else Map.get("path", obj) |> Option.flatMap(JsonCodec.expectString) |> Option.flatMap(p -> sidecarPathOf(p));
        let (sidecar, warnings) = match sidecarPath {
            case None       => (emptySidecar(), Nil)
            case Some(path) => readSidecar(dir, path)
        };
        ({ data    = extras#data    |> Option.getWithDefault(sidecar#data),
           compose = extras#compose |> Option.getWithDefault(sidecar#compose) },
         warnings)

    def emptySidecar(): PreviewInput =
        { data = Map.empty(), compose = Nil }

    /// sidecar を読む。ファイルが無いのは普通のこと (静かに素通し)。中身の形違いは置いた人の
    /// 意図が果たされていないので warning で伝え、その項目だけ無視する。
    def readSidecar(dir: String, sidecarPath: String): (PreviewInput, List[String]) \ IO =
        match FileIndex.readInside(dir, sidecarPath) {
            case Err(_)      => (emptySidecar(), Nil)
            case Ok(content) => match (JsonCompat.parse(String.trim(content)) |> Option.flatMap(JsonCodec.expectObject)) {
                case None      => (emptySidecar(), "sidecar ${sidecarPath} is not a JSON object — ignored" :: Nil)
                case Some(obj) =>
                    let (data, dataWarnings) =
                        sidecarField("data", json -> dataFromJson(json), Map.empty(),
                                     "an object of string values", sidecarPath, obj);
                    let (compose, composeWarnings) =
                        sidecarField("compose", json -> composeFromJson(json), Nil,
                                     "an array of {path, data?}", sidecarPath, obj);
                    ({ data = data, compose = compose }, dataWarnings ::: composeWarnings)
            }
        }

    /// sidecar の 1 フィールドを解く。無ければ既定値 (警告なし)、形違いは既定値 + warning 1 行。
    def sidecarField(key: String, decode: Json -> Option[a], fallback: a, shape: String,
                     sidecarPath: String, obj: Map[String, Json]): (a, List[String]) =
        match Map.get(key, obj) {
            case None       => (fallback, Nil)
            case Some(json) => match decode(json) {
                case Some(value) => (value, Nil)
                case None        => (fallback, "sidecar ${sidecarPath}: '${key}' must be ${shape} — ignored" :: Nil)
            }
        }

    // ════════════════════════════════════════════════════════
    // パース → 合成 → 描画
    // ════════════════════════════════════════════════════════

    /// プロジェクト設定を読み、主 doc を 2 経路 (描画用 UiSpec / 木情報用 UiDoc) でパースし、
    /// 合成文書を読み集めてから描画へ渡す。UiDoc.Spec を別途取るのは note/origin
    /// (エディタ向け情報) が UiSpec.Spec に無いため。
    def preview(dir: String, caches: Caches.Caches, docJson: Json, hovered: Option[String], scale: Int32,
                input: PreviewInput, extraWarnings: List[String]): (Int32, Json) \ IO =
        HeadlessFont.ensureHeadless();
        match ProjectCtx.load(dir) {
            case Err(message) => (200, failJson("project.json: ${message}"))
            case Ok(ctx)      =>
                let specRes = run { UiSpec.parseAt(dir, docJson) } with Fs.FileRead.runWithIO;
                let docRes  = run { UiDoc.parseAt(dir, docJson) } with Fs.FileRead.runWithIO;
                let palette = resolvedPalette(dir, docJson);
                match loadComposed(dir, input#compose) {
                    case Err(message)  => (200, failJson(message))
                    case Ok(composed)  => match (specRes, docRes) {
                        case (Ok(spec), Ok(docSpec)) =>
                            render(dir, caches, ctx, docSpec, {
                                main = { path = "", spec = spec, data = input#data },
                                composed = composed, hovered = hovered, scale = scale,
                                drawPath = DrawPath.StorePath, palette = palette,
                                extraWarnings = extraWarnings })
                        case (Err(e), Ok(docSpec))   =>
                            if (isRotationErr(e) and List.isEmpty(composed))
                                rotationFallback(dir, caches, ctx, docJson, docSpec, hovered, scale, input, extraWarnings, e)
                            else if (isRotationErr(e))
                                (200, failJson("this document uses poly rotation — composing is not supported for it, preview it alone"))
                            else (200, failJson(JsonCompat.describe(e)))
                        case (_, Err(e))             => (200, failJson(JsonCompat.describe(e)))
                    }
                }
        }

    /// 合成する各文書を読む。1 つでも読めない・解けない文書があれば全体を ok:false —
    /// 一部だけ欠けた合成絵を「正」と誤読させないため。poly rotation 入りの文書は合成では
    /// 未対応なので、単体プレビューへ誘導する文言で断る。
    def loadComposed(dir: String, entries: List[ComposeEntry]): Result[String, List[DocToSpawn]] \ IO =
        entries |> List.foldRight((entry, accRes) -> match accRes {
            case Err(message) => Err(message)
            case Ok(acc)      => loadComposeDoc(dir, entry) |> Result.map(doc -> doc :: acc)
        }, Ok(Nil))

    def loadComposeDoc(dir: String, entry: ComposeEntry): Result[String, DocToSpawn] \ IO =
        let jsonRes = FileIndex.readInside(dir, entry#path)
            |> Result.flatMap(content -> JsonCompat.parse(String.trim(content)) |> Option.toOk("JSON parse failed"));
        match jsonRes {
            case Err(message) => Err("compose '${entry#path}': ${message}")
            case Ok(json)     =>
                (run { UiSpec.parseAt(dir, json) } with Fs.FileRead.runWithIO)
                    |> Result.mapErr(e ->
                        if (isRotationErr(e))
                            "compose '${entry#path}': poly rotation documents cannot be composed — preview it alone"
                        else
                            "compose '${entry#path}': ${JsonCompat.describe(e)}")
                    |> Result.map(spec -> ({ path = entry#path, spec = spec, data = entry#data }: DocToSpawn))
        }

    /// poly rotation/pivot 付きドキュメントの逃げ道 (合成なしの単体時だけ)。回転はレイアウト
    /// 矩形を変えないので、rects と名前表は rotation/pivot を落とした写しの UiStore から取り、
    /// 絵は Flex 経路が回転込みで描く。写しでも通らなければ元のエラーをそのまま返す。
    def rotationFallback(dir: String, caches: Caches.Caches, ctx: ProjectCtx.Ctx, docJson: Json, docSpec: UiDoc.Spec,
                         hovered: Option[String], scale: Int32, input: PreviewInput,
                         extraWarnings: List[String], original: Util.Json.JsonError): (Int32, Json) \ IO =
        let strippedRes = run { UiSpec.parseAt(dir, stripRotation(docJson)) } with Fs.FileRead.runWithIO;
        match strippedRes {
            case Ok(spec) => render(dir, caches, ctx, docSpec, {
                main = { path = "", spec = spec, data = input#data },
                composed = Nil, hovered = hovered, scale = scale,
                drawPath = DrawPath.FlexPath, palette = resolvedPalette(dir, docJson),
                extraWarnings = extraWarnings })
            case Err(_)   => (200, failJson(JsonCompat.describe(original)))
        }

    /// UiSpec 経路が poly rotation/pivot を断ったエラーか (文言で見分ける)。
    def isRotationErr(e: Util.Json.JsonError): Bool =
        String.contains(substr = "poly rotation/pivot is not supported", JsonCompat.describe(e))

    /// JSON 木のどこかに "rotation"/"pivot" キーがあるか。ui.json 方言でこの 2 キーを読むのは
    /// poly だけなので、キーの有無だけで「合成に使えない (回転入り) 文書」と判定できる。
    /// GET /files が合成候補の事前判定に使う。
    pub def containsRotation(json: Json): Bool =
        match json {
            case JObject(m) =>
                Map.memberOf("rotation", m) or Map.memberOf("pivot", m)
                    or (Map.valuesOf(m) |> List.exists(v -> containsRotation(v)))
            case JArray(vs) => Vector.exists(v -> containsRotation(v), vs)
            case _          => false
        }

    /// JSON 木から "rotation"/"pivot" キーを全部落とす。ui.json 方言でこの 2 キーを読むのは
    /// poly だけなので、木全体から落としても他の widget の意味は変わらない。
    def stripRotation(json: Json): Json =
        match json {
            case JObject(m) => JObject(m |> Map.remove("rotation") |> Map.remove("pivot")
                                         |> Map.map(v -> stripRotation(v)))
            case JArray(vs) => JArray(Vector.map(v -> stripRotation(v), vs))
            case other      => other
        }

    // ════════════════════════════════════════════════════════
    // パレット表 (応答の palette フィールド)
    // ════════════════════════════════════════════════════════

    /// 主 doc の解決済みパレット表 ("名前" → "#rrggbb")。paletteFile を dir 起点で読み、
    /// inline "palette" を上に重ねる (同名は inline 勝ち = UiDoc.load と同じ合成順)。
    /// 読めない・形違いはその分だけ落として空側に倒す — この表は編集画面の色見本用で、
    /// ドキュメント自体の誤りはプレビュー本体 (parse) が名前パス付きで報告する。
    pub def resolvedPalette(dir: String, docJson: Json): Map[String, String] \ IO =
        match docJson {
            case JObject(top) => paletteTable(filePaletteOf(dir, top), top)
            case _            => Map.empty()
        }

    /// トップの "paletteFile" が指す先を読んでパレットの Map にする (無い・読めないは空)。
    def filePaletteOf(dir: String, top: Map[String, Json]): Map[String, Json] \ IO =
        match paletteRefOf(JObject(top)) {
            case None       => Map.empty()
            case Some(path) => match FileIndex.readInside(dir, path) {
                case Err(_)      => Map.empty()
                case Ok(content) => JsonCompat.parse(String.trim(content))
                    |> Option.flatMap(JsonCodec.expectObject)
                    |> Option.getWithDefault(Map.empty())
            }
        }

    /// トップレベルの "paletteFile" 参照 (文字列のときだけ)。
    /// GET /files が palette.json の一覧 (逆引き) を組むのにも使う。
    pub def paletteRefOf(json: Json): Option[String] =
        JsonCodec.expectObject(json)
            |> Option.flatMap(top -> Map.get("paletteFile", top))
            |> Option.flatMap(JsonCodec.expectString)

    /// 外部パレットの上に inline "palette" を重ね (同名は inline 勝ち)、各色を "#rrggbb" へ
    /// 解決した表にする。解決できない値は表から落とす (色見本に出せない値を無理に出さない)。
    pub def paletteTable(filePalette: Map[String, Json], top: Map[String, Json]): Map[String, String] =
        let inline = Map.get("palette", top)
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.getWithDefault(Map.empty());
        let merged = Map.foldLeftWithKey((acc, name, value) -> Map.insert(name, value, acc), filePalette, inline);
        merged |> Map.toList
            |> List.filterMap(entry -> {
                let (name, value) = entry;
                colorHexOf(value) |> Option.map(hex -> (name, hex))
            })
            |> List.toMap

    /// 色値 ("#rrggbb" | {"hsv":[h,s,v]} | {"rgb":[r,g,b]}) を "#rrggbb" へ。
    /// hsv→rgb の数式はエンジンの Color.hsv に任せる (二重実装を作らない)。
    def colorHexOf(json: Json): Option[String] =
        match json {
            case JString(s) => normalizeHex(s)
            case JObject(m) => match (Map.get("hsv", m), Map.get("rgb", m)) {
                case (Some(hsvJson), None) => floats3Of(hsvJson) |> Option.map(t -> {
                    let (h, s, v) = t;
                    colorToHex(Color.hsv({ h = h, s = s, v = v }))
                })
                case (None, Some(rgbJson)) => floats3Of(rgbJson) |> Option.map(t -> {
                    let (r, g, b) = t;
                    colorToHex({ r = channelOf(r), g = channelOf(g), b = channelOf(b) })
                })
                case _ => None
            }
            case _ => None
        }

    /// "#rrggbb" (先頭 # は任意・大文字可) を小文字の "#rrggbb" へ。6 桁 16 進以外は None
    /// ("@名前" もここで落ちる — パレットの値に "@..." は書けない規約)。
    def normalizeHex(s: String): Option[String] =
        let body = if (String.startsWith(prefix = "#", s)) String.drop(1, s) else s;
        let chars = String.toList(String.toLowerCase(body));
        if (List.length(chars) == 6 and List.forAll(c -> isHexDigit(c), chars))
            Some("#${String.toLowerCase(body)}")
        else None

    def isHexDigit(c: Char): Bool =
        (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f')

    def floats3Of(json: Json): Option[(Float64, Float64, Float64)] =
        match json {
            case JArray(v) => match Vector.toList(v) |> List.map(JsonCodec.expectFloat) {
                case Some(a) :: Some(b) :: Some(c) :: Nil => Some((a, b, c))
                case _                                    => None
            }
            case _ => None
        }

    def channelOf(x: Float64): Float32 =
        Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, x)

    /// Color (0〜1 の 3 チャンネル) を "#rrggbb" にする。
    def colorToHex(c: Color): String =
        "#${hexByte(c#r)}${hexByte(c#g)}${hexByte(c#b)}"

    def hexByte(x: Float32): String =
        let raw = Float64.tryToInt32(Float32.toFloat64(x) * 255.0 + 0.5) |> Option.getWithDefault(0);
        let n = Int32.max(0, Int32.min(255, raw));
        "${hexDigit(n / 16)}${hexDigit(Int32.modulo(n, 16))}"

    def hexDigit(n: Int32): String =
        "0123456789abcdef" |> String.drop(n) |> String.take(1)

    /// render の入力一式。`composed` が奥、`main` (主 doc) が最前。
    type alias RenderJob = {
        main = DocToSpawn,
        composed = List[DocToSpawn],
        hovered = Option[String],
        scale = Int32,
        drawPath = DrawPath,
        palette = Map[String, String],
        extraWarnings = List[String]
    }

    /// パース済みの全文書を spawn → レイアウト → ラスタライズして成功応答を組む。
    def render(dir: String, caches: Caches.Caches, ctx: ProjectCtx.Ctx, docSpec: UiDoc.Spec, job: RenderJob): (Int32, Json) \ IO =
        let hasCompose = not List.isEmpty(job#composed);
        // FlexPath の絵は UiDoc (Spec 直読み) が描くので、store へ data を流すと rects だけが
        // 動いて絵と食い違う。流さず warning で伝える。
        let dataDropped = match job#drawPath {
            case DrawPath.StorePath => false
            case DrawPath.FlexPath  => not Map.isEmpty(job#main#data)
        };
        let mainDoc = if (dataDropped) { data = Map.empty() | job#main } else job#main;
        let spawned = spawnDocs(List.append(job#composed, mainDoc :: Nil), hasCompose);
        let mainRootName = UiDoc.nameOf(docSpec);
        // hover は主 doc のみ対象。合成文書のノードに当てても絵は変えない (編集対象は主 doc)。
        let hoveredApplied = job#hovered
            |> Option.flatMap(path ->
                if (underRootPath(mainRootName, path) and not Option.isEmpty(UiStore.idOf(path, spawned#ui)))
                    Some(path)
                else None);
        let ui = UiStore.setHovered(hoveredApplied, spawned#ui);
        let usedFonts = ui#texts |> Map.valuesOf |> List.map(text -> text#font);
        let fonts = ProjectCtx.fontSetup(usedFonts, dir, caches, ctx);
        match fonts#primary {
            case None          =>
                (200, failJson(Option.getWithDefault("no font available for preview", List.head(fonts#warnings))))
            case Some(primary) =>
                let atlasOf = name -> Option.getWithDefault(primary#atlas, Map.get(name, fonts#atlases));
                let usedTextures = ui#sprites |> Map.valuesOf |> List.map(sprite -> sprite#texture);
                let textures = ProjectCtx.textureSetup(usedTextures, caches, ctx);
                let textureInfoOf = name -> Map.get(name, textures#infos);
                let design: Vec2.Vec2 = { x = Int32.toFloat64(ctx#designW), y = Int32.toFloat64(ctx#designH) };
                let rootRect: Rect2.Rect2 = { position = Vec2.zero(), size = design };
                let measures = UiExtract.measureTexts(ui#texts, atlasOf);
                let layoutInput = { styles = ui#styles, parents = ui#parents, order = ui#order,
                                    measures = measures, visible = ui#visible };
                let rects = spawned#roots |> List.foldLeft((acc, root) ->
                    UiLayout.computeLayout(layoutInput, root#id, rootRect)
                        |> Map.foldLeftWithKey((m, id, rect) -> Map.insert(id, rect, m), acc),
                    Map.empty());
                let out = match job#drawPath {
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
                    design = design, scale = job#scale, background = ctx#clearColor,
                    texturePath = ProjectCtx.texturePaths(ctx),
                    fontTtf = primary#path, fontAtlas = primary#atlas,
                    outPath = "" });
                let pathWarnings = match (job#drawPath, job#hovered) {
                    case (DrawPath.FlexPath, Some(_)) =>
                        "hover is not applied — documents using poly rotation render via the static path" :: Nil
                    case _                            => Nil
                };
                let dataPathWarnings =
                    if (dataDropped)
                        "data is not applied — documents using poly rotation render via the static path" :: Nil
                    else Nil;
                let dataSources = mainDoc#data :: (job#composed |> List.map(doc -> doc#data));
                let warnings = fonts#warnings ::: textures#warnings
                    ::: hoverWarnings(job#hovered, hasCompose, mainRootName, ui)
                    ::: duplicateRootWarnings(spawned#roots |> List.map(root -> root#root))
                    ::: unmatchedDataWarnings(dataSources, spawned#bindKeys)
                    ::: pathWarnings ::: dataPathWarnings ::: job#extraWarnings;
                let composedRoots = List.take(List.length(spawned#roots) - 1, spawned#roots);
                (200, JObject(Map#{
                    "ok"       => JBool(true),
                    "png"      => JString(PngBase64.encode(image)),
                    "width"    => JNumber(JsonCodec.intToBd(image.getWidth())),
                    "height"   => JNumber(JsonCodec.intToBd(image.getHeight())),
                    "scale"    => JNumber(JsonCodec.intToBd(job#scale)),
                    "design"   => JObject(Map#{
                        "w" => JNumber(JsonCodec.intToBd(ctx#designW)),
                        "h" => JNumber(JsonCodec.intToBd(ctx#designH))
                    }),
                    "rects"    => rectsJson(ui, rects),
                    "tree"     => treeJson("", docSpec),
                    "palette"  => JObject(job#palette |> Map.map(hex -> JString(hex))),
                    "composed" => composedJson(composedRoots),
                    "warnings" => JsonCodec.encodeList(warning -> JString(warning), warnings),
                    "error"    => JNull
                }))
        }

    // ════════════════════════════════════════════════════════
    // 合成 spawn (純粋 — テストの入口)
    // ════════════════════════════════════════════════════════

    /// 文書列 (奥→手前) を 1 つの UiStore へ順に spawn する。各文書で行うこと:
    /// root の強制表示 — 画面系文書は「隠して開始→ゲームが表示を切り替える」作りが多く、
    /// プレビューは文書を見る場なので root だけ表示する (子孫の hidden は条件付き UI なので尊重)。
    /// layer の付け直し (overrideLayers 時) — 合成の前後関係は文書側の layer でなく配列順が
    /// 契約なので、root の layer を配列位置で上書きする。
    /// data の流し込み — 同じ bind key を持つ別文書を巻き込まないよう、この spawn で採番された
    /// entity に bindings を絞ってから、ゲームと同じ UiBinding.apply へ通す。
    pub def spawnDocs(docs: List[DocToSpawn], overrideLayers: Bool):
            { ui = UiStore.UiWorld, roots = List[SpawnedRoot], bindKeys = Set[String] } =
        let seed = { ui = UiStore.empty(), roots = (Nil: List[SpawnedRoot]),
                     bindKeys = (Set.empty(): Set[String]), layer = 0 };
        let acc = docs |> List.foldLeft((state, doc) -> {
            let startId = state#ui#nextId;
            let (rootId, ui1) = UiSpec.spawnRoot(doc#spec, state#ui);
            let rootName = specNameOf(doc#spec);
            let ui2 = UiStore.setVisible(rootName, true, ui1);
            let ui3 = if (overrideLayers) {layers = Map.insert(rootId, state#layer, ui2#layers) | ui2} else ui2;
            let docBindings = ui3#bindings |> Map.filterWithKey((id, _key) -> id >= startId);
            { ui = applyDocData(docBindings, doc#data, ui3),
              roots = List.append(state#roots, ({ path = doc#path, root = rootName, id = rootId }: SpawnedRoot) :: Nil),
              bindKeys = Set.union(state#bindKeys, docBindings |> Map.valuesOf |> List.toSet),
              layer = state#layer + 1 }
        }, seed);
        { ui = acc#ui, roots = acc#roots, bindKeys = acc#bindKeys }

    /// data をこの文書の bind (docBindings) だけに適用する。流し込みの本体はゲームと同じ
    /// UiBinding.apply — bindings 台帳を一時的にこの文書ぶんへ絞って通し、通した後に元へ戻す。
    def applyDocData(docBindings: Map[EntityId, String], data: Map[String, String], ui: UiStore.UiWorld): UiStore.UiWorld =
        if (Map.isEmpty(data)) ui
        else {
            let applied = UiBinding.apply(key -> Map.get(key, data), {bindings = docBindings | ui});
            {bindings = ui#bindings | applied}
        }

    /// UiSpec.Spec の root 名を取り出す。
    def specNameOf(spec: UiSpec.Spec): String =
        let UiSpec.Spec.Spec(fields) = spec;
        fields#name

    /// path が root 名そのものか、その配下 ("root/...") か。
    def underRootPath(rootName: String, path: String): Bool =
        path == rootName or String.startsWith(prefix = "${rootName}/", path)

    // ════════════════════════════════════════════════════════
    // warning の導出 (純粋 — テストの入口)
    // ════════════════════════════════════════════════════════

    /// 同じ root 名の文書を重ねると、名前パス台帳が後勝ちで上書きされ先の文書は rects からも
    /// 絵からも消える。黙って消さず 1 行で伝える (重複した名前ごとに 1 行)。
    pub def duplicateRootWarnings(rootNames: List[String]): List[String] =
        rootNames
            |> List.filter(name -> List.count(other -> other == name, rootNames) > 1)
            |> List.distinct
            |> List.map(name -> "root name '${name}' is used by multiple documents — the last one wins in rects and the image")

    /// data のキーがどの文書の bind にも無ければタイポの可能性が高いので 1 行ずつ伝える。
    pub def unmatchedDataWarnings(datas: List[Map[String, String]], bindKeys: Set[String]): List[String] =
        datas
            |> List.flatMap(data -> Map.keysOf(data) |> Set.toList)
            |> List.distinct
            |> List.filter(key -> not Set.memberOf(key, bindKeys))
            |> List.map(key -> "data key '${key}' does not match any bind")

    /// hovered の名前パスが主 doc のどのノードにも当たらないときだけ warning にする
    /// (絵が変わらない理由を編集画面へ伝える。当たれば絵の変化そのものが答え)。
    def hoverWarnings(hovered: Option[String], hasCompose: Bool, mainRootName: String,
                      ui: UiStore.UiWorld): List[String] =
        match hovered {
            case None       => Nil
            case Some(path) =>
                if (underRootPath(mainRootName, path) and not Option.isEmpty(UiStore.idOf(path, ui)))
                    Nil
                else if (hasCompose)
                    "hovered '${path}' does not match any node in the main document" :: Nil
                else
                    "hovered '${path}' does not match any node" :: Nil
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

    /// 合成した文書の一覧 (主 doc は含めない)。各要素の rects は応答の rects に統合済み。
    def composedJson(roots: List[SpawnedRoot]): Json =
        JsonCodec.encodeList(root -> JObject(Map#{
            "path" => JString(root#path),
            "root" => JString(root#root)
        }), roots)

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
