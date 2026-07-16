// TestFxDoc — fx.json 方言の唯一のパーサ（FxDoc）を固定する。
// CurveSpec は中身がレコードで Eq を持たないため、(タグ, 値, 値) に射影して比べる。
mod TestFxDoc {

    // ── 道具 ──

    def parseDoc(s: String): Option[FxDoc.Spec] =
        JsonCompat.parse(s) |> Option.flatMap(json -> FxDoc.parse(json) |> Result.toOption)

    /// doc のパースエラーを編集者向け文言（describe）で返す（成功や JSON 構文エラーは目印文字列）。
    def errTextOf(doc: String): String =
        match JsonCompat.parse(doc) {
            case None       => "(json syntax error)"
            case Some(json) => match FxDoc.parse(json) {
                case Ok(_)  => "(parsed ok)"
                case Err(e) => JsonCompat.describe(e)
            }
        }

    def firstEmitter(spec: FxDoc.Spec): Option[FxDoc.Emitter] =
        List.head(spec#emitters)

    /// カーブを (種類, 値1, 値2) に射影する（linear = from/to・ease = power・peak = at・flicker = rate/amount）。
    def curve3(c: FxDoc.CurveSpec): (String, Float64, Float64) =
        match c {
            case FxDoc.CurveSpec.Constant   => ("constant", 0.0, 0.0)
            case FxDoc.CurveSpec.Linear(l)  => ("linear", l#fromV, l#toV)
            case FxDoc.CurveSpec.EaseIn(e)  => ("easeIn", e#power, 0.0)
            case FxDoc.CurveSpec.EaseOut(e) => ("easeOut", e#power, 0.0)
            case FxDoc.CurveSpec.Peak(p)    => ("peak", p#at, 0.0)
            case FxDoc.CurveSpec.Flicker(f) => ("flicker", f#rate, f#amount)
        }

    def shapeTag(s: FxDoc.Shape): String =
        match s { case FxDoc.Shape.Circle => "circle" case FxDoc.Shape.Box => "box" }

    def blendTag(b: DrawCmd.BlendMode): String =
        match b { case DrawCmd.BlendMode.Normal => "normal" case DrawCmd.BlendMode.Add => "add" case DrawCmd.BlendMode.Multiply => "multiply" }

    def colorTuple(c: Color): (Float32, Float32, Float32) =
        (c#r, c#g, c#b)

    /// 相談で承認した explosion スペック（fx.json 語彙の正の形）。
    def explosionDoc(): String =
        "{ \"name\": \"explosion\", \"duration\": 0.9,"
        + "  \"emitters\": ["
        + "    { \"name\": \"sparks\", \"count\": 20, \"shape\": \"circle\", \"size\": 3,"
        + "      \"color\": [\"#fff7c0\", \"#ff8a3d\", \"#69323a\"],"
        + "      \"life\":  { \"base\": 0.5, \"vary\": 0.2 },"
        + "      \"speed\": { \"base\": 140, \"vary\": 0.3, \"over\": {\"kind\": \"easeOut\", \"power\": 2.4} },"
        + "      \"dir\":   { \"base\": 0, \"spread\": 360 },"
        + "      \"sizeOver\": {\"kind\": \"peak\", \"at\": 0.25},"
        + "      \"alphaOver\": {\"kind\": \"fadeOut\"},"
        + "      \"blend\": \"add\" } ] }"

    /// 必須項目だけの最小 emitter（既定値のテスト用）。
    def minimalDoc(): String =
        "{ \"name\": \"m\", \"duration\": 1.0, \"emitters\": ["
        + "  { \"name\": \"dust\", \"count\": 3, \"size\": 2,"
        + "    \"color\": [\"#ffffff\"], \"life\": { \"base\": 0.4 } } ] }"

    // ════════════════════════════════════════════════════════
    // parse: 正の形（explosion スペック）
    // ════════════════════════════════════════════════════════

    /// トップレベル: name / duration / emitters 1 本が読める。
    @Test
    def testParseTopLevel(): Unit \ Assert =
        let got = parseDoc(explosionDoc())
            |> Option.map(spec -> (spec#name, spec#duration, List.length(spec#emitters)));
        Assert.assertEq(expected = Some(("explosion", 0.9, 1)), got)

    /// emitter の素の値: name / count / shape / size / blend / 色数。
    @Test
    def testParseEmitterBasics(): Unit \ Assert =
        let got = parseDoc(explosionDoc()) |> Option.flatMap(firstEmitter)
            |> Option.map(em -> (em#name, em#count, shapeTag(em#shape), em#size,
                                 blendTag(em#blend), List.length(em#color)));
        Assert.assertEq(expected = Some(("sparks", 20, "circle", 3.0, "add", 3)), got)

    /// life / speed / dir の数値と、speed.over の easeOut power。
    @Test
    def testParseLifeSpeedDir(): Unit \ Assert =
        let got = parseDoc(explosionDoc()) |> Option.flatMap(firstEmitter)
            |> Option.map(em -> (em#life#base, em#life#vary,
                                 em#speed#base, em#speed#vary, curve3(em#speed#over),
                                 em#dir#base, em#dir#spread));
        Assert.assertEq(
            expected = Some((0.5, 0.2, 140.0, 0.3, ("easeOut", 2.4, 0.0), 0.0, 360.0)),
            got)

    /// sizeOver = peak {at}・alphaOver の fadeOut は linear {1, 0} の別名に畳まれる。
    @Test
    def testParseCurves(): Unit \ Assert =
        let got = parseDoc(explosionDoc()) |> Option.flatMap(firstEmitter)
            |> Option.map(em -> (curve3(em#sizeOver), curve3(em#alphaOver)));
        Assert.assertEq(
            expected = Some((("peak", 0.25, 0.0), ("linear", 1.0, 0.0))),
            got)

    /// 色グラデの端: 先頭 #fff7c0 と末尾 #69323a（16 進 → 0..1 の丸めは 1/255 の分数）。
    @Test
    def testParseColorEnds(): Unit \ Assert =
        let ch = (v: Int32) -> Float64.truncateToFloat32(Int32.toFloat64(v) / 255.0);
        let got = parseDoc(explosionDoc()) |> Option.flatMap(firstEmitter)
            |> Option.map(em -> (List.head(em#color) |> Option.map(colorTuple),
                                 List.last(em#color) |> Option.map(colorTuple)));
        Assert.assertEq(
            expected = Some((Some((ch(255), ch(247), ch(192))), Some((ch(105), ch(50), ch(58))))),
            got)

    // ════════════════════════════════════════════════════════
    // parse: 既定値と付帯情報
    // ════════════════════════════════════════════════════════

    /// 省略時の既定: shape=circle / blend=normal / speed=止まったまま / dir=真上・広がり 0 /
    /// カーブ=constant / vary=0 / zIndex=0。
    @Test
    def testParseDefaults(): Unit \ Assert =
        let got = parseDoc(minimalDoc()) |> Option.flatMap(firstEmitter)
            |> Option.map(em -> (shapeTag(em#shape), blendTag(em#blend),
                                 em#speed#base, em#speed#vary, curve3(em#speed#over),
                                 em#dir#base, em#dir#spread, em#life#vary,
                                 curve3(em#sizeOver), curve3(em#alphaOver), em#zIndex));
        Assert.assertEq(
            expected = Some(("circle", "normal", 0.0, 0.0, ("constant", 0.0, 0.0),
                             0.0, 0.0, 0.0,
                             ("constant", 0.0, 0.0), ("constant", 0.0, 0.0), 0)),
            got)

    /// note と "//" コメントキーは ui.json と同じ扱い（note は保持・コメントは無視）。
    @Test
    def testParseNoteAndCommentKeys(): Unit \ Assert =
        let doc = "{ \"//\": \"memo\", \"note\": \"爆発の素\", \"name\": \"m\", \"duration\": 1.0,"
            + " \"emitters\": [ { \"//why\": \"x\", \"name\": \"d\", \"count\": 1, \"size\": 2,"
            + " \"color\": [\"#ffffff\"], \"life\": { \"base\": 0.4 } } ] }";
        Assert.assertEq(
            expected = Some(Some("爆発の素")),
            parseDoc(doc) |> Option.map(spec -> spec#note))

    /// shape=box と flicker カーブ（rate/amount）も読める。
    @Test
    def testParseBoxAndFlicker(): Unit \ Assert =
        let doc = "{ \"name\": \"m\", \"duration\": 1.0, \"emitters\": ["
            + " { \"name\": \"d\", \"count\": 1, \"shape\": \"box\", \"size\": 2,"
            + " \"color\": [\"#ffffff\"], \"life\": { \"base\": 0.4 },"
            + " \"alphaOver\": {\"kind\": \"flicker\", \"rate\": 8, \"amount\": 0.6} } ] }";
        let got = parseDoc(doc) |> Option.flatMap(firstEmitter)
            |> Option.map(em -> (shapeTag(em#shape), curve3(em#alphaOver)));
        Assert.assertEq(expected = Some(("box", ("flicker", 8.0, 0.6))), got)

    // ════════════════════════════════════════════════════════
    // parse: エラー（ノードパス付き）
    // ════════════════════════════════════════════════════════

    /// 必須の color 欠落: エラー文言が emitters[0] を指す。
    @Test
    def testErrorCarriesEmitterPath(): Unit \ Assert =
        let doc = "{ \"name\": \"m\", \"duration\": 1.0, \"emitters\": ["
            + " { \"name\": \"d\", \"count\": 1, \"size\": 2, \"life\": { \"base\": 0.4 } } ] }";
        Assert.assertEq(expected = true,
            String.contains(substr = "emitters[0]", errTextOf(doc)))

    /// speed.over の flicker は閉形式の積分が無いのでパース時に断る（パスは emitters[0].speed）。
    @Test
    def testErrorSpeedFlickerRejected(): Unit \ Assert =
        let doc = "{ \"name\": \"m\", \"duration\": 1.0, \"emitters\": ["
            + " { \"name\": \"d\", \"count\": 1, \"size\": 2, \"color\": [\"#ffffff\"],"
            + " \"life\": { \"base\": 0.4 },"
            + " \"speed\": { \"base\": 10, \"over\": {\"kind\": \"flicker\", \"rate\": 4} } } ] }";
        let msg = errTextOf(doc);
        Assert.assertEq(expected = (true, true),
            (String.contains(substr = "emitters[0].speed", msg),
             String.contains(substr = "flicker", msg)))

    /// まとめて弾く系: 知らないカーブ kind / vary の範囲外 / emitters 空 / version 2 / blend 不正。
    @Test
    def testErrorCases(): Unit \ Assert =
        let base = (body: String) -> "{ \"name\": \"m\", \"duration\": 1.0, \"emitters\": ["
            + " { \"name\": \"d\", \"count\": 1, \"size\": 2, \"color\": [\"#ffffff\"],"
            + " \"life\": { \"base\": 0.4 }" + body + " } ] }";
        let parses = (doc: String) -> match parseDoc(doc) { case Some(_) => true case None => false };
        Assert.assertEq(expected = (false, false, false, false, false),
            (parses(base(", \"sizeOver\": {\"kind\": \"bounce\"}")),
             parses(base(", \"speed\": { \"base\": 1, \"vary\": 1.5 }")),
             parses("{ \"name\": \"m\", \"duration\": 1.0, \"emitters\": [] }"),
             parses("{ \"version\": 2, \"name\": \"m\", \"duration\": 1.0, \"emitters\": [] }"),
             parses(base(", \"blend\": \"screen\""))))
}
