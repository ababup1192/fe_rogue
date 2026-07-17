// TestLightDoc — light.json 方言の唯一のパーサ（LightDoc）を固定する。
mod TestLightDoc {

    // ── 道具 ──

    def parseDoc(s: String): Option[LightDoc.Spec] =
        JsonCompat.parse(s) |> Option.flatMap(json -> LightDoc.parse(json) |> Result.toOption)

    /// doc のパースエラーを編集者向け文言（describe）で返す（成功や JSON 構文エラーは目印文字列）。
    def errTextOf(doc: String): String =
        match JsonCompat.parse(doc) {
            case None       => "(json syntax error)"
            case Some(json) => match LightDoc.parse(json) {
                case Ok(_)  => "(parsed ok)"
                case Err(e) => JsonCompat.describe(e)
            }
        }

    def firstLight(spec: LightDoc.Spec): Option[LightDoc.LightSpec] =
        List.head(spec#lights)

    def colorTuple(c: Color): (Float32, Float32, Float32) =
        (c#r, c#g, c#b)

    /// 相談で承認したカンテラ相当のスペック（light.json 語彙の正の形）。
    def lanternDoc(): String =
        "{ \"darkness\": 0.95,"
        + "  \"rim\": { \"width\": 2.5, \"strength\": 0.5 },"
        + "  \"haloDiameterFactor\": 1.25,"
        + "  \"lights\": [ { \"at\": [160,120], \"radius\": 48, \"color\": \"#ffbf66\", \"halo\": 0.35 } ] }"

    /// 必須項目（at/radius/color）だけの最小ドキュメント（既定値のテスト用）。
    def minimalDoc(): String =
        "{ \"lights\": [ { \"at\": [10,20], \"radius\": 5, \"color\": \"#ff0000\" } ] }"

    // ════════════════════════════════════════════════════════
    // parse: 正の形（lanternDoc）— 具体値 pin
    // ════════════════════════════════════════════════════════

    /// トップレベル: darkness / rim / haloDiameterFactor が読める。
    @Test
    def testParseTopLevel(): Unit \ Assert =
        let got = parseDoc(lanternDoc())
            |> Option.map(spec -> (spec#darkness, spec#rimWidth, spec#rimStrength, spec#haloDiameterFactor));
        Assert.assertEq(expected = Some((0.95, 2.5, 0.5, 1.25)), got)

    /// light 1 個の at / radius / color / halo。
    @Test
    def testParseLight(): Unit \ Assert =
        let got = parseDoc(lanternDoc()) |> Option.flatMap(firstLight)
            |> Option.map(l -> (l#at#x, l#at#y, l#radius, colorTuple(l#color), l#halo));
        let ch = (v: Int32) -> Float64.truncateToFloat32(Int32.toFloat64(v) / 255.0);
        Assert.assertEq(
            expected = Some((160.0, 120.0, 48.0, (ch(255), ch(191), ch(102)), 0.35)),
            got)

    /// lights の個数。
    @Test
    def testParseLightsCount(): Unit \ Assert =
        Assert.assertEq(
            expected = Some(1),
            parseDoc(lanternDoc()) |> Option.map(spec -> List.length(spec#lights)))

    // ════════════════════════════════════════════════════════
    // parse: 既定値
    // ════════════════════════════════════════════════════════

    /// トップレベル全省略（lights のみ）: darkness=0.95 / rim=Shadow既定 /
    /// haloDiameterFactor=Light.defaultHaloDiameterFactor / halo=0.35。
    @Test
    def testParseDefaults(): Unit \ Assert =
        let got = parseDoc(minimalDoc())
            |> Option.map(spec -> (spec#darkness, spec#rimWidth, spec#rimStrength, spec#haloDiameterFactor));
        Assert.assertEq(
            expected = Some((0.95, Shadow.defaultRimWidth(), Shadow.defaultRimStrength(), Light.defaultHaloDiameterFactor())),
            got)

    /// light の halo 省略時は 0.35。
    @Test
    def testParseLightHaloDefault(): Unit \ Assert =
        let got = parseDoc(minimalDoc()) |> Option.flatMap(firstLight) |> Option.map(l -> l#halo);
        Assert.assertEq(expected = Some(0.35), got)

    /// lights 自体を省略すると空リスト（暗闇だけの演出も正当）。
    @Test
    def testParseLightsOmittedIsEmpty(): Unit \ Assert =
        let doc = "{ \"darkness\": 0.8 }";
        Assert.assertEq(expected = Some(0), parseDoc(doc) |> Option.map(spec -> List.length(spec#lights)))

    /// note と "//" コメントキーは fx.json / ui.json と同じ扱い（note は保持・コメントは無視）。
    @Test
    def testParseNoteAndCommentKeys(): Unit \ Assert =
        let doc = "{ \"//\": \"memo\", \"note\": \"カンテラの質感\", \"lights\": [] }";
        Assert.assertEq(
            expected = Some(Some("カンテラの質感")),
            parseDoc(doc) |> Option.map(spec -> spec#note))

    /// color は {"hsv":[...]} / {"rgb":[...]} も読める（ui.json と同じ方言）。
    @Test
    def testParseColorVariants(): Unit \ Assert =
        let doc = "{ \"lights\": [ { \"at\": [0,0], \"radius\": 1, \"color\": {\"rgb\":[0.1,0.2,0.3]} } ] }";
        let got = parseDoc(doc) |> Option.flatMap(firstLight) |> Option.map(l -> colorTuple(l#color));
        Assert.assertEq(expected = Some((0.1f32, 0.2f32, 0.3f32)), got)

    // ════════════════════════════════════════════════════════
    // parse: エラー（形違い・パス付き）
    // ════════════════════════════════════════════════════════

    /// パースできたかどうかだけを見る（Spec 自体は Color を含み Eq/ToString が無いため）。
    def parses(doc: String): Bool =
        match parseDoc(doc) { case Some(_) => true case None => false }

    /// トップレベルが配列など JSON オブジェクトでなければ None、
    /// 必須項目欠落・値の範囲外・形違い・未サポート version もまとめて弾く。
    @Test
    def testErrorCases(): Unit \ Assert =
        Assert.assertEq(expected = (false, false, false, false, false),
            (parses("[1,2,3]"),
             parses("{ \"lights\": [ { \"at\": [0,0], \"radius\": 0, \"color\": \"#ffffff\" } ] }"),
             parses("{ \"lights\": [ { \"at\": [0,0], \"radius\": 1, \"color\": \"#ffffff\", \"halo\": 1.5 } ] }"),
             parses("{ \"lights\": [ { \"at\": [0], \"radius\": 1, \"color\": \"#ffffff\" } ] }"),
             parses("{ \"version\": 2, \"lights\": [] }")))

    /// light に radius が無ければ弾く（エラー文言に lights[0] を含む）。
    @Test
    def testErrorMissingRadius(): Unit \ Assert =
        let doc = "{ \"lights\": [ { \"at\": [0,0], \"color\": \"#ffffff\" } ] }";
        Assert.assertEq(expected = (false, true),
            (parses(doc), String.contains(substr = "lights[0]", errTextOf(doc))))

    /// 壊れた JSON 構文はそもそも Json にならない。
    @Test
    def testErrorJsonSyntax(): Unit \ Assert =
        Assert.assertEq(expected = "(json syntax error)", errTextOf("{ not json "))

    // ════════════════════════════════════════════════════════
    // toConfig / toConfigWithLights
    // ════════════════════════════════════════════════════════

    def ctxFor(occluders: List[List[Vec2.Vec2]]): { occluders = List[List[Vec2.Vec2]], viewport = Vec2.Vec2,
                                                     glow = Light.GlowAssets, z = Int32 } =
        { occluders = occluders, viewport = { x = 320.0, y = 240.0 }, glow = Light.defaultGlowAssets(), z = 10 }

    /// toConfig は spec の質感値 + ctx の occluders/viewport/glow/z をそのまま SceneLightConfig へ運ぶ。
    @Test
    def testToConfigCarriesSpecAndCtx(): Unit \ Assert =
        let spec = parseDoc(lanternDoc()) |> Option.getWithDefault(LightDoc.empty());
        let cfg = LightDoc.toConfig(spec, ctxFor(Nil));
        Assert.assertEq(
            expected = (0.95, 2.5, 0.5, 1.25, 10, 1),
            (cfg#darkness, cfg#rimWidth, cfg#rimStrength, cfg#haloDiameterFactor, cfg#z, List.length(cfg#lights)))

    /// toConfigWithLights は spec の lights を無視し runtimeLights に丸ごと差し替える
    /// （「json は質感、位置はゲーム」の分業）。
    @Test
    def testToConfigWithLightsReplacesLights(): Unit \ Assert =
        let spec = parseDoc(lanternDoc()) |> Option.getWithDefault(LightDoc.empty());
        let runtimeLight = { at = { x = 5.0, y = 6.0 }, radius = 9.0,
                             color = { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, halo = 0.2 };
        let cfg = LightDoc.toConfigWithLights(spec, runtimeLight :: Nil, ctxFor(Nil));
        Assert.assertEq(
            expected = Some((5.0, 6.0)),
            List.head(cfg#lights) |> Option.map(l -> (l#at#x, l#at#y)))

    /// LightDoc.empty() は Light.items にそのまま渡してもクラッシュしない
    /// （lights=Nil なので全面暗幕のみになる ＝ 未読込時の fail-open な絵）。
    @Test
    def testEmptySpecFeedsLightItems(): Unit \ Assert =
        let cfg = LightDoc.toConfig(LightDoc.empty(), ctxFor(Nil));
        let (drawables, _) = Render.draw(Light.items(cfg));
        Assert.assertEq(expected = 1, List.length(drawables))
}
