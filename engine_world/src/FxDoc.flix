// FxDoc — fx.json（閉形式パーティクル）の宣言ドキュメント層。
// 「火花を 20 粒、円で、白→橙→煤の色で、速く出てだんだん減速」のような群れの姿を
// JSON に書き、Spec（pure data）へ畳む。粒の実体はどこにも保存されず、絵は Fx.sample が
// (Spec, seed, t) から毎回計算する — spawn も update も free も無い。
//
// 語彙（version 1）:
//   トップレベル: name（必須）/ duration 秒（必須）/ emitters（必須・1 個以上）。
//     "version"（省略時 1。1 以外は Err）・"$schema"・"note"・"//" キーは ui.json と同じ扱い。
//   emitter: name / count / shape("circle"|"box"・省略時 circle) / size px /
//     color（1〜N 色の配列 — 寿命に沿った線形グラデ。色表記は ui.json と同じ）/
//     life {base 秒, vary} / speed {base px/s, vary, over} / dir {base 度, spread 度} /
//     sizeOver / alphaOver（カーブ）/ blend("normal"|"add"|"multiply"・省略時 normal) / zIndex。
//     vary は 0..1 — 粒ごとに base × (1 ± vary) の幅でばらつく。dir は 0 度 = 真上・時計回り。
//   カーブ: {"kind": ...} の 6 形。省略時は constant（= いつでも 1.0）。
//     constant / linear {from, to} / easeOut {power} / easeIn {power} /
//     peak {at} / flicker {rate, amount}。fadeOut は linear {1, 0} の別名。
//     speed.over だけは flicker 不可（移動距離の式が閉形式にならない）— パース時に断る。
//
// エラーはノードのパス付き（例: `at emitters[0].speed: ...`）— UiDoc と同じ流儀で
// 手書きドキュメントの編集箇所へ誘導する。

mod FxDoc {
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JString}
    use Util.Json.JsonError
    use JsonCompat.PathTag.Root

    // ========================================================================
    // 型（pure data）
    // ========================================================================

    /// 正規化寿命 u（0 = 生まれた瞬間, 1 = 消える瞬間）→ 倍率、のカーブ。
    /// レコードラベルの from/to は Flix の予約語なので内部名は fromV/toV。
    /// （中身がレコードだと Eq を derive できないため、テストは形ごとの値で確かめる）
    pub enum CurveSpec {
        /// いつでも 1.0（変化なし）。
        case Constant
        /// fromV から toV へまっすぐ変わる。
        case Linear({ fromV = Float64, toV = Float64 })
        /// u^power — ゆっくり始まって加速しながら 0 → 1。
        case EaseIn({ power = Float64 })
        /// (1-u)^power — 1 から始まり、速く出てだんだん弱まって 0 へ。
        case EaseOut({ power = Float64 })
        /// u = at で山（1.0）になる三角形（0 → 1 → 0）。ふくらんで縮む粒に。
        case Peak({ at = Float64 })
        /// 寿命あたり rate 回、1 から最大 amount ぶん暗くチラつく（決定論の疑似乱数）。
        case Flicker({ rate = Float64, amount = Float64 })
    }

    /// 粒の形。circle は直径 size の円、box は一辺 size の正方形。
    pub enum Shape with Eq {
        case Circle
        case Box
    }

    /// ばらつき付きの量。粒ごとに base × (1 ± vary) の範囲で決まり、
    /// over が寿命に沿った倍率を掛ける。
    pub type alias Scalar = { base = Float64, vary = Float64, over = CurveSpec }

    /// 粒の群れ 1 種類ぶんの宣言。v1 は burst（全粒が t=0 で同時に生まれる）固定。
    pub type alias Emitter = {
        name = String,                              // 粒ごとの乱数の系統を分ける識別子
        count = Int32,                              // 粒の数
        shape = Shape,                              // 粒の形
        size = Float64,                             // 粒の大きさ px（円は直径・箱は一辺）
        color = List[Color],                        // 寿命に沿った色グラデ（1 色以上）
        life = { base = Float64, vary = Float64 },  // 粒の寿命 秒
        speed = Scalar,                             // 初速 px/s（over が減速カーブ）
        dir = { base = Float64, spread = Float64 }, // 射出方向 度（0 = 真上・時計回り）
        sizeOver = CurveSpec,                       // 大きさの倍率カーブ
        alphaOver = CurveSpec,                      // 透明度の倍率カーブ
        blend = DrawCmd.BlendMode,                  // 重ね方（add = 加算・multiply = 乗算）
        zIndex = Int32                              // 描画順
    }

    /// fx ドキュメント全体。duration を過ぎた時刻の sample は空になる。
    pub type alias Spec = {
        name = String,
        duration = Float64,
        note = Option[String],
        emitters = List[Emitter]
    }

    // ========================================================================
    // parse（純粋）
    // ========================================================================

    /// ドキュメント（version + name + duration + emitters）を Spec へ畳む。
    pub def parse(json: Json): Result[JsonError, Spec] =
        match json {
            case JObject(top) => forM (
                _v       <- JsonCompat.checkVersion("fx document", top);
                name     <- (JsonCompat.getAtKey(Root, "name", top): Result[JsonError, String]);
                duration <- JsonCompat.numAt("duration", top);
                _dur     <- require(duration > 0.0, "(top)", "duration must be > 0 (got: ${duration})");
                note     <- (JsonCompat.getAtKeyOpt(Root, "note", top): Result[JsonError, Option[String]]);
                emitters <- parseEmitters(top)
            ) yield ({ name = name, duration = duration, note = note, emitters = emitters }: Spec)
            case _ => Err(JsonCompat.jsonError(Root, Set#{"FxDoc must be a JSON object with 'name', 'duration', 'emitters'"}))
        }

    def parseEmitters(top: Map[String, Json]): Result[JsonError, List[Emitter]] =
        match Map.get("emitters", top) {
            case Some(JArray(arr)) =>
                if (Vector.isEmpty(arr))
                    Err(JsonCompat.jsonError(Root, Set#{"emitters must have at least 1 entry"}))
                else
                    Result.traverse(entry -> {
                        let (i, json) = entry;
                        forM (
                            m       <- JsonCompat.atNode("emitters[${i}]", JsonCompat.asObject("emitter", json));
                            emitter <- parseEmitter("emitters[${i}]", m)
                        ) yield emitter
                    }, List.zipWithIndex(Vector.toList(arr)))
            case _ => Err(JsonCompat.jsonError(Root, Set#{"'emitters' is required and must be an array"}))
        }

    /// 1 emitter を読む。エラーは "emitters[i]"（サブオブジェクトは "emitters[i].speed" 等）でタグする。
    def parseEmitter(path: String, m: Map[String, Json]): Result[JsonError, Emitter] =
        forM (
            name      <- JsonCompat.atNode(path, (JsonCompat.getAtKey(Root, "name", m): Result[JsonError, String]));
            count     <- JsonCompat.atNode(path, (JsonCompat.getAtKey(Root, "count", m): Result[JsonError, Int32]));
            _cnt      <- require(count >= 1, path, "count must be >= 1 (got: ${count})");
            shape     <- parseShape(path, m);
            size      <- JsonCompat.atNode(path, JsonCompat.numAt("size", m));
            _size     <- require(size > 0.0, path, "size must be > 0 (got: ${size})");
            color     <- parseColors(path, m);
            life      <- parseLife("${path}.life", m);
            speed     <- parseSpeed("${path}.speed", m);
            dir       <- parseDir("${path}.dir", m);
            sizeOver  <- parseCurveAt("${path}.sizeOver", "sizeOver", m);
            alphaOver <- parseCurveAt("${path}.alphaOver", "alphaOver", m);
            blend     <- parseBlend(path, m);
            zIndexOpt <- JsonCompat.atNode(path, (JsonCompat.getAtKeyOpt(Root, "zIndex", m): Result[JsonError, Option[Int32]]))
        ) yield ({
            name = name, count = count, shape = shape, size = size, color = color,
            life = life, speed = speed, dir = dir,
            sizeOver = sizeOver, alphaOver = alphaOver, blend = blend,
            zIndex = Option.getWithDefault(0, zIndexOpt)
        }: Emitter)

    /// 条件が成り立たなければ path 付きで断る（値の下限・範囲の検査に使う）。
    def require(ok: Bool, path: String, msg: String): Result[JsonError, Unit] =
        if (ok) Ok(())
        else JsonCompat.atNode(path, Err(JsonCompat.jsonError(Root, Set#{msg})))

    def parseShape(path: String, m: Map[String, Json]): Result[JsonError, Shape] =
        match (JsonCompat.getAtKeyOpt(Root, "shape", m): Result[JsonError, Option[String]]) {
            case Err(e)              => JsonCompat.atNode(path, Err(e))
            case Ok(None)            => Ok(Shape.Circle)
            case Ok(Some("circle"))  => Ok(Shape.Circle)
            case Ok(Some("box"))     => Ok(Shape.Box)
            case Ok(Some(unknown))   =>
                JsonCompat.atNode(path, Err(JsonCompat.jsonError(Root, Set#{"shape must be circle|box (got: ${unknown})"})))
        }

    def parseBlend(path: String, m: Map[String, Json]): Result[JsonError, DrawCmd.BlendMode] =
        match (JsonCompat.getAtKeyOpt(Root, "blend", m): Result[JsonError, Option[String]]) {
            case Err(e)             => JsonCompat.atNode(path, Err(e))
            case Ok(None)           => Ok(DrawCmd.BlendMode.Normal)
            case Ok(Some("normal")) => Ok(DrawCmd.BlendMode.Normal)
            case Ok(Some("add"))    => Ok(DrawCmd.BlendMode.Add)
            case Ok(Some("multiply")) => Ok(DrawCmd.BlendMode.Multiply)
            case Ok(Some(unknown))  =>
                JsonCompat.atNode(path, Err(JsonCompat.jsonError(Root, Set#{"blend must be normal|add|multiply (got: ${unknown})"})))
        }

    /// "color": [<色>, ...]（1 色以上）。色表記は ui.json と同一（UiDoc.colorOf に一本化）。
    def parseColors(path: String, m: Map[String, Json]): Result[JsonError, List[Color]] =
        match Map.get("color", m) {
            case Some(JArray(arr)) =>
                if (Vector.isEmpty(arr))
                    JsonCompat.atNode(path, Err(JsonCompat.jsonError(Root, Set#{"color must have at least 1 entry"})))
                else
                    JsonCompat.atNode(path,
                        Result.traverse(c -> UiDoc.colorOf(Map.empty(), "color", c), Vector.toList(arr)))
            case Some(_) => JsonCompat.atNode(path, Err(JsonCompat.jsonError(Root, Set#{"color must be an array of colors"})))
            case None    => JsonCompat.atNode(path, Err(JsonCompat.jsonError(Root, Set#{"'color' is required"})))
        }

    /// "life": {"base": 秒, "vary": 0..1}（必須。vary 省略時 0）。
    def parseLife(path: String, m: Map[String, Json]): Result[JsonError, { base = Float64, vary = Float64 }] =
        match (JsonCompat.getAtKeyOpt(Root, "life", m): Result[JsonError, Option[Map[String, Json]]]) {
            case Err(e)       => JsonCompat.atNode(path, Err(e))
            case Ok(None)     => JsonCompat.atNode(path, Err(JsonCompat.jsonError(Root, Set#{"'life' is required ({\"base\": seconds})"})))
            case Ok(Some(lm)) => forM (
                base  <- JsonCompat.atNode(path, JsonCompat.numAt("base", lm));
                vary  <- JsonCompat.atNode(path, JsonCompat.numOr("vary", 0.0, lm));
                _base <- require(base > 0.0, path, "base must be > 0 (got: ${base})");
                _vary <- requireVary(path, vary)
            ) yield { base = base, vary = vary }
        }

    /// "speed": {"base": px/s, "vary": 0..1, "over": <カーブ>}（省略時は動かない粒）。
    /// over に flicker は使えない — 位置 = 速度の積分が閉形式にならないため、パース時に断る。
    def parseSpeed(path: String, m: Map[String, Json]): Result[JsonError, Scalar] =
        match (JsonCompat.getAtKeyOpt(Root, "speed", m): Result[JsonError, Option[Map[String, Json]]]) {
            case Err(e)       => JsonCompat.atNode(path, Err(e))
            case Ok(None)     => Ok({ base = 0.0, vary = 0.0, over = CurveSpec.Constant })
            case Ok(Some(sm)) => forM (
                base  <- JsonCompat.atNode(path, JsonCompat.numAt("base", sm));
                vary  <- JsonCompat.atNode(path, JsonCompat.numOr("vary", 0.0, sm));
                _vary <- requireVary(path, vary);
                over  <- parseCurveAt(path, "over", sm);
                _int  <- require(not isFlicker(over), path, "speed.over does not support flicker (position needs a closed-form integral)")
            ) yield { base = base, vary = vary, over = over }
        }

    def isFlicker(curve: CurveSpec): Bool =
        match curve { case CurveSpec.Flicker(_) => true case _ => false }

    def requireVary(path: String, vary: Float64): Result[JsonError, Unit] =
        require(vary >= 0.0 and vary <= 1.0, path, "vary must be within 0..1 (got: ${vary})")

    /// "dir": {"base": 度, "spread": 度}（省略時は真上・広がりなし）。
    def parseDir(path: String, m: Map[String, Json]): Result[JsonError, { base = Float64, spread = Float64 }] =
        match (JsonCompat.getAtKeyOpt(Root, "dir", m): Result[JsonError, Option[Map[String, Json]]]) {
            case Err(e)       => JsonCompat.atNode(path, Err(e))
            case Ok(None)     => Ok({ base = 0.0, spread = 0.0 })
            case Ok(Some(dm)) => forM (
                base   <- JsonCompat.atNode(path, JsonCompat.numOr("base", 0.0, dm));
                spread <- JsonCompat.atNode(path, JsonCompat.numOr("spread", 0.0, dm))
            ) yield { base = base, spread = spread }
        }

    /// key のカーブ（省略時 constant）。{"kind": "..."} の 6 形 + fadeOut 別名。
    def parseCurveAt(path: String, key: String, m: Map[String, Json]): Result[JsonError, CurveSpec] =
        match Map.get(key, m) {
            case None              => Ok(CurveSpec.Constant)
            case Some(JObject(cm)) => JsonCompat.atNode(path, parseCurveObj(cm))
            case Some(_)           =>
                JsonCompat.atNode(path, Err(JsonCompat.jsonError(Root, Set#{"${key} must be an object {\"kind\": ...}"})))
        }

    def parseCurveObj(cm: Map[String, Json]): Result[JsonError, CurveSpec] =
        forM (
            kind  <- (JsonCompat.getAtKey(Root, "kind", cm): Result[JsonError, String]);
            curve <- parseCurveKind(kind, cm)
        ) yield curve

    def parseCurveKind(kind: String, cm: Map[String, Json]): Result[JsonError, CurveSpec] =
        match kind {
            case "constant" => Ok(CurveSpec.Constant)
            case "linear"   => forM (
                fromV <- JsonCompat.numAt("from", cm);
                toV   <- JsonCompat.numAt("to", cm)
            ) yield CurveSpec.Linear({ fromV = fromV, toV = toV })
            case "fadeOut"  => Ok(CurveSpec.Linear({ fromV = 1.0, toV = 0.0 }))
            case "easeIn"   => JsonCompat.numOr("power", 2.0, cm) |> Result.map(p -> CurveSpec.EaseIn({ power = p }))
            case "easeOut"  => JsonCompat.numOr("power", 2.0, cm) |> Result.map(p -> CurveSpec.EaseOut({ power = p }))
            case "peak"     => JsonCompat.numAt("at", cm) |> Result.flatMap(at ->
                if (at < 0.0 or at > 1.0)
                    Err(JsonCompat.jsonError(Root, Set#{"peak 'at' must be within 0..1 (got: ${at})"}))
                else Ok(CurveSpec.Peak({ at = at })))
            case "flicker"  => forM (
                rate   <- JsonCompat.numAt("rate", cm);
                amount <- JsonCompat.numOr("amount", 1.0, cm)
            ) yield CurveSpec.Flicker({ rate = rate, amount = amount })
            case unknown    => Err(JsonCompat.jsonError(Root,
                Set#{"kind must be constant|linear|fadeOut|easeIn|easeOut|peak|flicker (got: ${unknown})"}))
        }
}
