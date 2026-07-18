// ShaderJson — シェーダー面の宣言（ShaderDoc.Spec）を JSON と相互変換する codec。
// これで「流れの速さ・網目サイズ・色」を engine を触らず *.shader.json の保存だけで即調整できる
// （App.watchFile によるホットリロードの受け皿）。手本は LightDoc（light.json）と同じ流儀:
//   - parse は純粋（Json -> Result[JsonError, Spec]）、IO は load だけ。
//   - 壊れた json は Err で返し、呼び側が getWithDefault でフォールバック（fail-open）。
//
// Field/Shade/Out は再帰 enum なので、タグ discriminant "kind" で分岐する再帰エンコード。
//   値の場: {"kind":"const","value":..} / {"kind":"uv","axis":"u"} /
//           {"kind":"worley","scale":..,"seed":..,"out":"f2mf1"} /
//           {"kind":"fbm","octaves":..,"scale":..,"seed":..} /
//           {"kind":"smoothstep","lo":..,"hi":..,"of":{..}} /
//           {"kind":"scaled","factor":..,"scroll":{"x":..,"y":..},"of":{..}} /
//           {"kind":"warp","amount":..,"scale":..,"seed":..,"of":{..}} /
//           {"kind":"mix","a":{..},"b":{..},"t":..} / {"kind":"blend","a":{..},"b":{..},"by":{..}}
//   色:     {"kind":"solid","color":<color>} / {"kind":"ramp","lo":<color>,"hi":<color>,"field":{..}}
//   出力:   {"kind":"fill","shade":{..},"alpha":{..}}
//   トップ: {"name":..,"cycleRate":..,"out":{..}}
// 色は "#rrggbb" か {"r":..,"g":..,"b":..}（0..1）。WorleyOut は "f1"/"f2"/"f2mf1"、Axis は "u"/"v"。

mod ShaderJson {
    import java.math.{BigDecimal => JBigDecimal}
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JNumber, JString}
    use Util.Json.JsonError
    use Util.Json.JsonError.JsonError.Decode
    use Util.Json.JsonError.DecodeErrorKind.TypeMismatch
    use Util.Json.JsonPath

    // ========================================================================
    // parse（純粋）
    // ========================================================================

    /// JSON をトップレベルの Spec へ畳む。壊れていれば Err（パス付きの説明）。
    /// shared（bindings）は前方参照のみ・循環は Err・out や後の binding の未定義 Ref も Err。
    pub def parse(json: Json): Result[JsonError, ShaderDoc.Spec] =
        match json {
            case JObject(top) =>
                forM (
                    name      <- strOr("name", "surface", top);
                    cycleRate <- numOr("cycleRate", 0.0, top);
                    bindings  <- parseBindings(top);
                    outJson   <- reqKey("out", top);
                    out       <- parseOut(outJson);
                    _         <- checkOutRefs(bindings, out)
                ) yield ({ name = name, cycleRate = cycleRate, bindings = bindings, out = out }: ShaderDoc.Spec)
            case _ => Err(err("ShaderDoc must be a JSON object"))
        }

    /// トップの "shared":[["name",{..field..}],..] を bindings へ（省略時 Nil）。
    /// 各 binding の Field 内の Ref は「自分より前に定義された名前」だけを指せる
    /// （後方参照・自己参照＝循環は Err・未定義 Ref も Err）。
    def parseBindings(top: Map[String, Json]): Result[JsonError, List[(String, ShaderDoc.Field)]] =
        match Map.get("shared", top) {
            case None => Ok(Nil)
            case Some(JArray(items)) => foldBindings(Vector.toList(items), Nil)
            case Some(_) => Err(err("'shared' must be an array of [name, field]"))
        }

    // 各要素を順に読み、その時点で定義済みの名前だけを Ref できることを検証しながら畳む。
    def foldBindings(items: List[Json], acc: List[(String, ShaderDoc.Field)]):
            Result[JsonError, List[(String, ShaderDoc.Field)]] =
        match items {
            case Nil => Ok(List.reverse(acc))
            case item :: rest =>
                parseBindingEntry(item) |> Result.flatMap(entry ->
                    checkRefsDefined(entry, acc) |> Result.flatMap(_ ->
                        foldBindings(rest, entry :: acc)))
        }

    // ["name", {..field..}] を (name, Field) へ。
    def parseBindingEntry(item: Json): Result[JsonError, (String, ShaderDoc.Field)] =
        match item {
            case JArray(v) => match Vector.toList(v) {
                case JString(name) :: fieldJson :: Nil =>
                    parseField(fieldJson) |> Result.map(field -> (name, field))
                case _ => Err(err("shared entry must be [name(string), field]"))
            }
            case _ => Err(err("shared entry must be [name, field]"))
        }

    // entry の Field 内の Ref が全て「既に定義された名前」（priorNames）に含まれることを検証。
    def checkRefsDefined(entry: (String, ShaderDoc.Field),
                         prior: List[(String, ShaderDoc.Field)]): Result[JsonError, Unit] =
        let (_, field) = entry;
        let priorNames = List.map(nf -> fst(nf), prior);
        let unknown = List.filter(r -> not List.memberOf(r, priorNames), collectRefs(field));
        match unknown {
            case Nil     => Ok()
            case bad :: _ => Err(err("shared binding refs undefined/forward name '${bad}'"))
        }

    // out（shade/alpha）内の Ref が全 binding 名のどれかであることを検証。
    def checkOutRefs(bindings: List[(String, ShaderDoc.Field)], out: ShaderDoc.Out): Result[JsonError, Unit] =
        let names = List.map(nf -> fst(nf), bindings);
        let refs = match out {
            case ShaderDoc.Out.Fill(f) =>
                let shadeRefs = match f#shade {
                    case ShaderDoc.Shade.Solid(_) => Nil
                    case ShaderDoc.Shade.Ramp(r)  => collectRefs(r#field)
                };
                List.append(shadeRefs, collectRefs(f#alpha))
        };
        let unknown = List.filter(r -> not List.memberOf(r, names), refs);
        match unknown {
            case Nil      => Ok()
            case bad :: _ => Err(err("out refs undefined shared name '${bad}'"))
        }

    /// Field の木を走査して現れる Ref 名を集める（検証用の薄いヘルパ）。
    def collectRefs(field: ShaderDoc.Field): List[String] =
        match field {
            case ShaderDoc.Field.Const(_)      => Nil
            case ShaderDoc.Field.Uv(_)         => Nil
            case ShaderDoc.Field.Worley(_)     => Nil
            case ShaderDoc.Field.Fbm(_)        => Nil
            case ShaderDoc.Field.Smoothstep(s) => collectRefs(s#of)
            case ShaderDoc.Field.Scaled(s)     => collectRefs(s#of)
            case ShaderDoc.Field.Warp(wp)      => collectRefs(wp#of)
            case ShaderDoc.Field.Mix(m)        => List.append(collectRefs(m#a), collectRefs(m#b))
            case ShaderDoc.Field.Blend(bl)     => List.append(collectRefs(bl#a),
                                                    List.append(collectRefs(bl#b), collectRefs(bl#by)))
            case ShaderDoc.Field.Disk(_)       => Nil
            case ShaderDoc.Field.Scales(_)     => Nil
            case ShaderDoc.Field.Glints(_)     => Nil
            case ShaderDoc.Field.Ripples(_)    => Nil
            case ShaderDoc.Field.Sparkle(_)    => Nil
            case ShaderDoc.Field.Bin(bn)       => List.append(collectRefs(bn#a), collectRefs(bn#b))
            case ShaderDoc.Field.Un(un)        => collectRefs(un#of)
            case ShaderDoc.Field.Pow(pw)       => collectRefs(pw#of)
            case ShaderDoc.Field.Time(tm)      => collectRefs(tm#offset)
            case ShaderDoc.Field.Tiling(tl)    => collectRefs(tl#of)
            case ShaderDoc.Field.Ref(name)     => name :: Nil
        }

    def parseOut(json: Json): Result[JsonError, ShaderDoc.Out] =
        asObjKind(json, "out") |> Result.flatMap(km -> {
            let (kind, m) = km;
            match kind {
                case "fill" =>
                    forM (
                        shadeJson <- reqKey("shade", m);
                        shade     <- parseShade(shadeJson);
                        alphaJson <- reqKey("alpha", m);
                        alpha     <- parseField(alphaJson)
                    ) yield ShaderDoc.Out.Fill({ shade = shade, alpha = alpha })
                case other => Err(err("unknown out kind: '${other}' (want 'fill')"))
            }
        })

    def parseShade(json: Json): Result[JsonError, ShaderDoc.Shade] =
        asObjKind(json, "shade") |> Result.flatMap(km -> {
            let (kind, m) = km;
            match kind {
                case "solid" =>
                    forM (
                        colorJson <- reqKey("color", m);
                        color     <- parseColor(colorJson)
                    ) yield ShaderDoc.Shade.Solid(color)
                case "ramp" =>
                    forM (
                        loJson    <- reqKey("lo", m);
                        lo        <- parseColor(loJson);
                        hiJson    <- reqKey("hi", m);
                        hi        <- parseColor(hiJson);
                        fieldJson <- reqKey("field", m);
                        field     <- parseField(fieldJson)
                    ) yield ShaderDoc.Shade.Ramp({ lo = lo, hi = hi, field = field })
                case other => Err(err("unknown shade kind: '${other}' (want 'solid'/'ramp')"))
            }
        })

    def parseField(json: Json): Result[JsonError, ShaderDoc.Field] =
        asObjKind(json, "field") |> Result.flatMap(km -> {
            let (kind, m) = km;
            match kind {
                case "const" =>
                    forM (v <- numAt("value", m)) yield ShaderDoc.Field.Const(v)
                case "uv" =>
                    forM (axis <- parseAxis(m)) yield ShaderDoc.Field.Uv({ axis = axis })
                case "worley" =>
                    forM (
                        scale <- numAt("scale", m);
                        seed  <- intAt("seed", m);
                        out   <- parseWorleyOut(m)
                    ) yield ShaderDoc.Field.Worley({ scale = scale, seed = seed, out = out })
                case "fbm" =>
                    forM (
                        octaves <- intAt("octaves", m);
                        scale   <- numAt("scale", m);
                        seed    <- intAt("seed", m)
                    ) yield ShaderDoc.Field.Fbm({ octaves = octaves, scale = scale, seed = seed })
                case "smoothstep" =>
                    forM (
                        lo     <- numAt("lo", m);
                        hi     <- numAt("hi", m);
                        ofJson <- reqKey("of", m);
                        of     <- parseField(ofJson)
                    ) yield ShaderDoc.Field.Smoothstep({ lo = lo, hi = hi, of = of })
                case "scaled" =>
                    forM (
                        factor    <- numAt("factor", m);
                        scroll    <- parseVec2("scroll", m);
                        ofJson    <- reqKey("of", m);
                        of        <- parseField(ofJson)
                    ) yield ShaderDoc.Field.Scaled({ factor = factor, scroll = scroll, of = of })
                case "warp" =>
                    forM (
                        amount <- numAt("amount", m);
                        scale  <- numAt("scale", m);
                        seed   <- intAt("seed", m);
                        ofJson <- reqKey("of", m);
                        of     <- parseField(ofJson)
                    ) yield ShaderDoc.Field.Warp({ amount = amount, scale = scale, seed = seed, of = of })
                case "mix" =>
                    forM (
                        aJson <- reqKey("a", m);
                        a     <- parseField(aJson);
                        bJson <- reqKey("b", m);
                        b     <- parseField(bJson);
                        t     <- numAt("t", m)
                    ) yield ShaderDoc.Field.Mix({ a = a, b = b, t = t })
                case "blend" =>
                    forM (
                        aJson  <- reqKey("a", m);
                        a      <- parseField(aJson);
                        bJson  <- reqKey("b", m);
                        b      <- parseField(bJson);
                        byJson <- reqKey("by", m);
                        by     <- parseField(byJson)
                    ) yield ShaderDoc.Field.Blend({ a = a, b = b, by = by })
                case "disk" =>
                    forM (
                        cx      <- numAt("cx", m);
                        cy      <- numAt("cy", m);
                        radius  <- numAt("radius", m);
                        feather <- numAt("feather", m)
                    ) yield ShaderDoc.Field.Disk({ cx = cx, cy = cy, radius = radius, feather = feather })
                case "scales" =>
                    forM (
                        scale   <- numAt("scale", m);
                        stagger <- numOr("stagger", 0.5, m)
                    ) yield ShaderDoc.Field.Scales({ scale = scale, stagger = stagger })
                case "glints" =>
                    forM (
                        scale   <- numAt("scale", m);
                        rate    <- numOr("rate", 1.0, m);
                        density <- numOr("density", 0.3, m);
                        seed    <- intAt("seed", m)
                    ) yield ShaderDoc.Field.Glints({ scale = scale, rate = rate, density = density, seed = seed })
                case "ripples" =>
                    forM (
                        freq  <- numAt("freq", m);
                        amp   <- numOr("amp", 0.1, m);
                        speed <- numOr("speed", 0.1, m);
                        seed  <- intAt("seed", m)
                    ) yield ShaderDoc.Field.Ripples({ freq = freq, amp = amp, speed = speed, seed = seed })
                case "sparkle" =>
                    forM (
                        scale   <- numAt("scale", m);
                        rate    <- numOr("rate", 1.0, m);
                        density <- numOr("density", 0.3, m);
                        seed    <- intAt("seed", m)
                    ) yield ShaderDoc.Field.Sparkle({ scale = scale, rate = rate, density = density, seed = seed })
                case "math2" =>
                    forM (
                        op    <- parseBinOp(m);
                        aJson <- reqKey("a", m);
                        a     <- parseField(aJson);
                        bJson <- reqKey("b", m);
                        b     <- parseField(bJson)
                    ) yield ShaderDoc.Field.Bin({ op = op, a = a, b = b })
                case "math1" =>
                    forM (
                        op     <- parseUnOp(m);
                        ofJson <- reqKey("of", m);
                        of     <- parseField(ofJson)
                    ) yield ShaderDoc.Field.Un({ op = op, of = of })
                case "pow" =>
                    forM (
                        ofJson <- reqKey("of", m);
                        of     <- parseField(ofJson);
                        p      <- numAt("p", m)
                    ) yield ShaderDoc.Field.Pow({ of = of, p = p })
                case "time" =>
                    forM (
                        scale      <- numAt("scale", m);
                        offsetJson <- reqKey("offset", m);
                        offset     <- parseField(offsetJson)
                    ) yield ShaderDoc.Field.Time({ scale = scale, offset = offset })
                case "tile" =>
                    forM (
                        tiles  <- parseVec2("tiles", m);
                        ofJson <- reqKey("of", m);
                        of     <- parseField(ofJson)
                    ) yield ShaderDoc.Field.Tiling({ tiles = tiles, of = of })
                case "use" =>
                    forM (name <- strAt("name", m)) yield ShaderDoc.Field.Ref(name)
                case other => Err(err("unknown field kind: '${other}'"))
            }
        })

    def parseAxis(m: Map[String, Json]): Result[JsonError, ShaderDoc.Axis] =
        forM (s <- strAt("axis", m); a <- match s {
            case "u" => Ok(ShaderDoc.Axis.U)
            case "v" => Ok(ShaderDoc.Axis.V)
            case other => Err(err("axis must be 'u'/'v' (got '${other}')"))
        }) yield a

    def parseBinOp(m: Map[String, Json]): Result[JsonError, ShaderDoc.BinOp] =
        forM (s <- strAt("op", m); o <- match s {
            case "add"  => Ok(ShaderDoc.BinOp.Add)
            case "sub"  => Ok(ShaderDoc.BinOp.Sub)
            case "mul"  => Ok(ShaderDoc.BinOp.Mul)
            case "min"  => Ok(ShaderDoc.BinOp.Min)
            case "max"  => Ok(ShaderDoc.BinOp.Max)
            case "step" => Ok(ShaderDoc.BinOp.Step)
            case other  => Err(err("math2 op must be add/sub/mul/min/max/step (got '${other}')"))
        }) yield o

    def parseUnOp(m: Map[String, Json]): Result[JsonError, ShaderDoc.UnOp] =
        forM (s <- strAt("op", m); o <- match s {
            case "neg"      => Ok(ShaderDoc.UnOp.Neg)
            case "abs"      => Ok(ShaderDoc.UnOp.Abs)
            case "fract"    => Ok(ShaderDoc.UnOp.Fract)
            case "floor"    => Ok(ShaderDoc.UnOp.Floor)
            case "sin"      => Ok(ShaderDoc.UnOp.Sin)
            case "cos"      => Ok(ShaderDoc.UnOp.Cos)
            case "sat"      => Ok(ShaderDoc.UnOp.Sat)
            case "oneMinus" => Ok(ShaderDoc.UnOp.OneMinus)
            case other      => Err(err("math1 op must be neg/abs/fract/floor/sin/cos/sat/oneMinus (got '${other}')"))
        }) yield o

    def parseWorleyOut(m: Map[String, Json]): Result[JsonError, ShaderDoc.WorleyOut] =
        forM (s <- strAt("out", m); o <- match s {
            case "f1"    => Ok(ShaderDoc.WorleyOut.F1)
            case "f2"    => Ok(ShaderDoc.WorleyOut.F2)
            case "f2mf1" => Ok(ShaderDoc.WorleyOut.F2mF1)
            case other   => Err(err("worley out must be 'f1'/'f2'/'f2mf1' (got '${other}')"))
        }) yield o

    /// "scroll": {"x":.., "y":..} を Vec2 へ。
    def parseVec2(key: String, m: Map[String, Json]): Result[JsonError, Vec2.Vec2] =
        reqKey(key, m) |> Result.flatMap(json -> match json {
            case JObject(vm) => forM (x <- numAt("x", vm); y <- numAt("y", vm)) yield ({ x = x, y = y }: Vec2.Vec2)
            case _           => Err(err("'${key}' must be {x, y}"))
        })

    /// 色: "#rrggbb" か {"r":..,"g":..,"b":..}（0..1）。他 Doc の色表記に合わせた素朴版。
    def parseColor(json: Json): Result[JsonError, Color] =
        match json {
            case JString(s)  => parseHexColor(s)
            case JObject(m)  =>
                forM (r <- numAt("r", m); g <- numAt("g", m); b <- numAt("b", m))
                    yield ({ r = f32(r), g = f32(g), b = f32(b) }: Color)
            case _ => Err(err("color must be \"#rrggbb\" or {r,g,b}"))
        }

    def parseHexColor(s: String): Result[JsonError, Color] =
        let hex = if (String.startsWith({ prefix = "#" }, s)) String.drop(1, s) else s;
        if (String.length(hex) != 6) Err(err("color hex must be #rrggbb (got '${s}')"))
        else match (hexByte(String.slice({ start = 0 }, { end = 2 }, hex)),
                    hexByte(String.slice({ start = 2 }, { end = 4 }, hex)),
                    hexByte(String.slice({ start = 4 }, { end = 6 }, hex))) {
            case (Some(r), Some(g), Some(b)) =>
                Ok({ r = f32(Int32.toFloat64(r) / 255.0),
                     g = f32(Int32.toFloat64(g) / 255.0),
                     b = f32(Int32.toFloat64(b) / 255.0) })
            case _ => Err(err("color hex has non-hex digits: '${s}'"))
        }

    def hexByte(two: String): Option[Int32] =
        Int32.parse(16, two) |> Result.toOption

    // ── Util.Json 小道具（engine 契約層に閉じるため JsonCompat/UiDoc に頼らない）──

    def asObjKind(json: Json, label: String): Result[JsonError, (String, Map[String, Json])] =
        match json {
            case JObject(m) => forM (kind <- strAt("kind", m)) yield (kind, m)
            case _          => Err(err("${label} must be an object with a 'kind'"))
        }

    def reqKey(key: String, m: Map[String, Json]): Result[JsonError, Json] =
        match Map.get(key, m) {
            case Some(j) => Ok(j)
            case None    => Err(err("'${key}' is required"))
        }

    def numAt(key: String, m: Map[String, Json]): Result[JsonError, Float64] =
        reqKey(key, m) |> Result.flatMap(j -> match j {
            case JNumber(bd) => match BigDecimal.tryToFloat64(bd) {
                case Some(v) => Ok(v)
                case None    => Err(err("'${key}' is not a finite number"))
            }
            case _ => Err(err("'${key}' must be a number"))
        })

    def intAt(key: String, m: Map[String, Json]): Result[JsonError, Int32] =
        numAt(key, m) |> Result.flatMap(v -> match Float64.tryToInt32(v) {
            case Some(i) => Ok(i)
            case None    => Err(err("'${key}' must be an integer"))
        })

    def strAt(key: String, m: Map[String, Json]): Result[JsonError, String] =
        reqKey(key, m) |> Result.flatMap(j -> match j {
            case JString(s) => Ok(s)
            case _          => Err(err("'${key}' must be a string"))
        })

    def strOr(key: String, fallback: String, m: Map[String, Json]): Result[JsonError, String] =
        match Map.get(key, m) {
            case None    => Ok(fallback)
            case Some(_) => strAt(key, m)
        }

    def numOr(key: String, fallback: Float64, m: Map[String, Json]): Result[JsonError, Float64] =
        match Map.get(key, m) {
            case None    => Ok(fallback)
            case Some(_) => numAt(key, m)
        }

    def err(msg: String): JsonError =
        Decode(JsonPath.empty(), TypeMismatch(msg))

    def f32(x: Float64): Float32 =
        Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, x)

    // ========================================================================
    // toJson（Spec → Json・往復テスト用）
    // ========================================================================

    pub def toJson(spec: ShaderDoc.Spec): Json =
        // bindings が空なら "shared" を出さない（既存 JSON の round-trip を 1 バイトも変えない）。
        let base = Map#{
            "name"      => JString(spec#name),
            "cycleRate" => num(spec#cycleRate),
            "out"       => outToJson(spec#out)
        };
        let full = if (List.isEmpty(spec#bindings)) base
                   else Map.insert("shared", bindingsToJson(spec#bindings), base);
        JObject(full)

    def bindingsToJson(bindings: List[(String, ShaderDoc.Field)]): Json =
        JArray(List.toVector(List.map(nf -> {
            let (name, field) = nf;
            JArray(Vector#{ JString(name), fieldToJson(field) })
        }, bindings)))

    def outToJson(out: ShaderDoc.Out): Json =
        match out {
            case ShaderDoc.Out.Fill(f) =>
                JObject(Map#{ "kind" => JString("fill"),
                              "shade" => shadeToJson(f#shade),
                              "alpha" => fieldToJson(f#alpha) })
        }

    def shadeToJson(shade: ShaderDoc.Shade): Json =
        match shade {
            case ShaderDoc.Shade.Solid(c) =>
                JObject(Map#{ "kind" => JString("solid"), "color" => colorToJson(c) })
            case ShaderDoc.Shade.Ramp(r) =>
                JObject(Map#{ "kind" => JString("ramp"),
                              "lo" => colorToJson(r#lo), "hi" => colorToJson(r#hi),
                              "field" => fieldToJson(r#field) })
        }

    def fieldToJson(field: ShaderDoc.Field): Json =
        match field {
            case ShaderDoc.Field.Const(v) =>
                JObject(Map#{ "kind" => JString("const"), "value" => num(v) })
            case ShaderDoc.Field.Uv(u) =>
                JObject(Map#{ "kind" => JString("uv"), "axis" => JString(axisStr(u#axis)) })
            case ShaderDoc.Field.Worley(w) =>
                JObject(Map#{ "kind" => JString("worley"), "scale" => num(w#scale),
                              "seed" => inum(w#seed), "out" => JString(worleyOutStr(w#out)) })
            case ShaderDoc.Field.Fbm(b) =>
                JObject(Map#{ "kind" => JString("fbm"), "octaves" => inum(b#octaves),
                              "scale" => num(b#scale), "seed" => inum(b#seed) })
            case ShaderDoc.Field.Smoothstep(s) =>
                JObject(Map#{ "kind" => JString("smoothstep"), "lo" => num(s#lo),
                              "hi" => num(s#hi), "of" => fieldToJson(s#of) })
            case ShaderDoc.Field.Scaled(s) =>
                JObject(Map#{ "kind" => JString("scaled"), "factor" => num(s#factor),
                              "scroll" => vec2ToJson(s#scroll), "of" => fieldToJson(s#of) })
            case ShaderDoc.Field.Warp(wp) =>
                JObject(Map#{ "kind" => JString("warp"), "amount" => num(wp#amount),
                              "scale" => num(wp#scale), "seed" => inum(wp#seed),
                              "of" => fieldToJson(wp#of) })
            case ShaderDoc.Field.Mix(m) =>
                JObject(Map#{ "kind" => JString("mix"), "a" => fieldToJson(m#a),
                              "b" => fieldToJson(m#b), "t" => num(m#t) })
            case ShaderDoc.Field.Blend(bl) =>
                JObject(Map#{ "kind" => JString("blend"), "a" => fieldToJson(bl#a),
                              "b" => fieldToJson(bl#b), "by" => fieldToJson(bl#by) })
            case ShaderDoc.Field.Disk(d) =>
                JObject(Map#{ "kind" => JString("disk"), "cx" => num(d#cx), "cy" => num(d#cy),
                              "radius" => num(d#radius), "feather" => num(d#feather) })
            case ShaderDoc.Field.Scales(sc) =>
                JObject(Map#{ "kind" => JString("scales"), "scale" => num(sc#scale),
                              "stagger" => num(sc#stagger) })
            case ShaderDoc.Field.Glints(g) =>
                JObject(Map#{ "kind" => JString("glints"), "scale" => num(g#scale),
                              "rate" => num(g#rate), "density" => num(g#density),
                              "seed" => inum(g#seed) })
            case ShaderDoc.Field.Ripples(rp) =>
                JObject(Map#{ "kind" => JString("ripples"), "freq" => num(rp#freq),
                              "amp" => num(rp#amp), "speed" => num(rp#speed),
                              "seed" => inum(rp#seed) })
            case ShaderDoc.Field.Sparkle(sp) =>
                JObject(Map#{ "kind" => JString("sparkle"), "scale" => num(sp#scale),
                              "rate" => num(sp#rate), "density" => num(sp#density),
                              "seed" => inum(sp#seed) })
            case ShaderDoc.Field.Bin(bn) =>
                JObject(Map#{ "kind" => JString("math2"), "op" => JString(binOpStr(bn#op)),
                              "a" => fieldToJson(bn#a), "b" => fieldToJson(bn#b) })
            case ShaderDoc.Field.Un(un) =>
                JObject(Map#{ "kind" => JString("math1"), "op" => JString(unOpStr(un#op)),
                              "of" => fieldToJson(un#of) })
            case ShaderDoc.Field.Pow(pw) =>
                JObject(Map#{ "kind" => JString("pow"), "of" => fieldToJson(pw#of), "p" => num(pw#p) })
            case ShaderDoc.Field.Time(tm) =>
                JObject(Map#{ "kind" => JString("time"), "scale" => num(tm#scale),
                              "offset" => fieldToJson(tm#offset) })
            case ShaderDoc.Field.Tiling(tl) =>
                JObject(Map#{ "kind" => JString("tile"), "tiles" => vec2ToJson(tl#tiles),
                              "of" => fieldToJson(tl#of) })
            case ShaderDoc.Field.Ref(name) =>
                JObject(Map#{ "kind" => JString("use"), "name" => JString(name) })
        }

    def binOpStr(op: ShaderDoc.BinOp): String =
        match op {
            case ShaderDoc.BinOp.Add  => "add"
            case ShaderDoc.BinOp.Sub  => "sub"
            case ShaderDoc.BinOp.Mul  => "mul"
            case ShaderDoc.BinOp.Min  => "min"
            case ShaderDoc.BinOp.Max  => "max"
            case ShaderDoc.BinOp.Step => "step"
        }

    def unOpStr(op: ShaderDoc.UnOp): String =
        match op {
            case ShaderDoc.UnOp.Neg      => "neg"
            case ShaderDoc.UnOp.Abs      => "abs"
            case ShaderDoc.UnOp.Fract    => "fract"
            case ShaderDoc.UnOp.Floor    => "floor"
            case ShaderDoc.UnOp.Sin      => "sin"
            case ShaderDoc.UnOp.Cos      => "cos"
            case ShaderDoc.UnOp.Sat      => "sat"
            case ShaderDoc.UnOp.OneMinus => "oneMinus"
        }

    def colorToJson(c: Color): Json =
        JObject(Map#{ "r" => num(Float32.toFloat64(c#r)),
                      "g" => num(Float32.toFloat64(c#g)),
                      "b" => num(Float32.toFloat64(c#b)) })

    def vec2ToJson(v: Vec2.Vec2): Json =
        JObject(Map#{ "x" => num(v#x), "y" => num(v#y) })

    def axisStr(a: ShaderDoc.Axis): String =
        match a { case ShaderDoc.Axis.U => "u" case ShaderDoc.Axis.V => "v" }

    def worleyOutStr(o: ShaderDoc.WorleyOut): String =
        match o {
            case ShaderDoc.WorleyOut.F1    => "f1"
            case ShaderDoc.WorleyOut.F2    => "f2"
            case ShaderDoc.WorleyOut.F2mF1 => "f2mf1"
        }

    def num(x: Float64): Json =
        JNumber(JBigDecimal.valueOf(x))

    def inum(n: Int32): Json =
        JNumber(JBigDecimal.valueOf(Int32.toFloat64(n)))

    // ========================================================================
    // load（IO はここだけ・parse は純粋のまま）
    // ========================================================================

    /// path を読んで Spec にする（読めない・崩れているときは Err）。フォールバックは呼び側が
    /// getWithDefault で与える（LightDoc.load と同じ流儀・fail-open）。
    pub def load(path: String): Result[JsonError, ShaderDoc.Spec] \ Fs.FileRead =
        let content = run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead;
        content
            |> Result.mapErr(readErr -> err("failed to read '${path}': ${readErr}"))
            |> Result.flatMap(text -> Util.Json.parse(String.trim(text)))
            |> Result.flatMap(parse)
}
