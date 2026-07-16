// PreviewFx — POST /preview/fx。編集中の fx.json (メモリ上の doc、またはプロジェクト内の
// ファイル path) を、seed と時刻 t の 1 コマとしてヘッドレスで PNG に描いて返す。
// キャンバス寸法は固定でなく、粒がいちばん遠くまで飛んだときの到達距離から自動で決める
// (designSideOf)。原点 (発生点) はキャンバス中央。
// 失敗の返し分けは PreviewUi と同じ: 封筒 (リクエストの形) が壊れているときだけ HTTP 400、
// ドキュメント側の問題 (パース失敗等) は HTTP 200 の ok:false + error{message, path}。

mod PreviewFx {
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JString, JNumber, JBool, JNull}

    /// リクエストボディを解いて (HTTP status, 応答 JSON) を作る。
    /// body: {path?, doc?, seed?, t?, scale?}。doc が path より優先 (編集中バッファ優先)。
    pub def respond(dir: String, caches: Caches.Caches, body: String): (Int32, Json) \ IO =
        match (JsonCompat.parse(body) |> Option.flatMap(JsonCodec.expectObject)) {
            case None      => (400, envelopeError("body must be a JSON object {path?, doc?, seed?, t?, scale?}"))
            case Some(obj) =>
                let scale = PreviewUi.clampScale(JsonCodec.intOr("scale", 2, obj));
                let seed = seedOf(obj);
                let t = JsonCodec.floatOr("t", 0.0, obj);
                match PreviewUi.docJsonOf(dir, obj) {
                    case Err(PreviewUi.BadRequest.Envelope(message)) => (400, envelopeError(message))
                    case Err(PreviewUi.BadRequest.Doc(message))      => (200, failJson(message))
                    case Ok(docJson)                                 => match FxDoc.parse(docJson) {
                        case Err(e)   => (200, failJson(JsonCompat.describe(e)))
                        case Ok(spec) => renderFx(dir, caches, spec, {seed = seed, t = t, scale = scale})
                    }
                }
        }

    /// seed は Int64 (Fx.sample の契約)。省略・数値でない・整数に収まらないときは既定の 42。
    def seedOf(obj: Map[String, Json]): Int64 =
        match Map.get("seed", obj) {
            case Some(JNumber(bd)) => BigDecimal.tryToInt64(bd) |> Option.getWithDefault(42i64)
            case _                 => 42i64
        }

    // ════════════════════════════════════════════════════════
    // キャンバス寸法の自動決定 (純粋 — テストの入口)
    // ════════════════════════════════════════════════════════

    /// キャンバスの一辺 (正方形・px)。粒の最大到達半径 × 2 を切り上げ、最小 128。
    /// 一辺 = clamp(128, 2048, ceil(2 × max_emitter(到達半径)))
    /// 到達半径 = |speed.base|·(1+speed.vary) × life.base·(1+life.vary)
    ///            × max|∫₀ᵘ speed.over| + size × max(sizeOver)
    // WhyNot: 上限 2048 を契約外に足している — 途方もない speed×life の doc を
    // そのまま信じると数十万 px の画像を作ろうとしてメモリごと落ちるため。
    pub def designSideOf(spec: FxDoc.Spec): Int32 =
        let halfExtent = spec#emitters
            |> List.foldLeft((acc, emitter) -> Float64.max(acc, emitterExtent(emitter)), 0.0);
        Int32.min(2048, Int32.max(128, ceilInt(halfExtent * 2.0)))

    /// emitter 1 本の粒が原点から届く最大距離 + 粒サイズぶんの余白。
    /// 距離 = 初速 × 寿命 × 速度カーブの積分 (Fx.sampleParticle と同じ閉形式) の最大値。
    /// vary は base×(1+vary) が最大なので、その最悪値で見積もる。
    pub def emitterExtent(emitter: FxDoc.Emitter): Float64 =
        let speedMax = Float64.abs(emitter#speed#base) * (1.0 + emitter#speed#vary);
        let lifeMax  = emitter#life#base * (1.0 + emitter#life#vary);
        speedMax * lifeMax * integralPeak(emitter#speed#over)
            + emitter#size * curvePeak(emitter#sizeOver)

    /// 速度カーブの積分 |∫₀ᵘ curve| の u∈[0,1] での最大値 (= 到達距離の倍率)。
    /// 単調に離れるカーブは u=1 が最遠。途中で速度の符号が変わる linear だけは
    /// 折り返し点 u* = from/(from-to) の往路が最遠になり得る。
    pub def integralPeak(curve: FxDoc.CurveSpec): Float64 =
        match curve {
            case FxDoc.CurveSpec.Constant   => 1.0
            case FxDoc.CurveSpec.Linear(l)  =>
                let endDist = Float64.abs((l#fromV + l#toV) / 2.0);
                if (l#fromV * l#toV < 0.0)
                    Float64.max(endDist, Float64.abs(l#fromV * l#fromV / (2.0 * (l#fromV - l#toV))))
                else endDist
            case FxDoc.CurveSpec.EaseIn(e)  => powerIntegral(e#power)
            case FxDoc.CurveSpec.EaseOut(e) => powerIntegral(e#power)
            case FxDoc.CurveSpec.Peak(_)    => 0.5
            // flicker は速度カーブとしてパースが弾くが、値 ≤ 1 なので積分 ≤ 1 を上限に使う。
            case FxDoc.CurveSpec.Flicker(_) => 1.0
        }

    /// u^p (easeIn) と (1-u)^p (easeOut) の ∫₀¹ = 1/(p+1)。
    /// p ≤ -1 は積分が発散する (パースは power を検査しない) ので上限 1.0 に倒す。
    def powerIntegral(power: Float64): Float64 =
        if (power <= -1.0) 1.0 else 1.0 / (power + 1.0)

    /// 大きさカーブの最大倍率 (粒サイズ余白の見積もり)。1.0 を超えられるのは linear だけ。
    pub def curvePeak(curve: FxDoc.CurveSpec): Float64 =
        match curve {
            case FxDoc.CurveSpec.Linear(l) => Float64.max(Float64.abs(l#fromV), Float64.abs(l#toV))
            case _                         => 1.0
        }

    /// 切り上げて Int32 に。Int32 に収まらない巨大値は上限 2048 側に倒す。
    def ceilInt(x: Float64): Int32 =
        Float64.ceil(x) |> Float64.tryToInt32 |> Option.getWithDefault(2048)

    // ════════════════════════════════════════════════════════
    // 描画 → 応答
    // ════════════════════════════════════════════════════════

    /// Spec を seed・t の 1 コマとして描き、成功応答を組む。粒は原点発生なので
    /// キャンバス中央へ平行移動してからラスタライズする。
    /// フォント: fx に文字は無いが、ラスタライザが TTF 1 本を必須にするので
    /// PreviewUi と同じ流儀でプロジェクトの代表フォントを工面する。
    def renderFx(dir: String, caches: Caches.Caches, spec: FxDoc.Spec,
                 req: {seed = Int64, t = Float64, scale = Int32}): (Int32, Json) \ IO =
        HeadlessFont.ensureHeadless();
        match ProjectCtx.load(dir) {
            case Err(message) => (200, failJson("project.json: ${message}"))
            case Ok(ctx)      =>
                let fonts = ProjectCtx.fontSetup(Nil, dir, caches, ctx);
                match fonts#primary {
                    case None          =>
                        (200, failJson(Option.getWithDefault("no font available for preview", List.head(fonts#warnings))))
                    case Some(primary) =>
                        let side = designSideOf(spec);
                        let design: Vec2.Vec2 = { x = Int32.toFloat64(side), y = Int32.toFloat64(side) };
                        let center = Vec2.mul(design, 0.5);
                        let placed = Fx.sample(spec, req#seed, req#t)
                            |> List.map(p -> { at = Vec2.add(p#at, center) | p });
                        let (drawables, polygons) =
                            Render.drawWith(_ -> (None: Option[GameEngine.TextureInfo]), placed);
                        let image = SoftRaster.renderToImage({
                            drawables = drawables, polygons = polygons,
                            design = design, scale = req#scale, background = ctx#clearColor,
                            texturePath = Map.empty(),
                            fontTtf = primary#path, fontAtlas = primary#atlas,
                            outPath = "" });
                        (200, JObject(Map#{
                            "ok"       => JBool(true),
                            "png"      => JString(PngBase64.encode(image)),
                            "width"    => JNumber(JsonCodec.intToBd(image.getWidth())),
                            "height"   => JNumber(JsonCodec.intToBd(image.getHeight())),
                            "scale"    => JNumber(JsonCodec.intToBd(req#scale)),
                            "design"   => JObject(Map#{
                                "w" => JNumber(JsonCodec.intToBd(side)),
                                "h" => JNumber(JsonCodec.intToBd(side))
                            }),
                            "duration" => JNumber(JsonCodec.floatToBd(spec#duration)),
                            "name"     => JString(spec#name),
                            "note"     => optString(spec#note),
                            "count"    => JNumber(JsonCodec.intToBd(List.length(placed))),
                            "warnings" => JsonCodec.encodeList(warning -> JString(warning), fonts#warnings),
                            "error"    => JNull
                        }))
                }
        }

    def optString(opt: Option[String]): Json =
        match opt {
            case None    => JNull
            case Some(s) => JString(s)
        }

    /// ドキュメント側の失敗応答 (HTTP 200)。error の path 分解は PreviewUi と同じ読み方。
    def failJson(message: String): Json =
        let (pathOpt, text) = PreviewUi.splitNodePath(message);
        JObject(Map#{
            "ok"       => JBool(false),
            "png"      => JNull,
            "warnings" => JArray(Vector#{}),
            "error"    => JObject(Map#{
                "message" => JString(text),
                "path"    => optString(pathOpt)
            })
        })

    /// 封筒不正 (400) の本文。他エンドポイントの失敗形と同じ {ok:false, error}。
    def envelopeError(message: String): Json =
        JObject(Map#{"ok" => JBool(false), "error" => JString(message)})
}
