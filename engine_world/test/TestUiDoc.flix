// TestUiDoc — ui.json 方言の唯一のパーサ（UiDoc）と、UiSpec 経路との一致を固定する。
// enum に Eq を要求しない「射影してタプル比較」流。Float の期待値は割り切れる入力に限る。
mod TestUiDoc {

    // ── 道具 ──

    def parseDoc(s: String): Option[UiDoc.Spec] =
        JsonCompat.parse(s) |> Option.flatMap(json -> UiDoc.parse(json) |> Result.toOption)

    /// パースが通るか（エラー系テスト用）。JSON 構文エラーも false。
    def parses(s: String): Bool =
        match parseDoc(s) { case Some(_) => true case None => false }

    def childrenOf(spec: UiDoc.Spec): List[UiDoc.Spec] =
        match spec { case UiDoc.Spec.Spec(node) => node#children }

    def widgetOf(spec: UiDoc.Spec): UiDoc.Widget =
        match spec { case UiDoc.Spec.Spec(node) => node#widget }

    def styleOf(spec: UiDoc.Spec): UiLayout.Style =
        match spec { case UiDoc.Spec.Spec(node) => node#style }

    def firstChild(spec: UiDoc.Spec): Option[UiDoc.Spec] =
        List.head(childrenOf(spec))

    def colorTuple(c: Color): (Float32, Float32, Float32) =
        (c#r, c#g, c#b)

    def sizeTuple(v: Vec2.Vec2): (Float64, Float64) =
        (v#x, v#y)

    def rect4(r: Rect2.Rect2): (Float64, Float64, Float64, Float64) =
        (r#position#x, r#position#y, r#size#x, r#size#y)

    /// SizeSpec は ToString を持たないので (タグ, 値) に射影して比べる。
    def sizeSpec2(s: UiLayout.SizeSpec): (String, Float64) =
        match s {
            case UiLayout.SizeSpec.Auto    => ("auto", 0.0)
            case UiLayout.SizeSpec.Px(v)   => ("px", v)
            case UiLayout.SizeSpec.Grow(w) => ("grow", w)
        }

    /// テキスト計測用のダミーアトラス（グリフ無し）。FontAtlas は単純レコードなので直構築できる。
    def dummyAtlas(): FontAtlas =
        { textureName = "dummy", fontSize = 32.0, textureSize = 256.0,
          ascent = 0.0, descent = 0.0, lineGap = 0.0, glyphs = Map.empty() }

    // ── parse: 基本形 ──

    @Test
    def testParseCircleNode(): Unit \ Assert =
        let doc = "{\"root\": {\"name\":\"g\",\"children\":["
                + "{\"name\":\"c\",\"widget\":\"circle\",\"radius\":18.0,\"color\":\"#ff0000\",\"zIndex\":10}]}}";
        let got = parseDoc(doc) |> Option.flatMap(firstChild) |> Option.flatMap(child ->
            match widgetOf(child) {
                case UiDoc.Widget.ShapeW(s) => match s#shape {
                    case UiShape.Shape.CircleS(c) => Some((UiDoc.nameOf(child), c#radius, s#zIndex, colorTuple(s#color)))
                    case _ => None
                }
                case _ => None
            });
        Assert.assertEq(expected = Some(("c", 18.0, 10, (1.0f32, 0.0f32, 0.0f32))), got)

    @Test
    def testShapeIntrinsicBecomesPxStyle(): Unit \ Assert =
        // width/height 未指定の circle は内在サイズ 2r が Px として敷かれる。
        let doc = "{\"root\": {\"name\":\"g\",\"children\":["
                + "{\"name\":\"c\",\"widget\":\"circle\",\"radius\":18.0,\"color\":\"#ff0000\"}]}}";
        let got = parseDoc(doc) |> Option.flatMap(firstChild) |> Option.map(child ->
            (sizeSpec2(styleOf(child)#width), sizeSpec2(styleOf(child)#height)));
        Assert.assertEq(expected = Some((("px", 36.0), ("px", 36.0))), got)

    // ── parse: templates / use ──

    @Test
    def testTemplateAppliesAndNodeWins(): Unit \ Assert =
        // テンプレの width 52 をノードの width 40 が上書きし、height はテンプレ値が残る。
        let doc = "{\"templates\": {\"shape\": {\"width\": 52, \"height\": 48, \"zIndex\": 10}},"
                + "\"root\": {\"name\":\"g\",\"children\":["
                + "{\"name\":\"c\",\"use\":\"shape\",\"widget\":\"circle\",\"radius\":18.0,\"color\":\"#ff0000\",\"width\":40}]}}";
        let got = parseDoc(doc) |> Option.flatMap(firstChild) |> Option.flatMap(child ->
            match widgetOf(child) {
                case UiDoc.Widget.ShapeW(s) =>
                    Some((sizeSpec2(styleOf(child)#width), sizeSpec2(styleOf(child)#height), s#zIndex))
                case _ => None
            });
        Assert.assertEq(
            expected = Some((("px", 40.0), ("px", 48.0), 10)),
            got)

    @Test
    def testUnknownTemplateIsError(): Unit \ Assert =
        let doc = "{\"root\": {\"name\":\"g\",\"use\":\"nope\"}}";
        Assert.assertEq(expected = false, parses(doc))

    // ── parse: 色 3 形 ──

    @Test
    def testHsvColorMatchesColorHsv(): Unit \ Assert =
        let doc = "{\"root\": {\"name\":\"g\",\"children\":["
                + "{\"name\":\"c\",\"widget\":\"circle\",\"radius\":1.0,\"color\":{\"hsv\":[0.5,0.72,1.0]}}]}}";
        let expected = Color.hsv({ h = 0.5, s = 0.72, v = 1.0 });
        let got = parseDoc(doc) |> Option.flatMap(firstChild) |> Option.flatMap(child ->
            match widgetOf(child) {
                case UiDoc.Widget.ShapeW(s) => Some(colorTuple(s#color))
                case _ => None
            });
        Assert.assertEq(expected = Some(colorTuple(expected)), got)

    @Test
    def testRgbColorTruncatesToFloat32(): Unit \ Assert =
        let doc = "{\"root\": {\"name\":\"g\",\"children\":["
                + "{\"name\":\"c\",\"widget\":\"circle\",\"radius\":1.0,\"color\":{\"rgb\":[0.560784,0.588235,0.713726]}}]}}";
        let got = parseDoc(doc) |> Option.flatMap(firstChild) |> Option.flatMap(child ->
            match widgetOf(child) {
                case UiDoc.Widget.ShapeW(s) => Some(colorTuple(s#color))
                case _ => None
            });
        Assert.assertEq(
            expected = Some((Float64.truncateToFloat32(0.560784),
                             Float64.truncateToFloat32(0.588235),
                             Float64.truncateToFloat32(0.713726))),
            got)

    @Test
    def testInvalidHexColorIsError(): Unit \ Assert =
        let doc = "{\"root\": {\"name\":\"g\",\"children\":["
                + "{\"name\":\"c\",\"widget\":\"circle\",\"radius\":1.0,\"color\":\"#zz0000\"}]}}";
        Assert.assertEq(expected = false, parses(doc))

    // ── parse: エラー系 ──

    @Test
    def testErrorCases(): Unit \ Assert =
        let unknownWidget = "{\"root\": {\"name\":\"g\",\"widget\":\"blob\",\"color\":\"#ffffff\"}}";
        let noRadius      = "{\"root\": {\"name\":\"g\",\"widget\":\"ngon\",\"n\":5,\"color\":\"#ffffff\"}}";
        let dupNames      = "{\"root\": {\"name\":\"g\",\"children\":["
                          + "{\"name\":\"a\"},{\"name\":\"a\"}]}}";
        let polyTwoPoints = "{\"root\": {\"name\":\"g\",\"widget\":\"poly\",\"color\":\"#ffffff\","
                          + "\"points\":[[0,0],[1,1]]}}";
        let okControl     = "{\"root\": {\"name\":\"g\"}}";
        Assert.assertEq(
            expected = (false, false, false, false, true),
            (parses(unknownWidget), parses(noRadius),
             parses(dupNames), parses(polyTwoPoints), parses(okControl)))

    /// doc のパースエラーを編集者向け文言（describe）で返す（成功や JSON 構文エラーは目印文字列）。
    def errTextOf(doc: String): String =
        JsonCompat.parse(doc)
            |> Option.map(json -> match UiDoc.parse(json) {
                case Ok(_)  => "no error"
                case Err(e) => JsonCompat.describe(e)
            })
            |> Option.getWithDefault("no json")

    @Test
    def testErrorCarriesNodePath(): Unit \ Assert =
        // 深いノードの必須キー欠落は、そのノードの名前パスでタグされる（編集箇所へ誘導する）。
        let doc = "{\"root\": {\"name\":\"g\",\"children\":[{\"name\":\"row1\",\"children\":["
                + "{\"name\":\"box\",\"widget\":\"circle\",\"radius\":1.0}]}]}}";
        Assert.assertEq(expected = true, String.contains(substr = "g/row1/box", errTextOf(doc)))

    @Test
    def testErrorCarriesChildIndexWhenNameMissing(): Unit \ Assert =
        // name の無い子は名前で指せないので「親パス[兄弟内位置]」で指す。
        let doc = "{\"root\": {\"name\":\"g\",\"children\":["
                + "{\"name\":\"a\"},{\"widget\":\"box\",\"color\":\"#000000\"}]}}";
        Assert.assertEq(expected = true, String.contains(substr = "g[1]", errTextOf(doc)))

    @Test
    def testErrorMessageHasNoDecoderNoise(): Unit \ Assert =
        // describe を通した文言に器の定型句("type mismatch: expected")が残らない —
        // 編集者は「どこで・何が要るか」だけを読む。
        let msg = errTextOf("{\"root\": {\"name\":\"g\",\"widget\":\"circle\",\"radius\":1.0}}");
        Assert.assertEq(
            expected = (true, false),
            (String.contains(substr = "at g: 'color' is required", msg),
             String.contains(substr = "type mismatch", msg)))

    // ── parse: palette（"@名前" の色参照）──

    @Test
    def testPaletteRefResolvesAtParse(): Unit \ Assert =
        let doc = "{\"palette\": {\"accent\": \"#ff0000\"},"
                + "\"root\": {\"name\":\"g\",\"children\":["
                + "{\"name\":\"c\",\"widget\":\"circle\",\"radius\":10.0,\"color\":\"@accent\","
                + "\"hover\":{\"borderColor\":\"@accent\"}}]}}";
        let got = parseDoc(doc) |> Option.flatMap(firstChild) |> Option.flatMap(child ->
            match widgetOf(child) {
                case UiDoc.Widget.ShapeW(s) => match child {
                    case UiDoc.Spec.Spec(node) =>
                        Some((colorTuple(s#color),
                              node#hover |> Option.flatMap(h -> Option.map(colorTuple, h#borderColor))))
                }
                case _ => None
            });
        Assert.assertEq(
            expected = Some(((1.0f32, 0.0f32, 0.0f32), Some((1.0f32, 0.0f32, 0.0f32)))),
            got)

    @Test
    def testUnknownPaletteNameIsError(): Unit \ Assert =
        let doc = "{\"palette\": {\"accent\": \"#ff0000\"},"
                + "\"root\": {\"name\":\"g\",\"widget\":\"box\",\"color\":\"@typo\",\"width\":10,\"height\":10}}";
        Assert.assertEq(expected = true,
            String.contains(substr = "unknown palette color '@typo'", errTextOf(doc)))

    @Test
    def testInstancePaletteIsPerDocument(): Unit \ Assert =
        // 参照先は自分の palette で解決する（使う側の accent は漏れない）。
        let btn = ("btn.ui.json",
            "{\"palette\": {\"accent\": \"#00ff00\"},"
            + "\"root\": {\"name\":\"button\",\"widget\":\"box\",\"color\":\"@accent\",\"width\":10,\"height\":10}}");
        let main = "{\"palette\": {\"accent\": \"#ff0000\"},"
                 + "\"root\": {\"name\":\"g\",\"children\":["
                 + "{\"name\":\"b\",\"instance\":\"btn.ui.json\"}]}}";
        let got = parseWithDocs(btn :: Nil, main)
            |> Option.flatMap(firstChild)
            |> Option.flatMap(b -> match widgetOf(b) {
                case UiDoc.Widget.BoxW(box) => Some(colorTuple(box#color))
                case _ => None
            });
        Assert.assertEq(expected = Some((0.0f32, 1.0f32, 0.0f32)), got)

    @Test
    def testWrapValidation(): Unit \ Assert =
        // wrap は Row + 幅高さ明示のみ。column や auto 寸法は loud に Err。
        let ok       = "{\"root\": {\"name\":\"g\",\"dir\":\"row\",\"wrap\":true,\"width\":100,\"height\":50}}";
        let column   = "{\"root\": {\"name\":\"g\",\"wrap\":true,\"width\":100,\"height\":50}}";
        let autoW    = "{\"root\": {\"name\":\"g\",\"dir\":\"row\",\"wrap\":true,\"height\":50}}";
        Assert.assertEq(
            expected = (true, false, false),
            (parses(ok), parses(column), parses(autoW)))

    // ── parse: version / $schema / "//" ──

    @Test
    def testVersionCheck(): Unit \ Assert =
        let v1 = "{\"version\": 1, \"root\": {\"name\":\"g\"}}";
        let v9 = "{\"version\": 9, \"root\": {\"name\":\"g\"}}";
        Assert.assertEq(expected = (true, false), (parses(v1), parses(v9)))

    @Test
    def testSchemaAndCommentKeysAreIgnored(): Unit \ Assert =
        // "$schema"（エディタ検証用）と "//"（コメント）は受理して無視 — 将来 strict 化しても
        // 壊れない契約としてここで固定する。
        let doc = "{\"$schema\": \"./ui.schema.json\", \"//\": \"top note\","
                + "\"root\": {\"name\":\"g\",\"//\":\"node note\"}}";
        Assert.assertEq(expected = true, parses(doc))

    // ── parse: sprite / bind / meta / layer（UiSpec 互換の保持） ──

    @Test
    def testSpriteParses(): Unit \ Assert =
        let doc = "{\"root\": {\"name\":\"g\",\"widget\":\"sprite\",\"texture\":\"hero\","
                + "\"scale\":[2.0,2.0],\"hframes\":4,\"frame\":2}}";
        let got = parseDoc(doc) |> Option.flatMap(spec -> match widgetOf(spec) {
            case UiDoc.Widget.SpriteW(s) => Some((s#texture, s#scale#x, s#hframes, s#frame))
            case _ => None
        });
        Assert.assertEq(expected = Some(("hero", 2.0, 4, 2)), got)

    @Test
    def testBindMetaLayerAreKept(): Unit \ Assert =
        // Flex 経路では使わないが Spec には保持する — 同じ JSON が経路で意味を失わない契約。
        let doc = "{\"root\": {\"name\":\"g\",\"layer\":7,\"children\":["
                + "{\"name\":\"t\",\"widget\":\"text\",\"text\":\"hi\",\"bind\":\"score\",\"meta\":\"item0\"}]}}";
        let got = parseDoc(doc) |> Option.flatMap(spec -> match spec {
            case UiDoc.Spec.Spec(root) => List.head(root#children) |> Option.map(child -> match child {
                case UiDoc.Spec.Spec(c) => (root#layer, c#binding, c#meta)
            })
        });
        Assert.assertEq(expected = Some((7, Some("score"), Some("item0"))), got)

    // ── hover（宣言 → spawn → extract 適用 → hitTestUi）──

    @Test
    def testHoverParsesPartialOverride(): Unit \ Assert =
        // hover は部分上書き — 書いたフィールドだけ Some になる。
        let doc = "{\"root\": {\"name\":\"g\",\"widget\":\"box\",\"color\":\"#000000\",\"width\":10,\"height\":10,"
                + "\"hover\": {\"color\":\"#ff0000\"}}}";
        let got = parseDoc(doc) |> Option.flatMap(spec -> match spec {
            case UiDoc.Spec.Spec(node) => node#hover |> Option.map(h ->
                (Option.map(colorTuple, h#color), Option.isEmpty(h#tint), Option.isEmpty(h#alpha)))
        });
        Assert.assertEq(expected = Some((Some((1.0f32, 0.0f32, 0.0f32)), true, true)), got)

    @Test
    def testHoverAppliesOnExtractOnlyWhenHovered(): Unit \ Assert =
        // setHovered された entity だけ、宣言された hover 上書きが extract で効く。
        let doc = "{\"root\": {\"name\":\"g\",\"widget\":\"box\",\"color\":\"#000000\",\"width\":10,\"height\":10,"
                + "\"hover\": {\"color\":\"#ff0000\"}}}";
        let boxColorAt = ui -> {
            let rects = layoutOf(ui);
            let vis = visOf(ui);
            UiExtract.extract(ui, rects, vis, _ -> dummyAtlas(), _ -> None)
                |> List.head
                |> Option.flatMap(placed -> match placed#item {
                    case Render.Item.Box(b) => Some(colorTuple(b#color))
                    case _                  => None
                })
        };
        let got = spawnDoc(doc) |> Option.map(ui ->
            (boxColorAt(ui), boxColorAt(UiStore.setHovered(Some("g"), ui))));
        Assert.assertEq(
            expected = Some((Some((0.0f32, 0.0f32, 0.0f32)), Some((1.0f32, 0.0f32, 0.0f32)))),
            got)

    @Test
    def testHoverAppliesToPolyAndSprite(): Unit \ Assert =
        // hover は poly（color）と sprite（tint）にも効く — 「宣言を受理して黙って無視」を作らない。
        let doc = "{\"root\": {\"name\":\"g\",\"dir\":\"row\",\"children\":["
                + "{\"name\":\"p\",\"widget\":\"poly\",\"color\":\"#000000\",\"width\":10,\"height\":10,"
                + "\"points\":[[0,0],[10,0],[5,10]],\"hover\":{\"color\":\"#ff0000\"}},"
                + "{\"name\":\"s\",\"widget\":\"sprite\",\"texture\":\"t\",\"width\":10,\"height\":10,"
                + "\"hover\":{\"tint\":\"#ff0000\"}}]}}";
        let got = spawnDoc(doc) |> Option.map(ui -> {
            let hovered = p -> UiStore.setHovered(Some(p), ui);
            let polyColor = u -> UiExtract.extractPolys(u, layoutOf(u), visOf(u))
                |> List.head |> Option.map(entry -> {let (_id, _pos, comp) = entry; colorTuple(comp#color)});
            let spriteTint = u -> UiExtract.extract(u, layoutOf(u), visOf(u), _ -> dummyAtlas(), _ -> None)
                |> List.filterMap(placed -> match placed#item {
                    case Render.Item.Sprite(sp) => Some(colorTuple(sp#tint))
                    case _                      => None
                }) |> List.head;
            (polyColor(hovered("g/p")), spriteTint(hovered("g/s")))
        });
        Assert.assertEq(
            expected = Some((Some((1.0f32, 0.0f32, 0.0f32)), Some((1.0f32, 0.0f32, 0.0f32)))),
            got)

    @Test
    def testHitTestUiFindsButtonsByRect(): Unit \ Assert =
        // 縦に並んだ 2 ボタン(10×10)を hitTestUi で引き分ける。ボタン外は root(全面)に当たる。
        let doc = "{\"root\": {\"name\":\"g\",\"children\":["
                + "{\"name\":\"b1\",\"widget\":\"box\",\"color\":\"#000000\",\"width\":10,\"height\":10,\"zIndex\":5},"
                + "{\"name\":\"b2\",\"widget\":\"box\",\"color\":\"#000000\",\"width\":10,\"height\":10,\"zIndex\":5}]}}";
        let design = { x = 100.0, y = 100.0 };
        let pathAt = (ui, p) -> UiFocus.hitTestUi(ui, design, p)
            |> Option.flatMap(id -> UiStore.pathOf(id, ui));
        let got = spawnDoc(doc) |> Option.map(ui ->
            (pathAt(ui, { x = 5.0, y = 5.0 }),
             pathAt(ui, { x = 5.0, y = 15.0 }),
             pathAt(ui, { x = 50.0, y = 50.0 })));
        Assert.assertEq(
            expected = Some((Some("g/b1"), Some("g/b2"), Some("g"))),
            got)

    @Test
    def testHitTestUiIgnoresZeroSizeText(): Unit \ Assert =
        // ボタン中心に重なった text（measures 無しで 0×0）が高 zIndex でも当たりを奪わない —
        // 面積 0 の rect は内部を持たない。
        let doc = "{\"root\": {\"name\":\"g\",\"children\":["
                + "{\"name\":\"btn\",\"widget\":\"box\",\"color\":\"#000000\",\"width\":10,\"height\":10,"
                + "\"dir\":\"column\",\"mainAlign\":\"center\",\"crossAlign\":\"center\",\"zIndex\":5,\"children\":["
                + "{\"name\":\"label\",\"widget\":\"text\",\"text\":\"+\",\"zIndex\":9}]}]}}";
        let got = spawnDoc(doc) |> Option.map(ui ->
            UiFocus.hitTestUi(ui, { x = 100.0, y = 100.0 }, { x = 5.0, y = 5.0 })
                |> Option.flatMap(id -> UiStore.pathOf(id, ui)));
        Assert.assertEq(expected = Some(Some("g/btn")), got)

    @Test
    def testHitTestUiSkipsInvisible(): Unit \ Assert =
        let doc = "{\"root\": {\"name\":\"g\",\"children\":["
                + "{\"name\":\"b1\",\"widget\":\"box\",\"color\":\"#000000\",\"width\":10,\"height\":10,"
                + "\"zIndex\":5,\"visible\":false}]}}";
        let got = spawnDoc(doc) |> Option.map(ui ->
            UiFocus.hitTestUi(ui, { x = 100.0, y = 100.0 }, { x = 5.0, y = 5.0 })
                |> Option.flatMap(id -> UiStore.pathOf(id, ui)));
        // 不可視ボタンには当たらず、背後の root に落ちる。
        Assert.assertEq(expected = Some(Some("g")), got)

    @Test
    def testReloadAllWithReportKeepsOldTreeAndReports(): Unit \ {Assert, IO} =
        // 読めないアセットの root は旧ツリーを保ちつつ、(root名, エラー文言) が報告に載る。
        let doc = "{\"root\": {\"name\":\"g\",\"widget\":\"box\",\"color\":\"#000000\",\"width\":10,\"height\":10}}";
        let got = spawnDoc(doc) |> Option.map(ui -> {
            let ui1 = UiStore.putSource("g", "no/such/file.ui.json", ui);
            let (ui2, errs) = run { UiSpec.reloadAllWithReport(ui1) } with Fs.FileRead.runWithIO;
            (Option.isEmpty(UiStore.idOf("g", ui2)) == false,
             List.map(entry -> {let (rootName, _msg) = entry; rootName}, errs))
        });
        Assert.assertEq(expected = Some((true, "g" :: Nil)), got)

    @Test
    def testSetShapeColorChangesExtractedShape(): Unit \ Assert =
        let doc = "{\"root\": {\"name\":\"g\",\"widget\":\"circle\",\"radius\":5.0,\"color\":\"#000000\"}}";
        let red = { r = 1.0f32, g = 0.0f32, b = 0.0f32 };
        let shapeColorAt = ui -> {
            UiExtract.extractShapes(ui, layoutOf(ui), visOf(ui))
                |> List.head
                |> Option.flatMap(placed -> match placed#item {
                    case Render.Item.Box(b) => Some(colorTuple(b#color))
                    case _                  => None
                })
        };
        let got = spawnDoc(doc) |> Option.map(ui ->
            shapeColorAt(UiStore.setShapeColor("g", red, ui)));
        Assert.assertEq(expected = Some(Some((1.0f32, 0.0f32, 0.0f32))), got)

    /// doc を parse → UiSpec 射影 → spawn した UiWorld（テスト用の定型）。
    def spawnDoc(doc: String): Option[UiStore.UiWorld] =
        JsonCompat.parse(doc)
            |> Option.flatMap(json -> UiSpec.parse(json) |> Result.toOption)
            |> Option.map(spec -> { let (_, ui) = UiSpec.spawnRoot(spec, UiStore.empty()); ui })

    /// 全 root を 100×100 の design で解いた rect 表（テスト用）。
    def layoutOf(ui: UiStore.UiWorld): Map[EntityId, Rect2.Rect2] =
        UiStore.rootsOf(ui) |> List.foldLeft((acc, root) -> Map.union(
            UiLayout.computeLayout(
                {styles = ui#styles, parents = ui#parents, order = ui#order,
                 measures = Map.empty(), visible = ui#visible},
                root, {position = {x = 0.0, y = 0.0}, size = {x = 100.0, y = 100.0}}), acc), Map.empty())

    def visOf(ui: UiStore.UiWorld): Map[EntityId, Bool] =
        UiStore.rootsOf(ui) |> List.foldLeft((acc, root) -> Map.union(
            UiHierarchy.resolveInherited(ui#visible, ui#parents, root, ui#order), acc), Map.empty())

    // ── instance / override ──

    /// (パス, JSON 文字列) の組から resolver を組む。
    def docsResolver(docs: List[(String, String)]): Map[String, Util.Json.Json] =
        docs |> List.filterMap(entry -> {
            let (p, text) = entry;
            JsonCompat.parse(text) |> Option.map(json -> (p, json))
        }) |> List.toMap

    /// (パス, JSON 文字列) の組を resolver にして root をパースする。
    def parseWithDocs(docs: List[(String, String)], root: String): Option[UiDoc.Spec] =
        JsonCompat.parse(root) |> Option.flatMap(json ->
            UiDoc.parseWith(docsResolver(docs), json) |> Result.toOption)

    /// parseWithDocs のエラー文言（成功時は目印文字列）。
    def errTextWithDocs(docs: List[(String, String)], root: String): String =
        JsonCompat.parse(root)
            |> Option.map(json -> match UiDoc.parseWith(docsResolver(docs), json) {
                case Ok(_)  => "no error"
                case Err(e) => JsonCompat.describe(e)
            })
            |> Option.getWithDefault("no json")

    def buttonDoc(): (String, String) =
        ("btn.ui.json",
         "{\"root\": {\"name\":\"button\",\"widget\":\"box\",\"color\":\"#000000\",\"width\":10,\"height\":10,"
         + "\"children\":[{\"name\":\"label\",\"widget\":\"text\",\"text\":\"?\",\"fontSize\":8.0}]}}")

    @Test
    def testInstanceComposesAndOverrides(): Unit \ Assert =
        // 参照先の root がノードとして合成され、name はノード勝ち・override が子に効く。
        let main = "{\"root\": {\"name\":\"g\",\"children\":["
                 + "{\"name\":\"b1\",\"instance\":\"btn.ui.json\","
                 + "\"override\": {\"label\": {\"text\":\"+\"}}}]}}";
        let got = parseWithDocs(buttonDoc() :: Nil, main)
            |> Option.flatMap(firstChild)
            |> Option.flatMap(b1 -> firstChild(b1) |> Option.flatMap(label ->
                match widgetOf(label) {
                    case UiDoc.Widget.TextW(t) => Some((UiDoc.nameOf(b1), t#text))
                    case _                     => None
                }));
        Assert.assertEq(expected = Some(("b1", "+")), got)

    @Test
    def testInstanceNodeFieldsWinOverRoot(): Unit \ Assert =
        // インスタンスノード自身のフィールド（width）が参照先 root の値に勝つ。
        let main = "{\"root\": {\"name\":\"g\",\"children\":["
                 + "{\"name\":\"b1\",\"instance\":\"btn.ui.json\",\"width\":20}]}}";
        let got = parseWithDocs(buttonDoc() :: Nil, main)
            |> Option.flatMap(firstChild)
            |> Option.map(b1 -> sizeSpec2(styleOf(b1)#width));
        Assert.assertEq(expected = Some(("px", 20.0)), got)

    @Test
    def testInstanceDeepOverride(): Unit \ Assert =
        // 2 段の相対名パス("menu/slot0")で子孫を上書きできる。
        let menuDoc = ("menu.ui.json",
            "{\"root\": {\"name\":\"panel\",\"children\":[{\"name\":\"menu\",\"children\":["
            + "{\"name\":\"slot0\",\"widget\":\"text\",\"text\":\"?\",\"fontSize\":8.0}]}]}}");
        let main = "{\"root\": {\"name\":\"g\",\"children\":["
                 + "{\"name\":\"m\",\"instance\":\"menu.ui.json\","
                 + "\"override\": {\"menu/slot0\": {\"meta\":\"m0\"}}}]}}";
        let got = parseWithDocs(menuDoc :: Nil, main)
            |> Option.flatMap(firstChild)      // m (panel)
            |> Option.flatMap(firstChild)      // menu
            |> Option.flatMap(firstChild)      // slot0
            |> Option.map(slot -> match slot { case UiDoc.Spec.Spec(node) => node#meta });
        Assert.assertEq(expected = Some(Some("m0")), got)

    @Test
    def testInstanceErrorCases(): Unit \ Assert =
        let btn = buttonDoc();
        let badPath   = errTextWithDocs(btn :: Nil,
            "{\"root\": {\"name\":\"g\",\"instance\":\"btn.ui.json\",\"override\":{\"nope\":{\"text\":\"x\"}}}}");
        let children  = errTextWithDocs(btn :: Nil,
            "{\"root\": {\"name\":\"g\",\"instance\":\"btn.ui.json\",\"children\":[]}}");
        let withUse   = errTextWithDocs(btn :: Nil,
            "{\"root\": {\"name\":\"g\",\"use\":\"t\",\"instance\":\"btn.ui.json\"}}");
        let badPatch  = errTextWithDocs(btn :: Nil,
            "{\"root\": {\"name\":\"g\",\"instance\":\"btn.ui.json\",\"override\":{\"label\":{\"children\":[]}}}}");
        let unloaded  = errTextWithDocs(Nil,
            "{\"root\": {\"name\":\"g\",\"instance\":\"btn.ui.json\"}}");
        Assert.assertEq(
            expected = (true, true, true, true, true),
            (String.contains(substr = "not found", badPath),
             String.contains(substr = "children", children),
             String.contains(substr = "cannot be combined", withUse),
             String.contains(substr = "leaf fields only", badPatch),
             String.contains(substr = "not loaded", unloaded)))

    @Test
    def testInstanceCycleIsError(): Unit \ Assert =
        let a = ("a.ui.json", "{\"root\": {\"name\":\"a\",\"instance\":\"b.ui.json\"}}");
        let b = ("b.ui.json", "{\"root\": {\"name\":\"b\",\"instance\":\"a.ui.json\"}}");
        let msg = errTextWithDocs(a :: b :: Nil,
            "{\"root\": {\"name\":\"g\",\"instance\":\"a.ui.json\"}}");
        Assert.assertEq(expected = true, String.contains(substr = "instance cycle", msg))

    @Test
    def testLoadMissingInstanceFileIsError(): Unit \ {Assert, IO} =
        let got = run { UiDoc.load("no/such/file.ui.json") } with Fs.FileRead.runWithIO;
        Assert.assertEq(
            expected = true,
            match got { case Err(e) => String.contains(substr = "failed to read", JsonCompat.describe(e)) case Ok(_) => false })

    // ── paletteFile（外部パレットの load 層合成）──

    @Test
    def testPaletteFileMergesAndInlineWins(): Unit \ {Assert, IO} =
        // 外部パレットの base が引け、同名の accent は inline が勝つ。
        let got = run { UiSpec.load("test/assets/palette_main.ui.json") } with Fs.FileRead.runWithIO;
        let colors = got |> Result.toOption |> Option.flatMap(firstTwoBoxColors);
        Assert.assertEq(
            expected = Some(((1.0f32, 0.0f32, 0.0f32), (0.0f32, 0.0f32, 1.0f32))),
            colors)

    /// root 直下の子 2 つの box 色を取り出す(paletteFile テスト用)。
    def firstTwoBoxColors(spec: UiSpec.Spec): Option[((Float32, Float32, Float32), (Float32, Float32, Float32))] =
        match spec {
            case UiSpec.Spec.Spec(root) => twoBoxColors(root#children)
        }

    def twoBoxColors(children: List[UiSpec.Spec]): Option[((Float32, Float32, Float32), (Float32, Float32, Float32))] =
        match children {
            case UiSpec.Spec.Spec(a) :: UiSpec.Spec.Spec(b) :: Nil =>
                a#box |> Option.flatMap(ab -> b#box |> Option.map(bb ->
                    (colorTuple(ab#color), colorTuple(bb#color))))
            case _ => None
        }

    @Test
    def testPaletteFileMissingIsLoudError(): Unit \ {Assert, IO} =
        // paletteFile が読めないときは黙って無視せず Err（文言に paletteFile が入る）。
        let got = run { UiDoc.load("test/assets/palette_missing.ui.json") } with Fs.FileRead.runWithIO;
        Assert.assertEq(
            expected = true,
            match got {
                case Err(e) => String.contains(substr = "paletteFile: failed to read", JsonCompat.describe(e))
                case Ok(_)  => false
            })

    // ── intrinsicSize ──

    @Test
    def testIntrinsicSizes(): Unit \ Assert =
        let circle  = UiShape.intrinsicSize(UiShape.Shape.CircleS({ radius = 18.0 }));
        let star    = UiShape.intrinsicSize(UiShape.Shape.StarS({ points = 5, outer = 21.0, inner = 9.0,
                                                                  via = UiShape.Via.RenderVia }));
        let ellipse = UiShape.intrinsicSize(UiShape.Shape.EllipseS({ radii = { x = 26.0, y = 16.0 },
                                                                     segments = 32, via = UiShape.Via.RenderVia }));
        // 水平線: lineQuad の法線は真上下に ±w/2 → bbox は (長さ, 太さ)。
        let line    = UiShape.intrinsicSize(UiShape.Shape.LineS({ a = { x = 0.0, y = 0.0 },
                                                                  b = { x = 10.0, y = 0.0 }, lineWidth = 4.0 }));
        // 直線の 2 次ベジェ（制御点が中点）: 背骨は y=0 のまま → bbox は (長さ, 0)。
        let bez     = UiShape.intrinsicSize(UiShape.Shape.BezierS({ p0 = { x = -10.0, y = 0.0 },
                                                                    ctrl = { x = 0.0, y = 0.0 },
                                                                    p1 = { x = 10.0, y = 0.0 },
                                                                    steps = 4, widthFrom = 1.0, widthTo = 1.0 }));
        Assert.assertEq(
            expected = ((36.0, 36.0), (42.0, 42.0), (52.0, 32.0), (10.0, 4.0), (20.0, 0.0)),
            (sizeTuple(circle), sizeTuple(star), sizeTuple(ellipse), sizeTuple(line), sizeTuple(bez)))

    // ── build: レイアウト骨格（描画 rect が Flex の骨格と一致する） ──

    @Test
    def testBuildGallerySkeletonRects(): Unit \ Assert =
        // 帯 = Px 44/28 の box、行 = grow の box ×5。root は column + stretch。
        let band = h -> "{\"name\":\"b${h}\",\"widget\":\"box\",\"color\":\"#000000\",\"height\":${h}}";
        let row  = i -> "{\"name\":\"r${i}\",\"widget\":\"box\",\"color\":\"#000000\",\"height\":\"grow\"}";
        let doc = "{\"root\": {\"name\":\"g\",\"dir\":\"column\",\"crossAlign\":\"stretch\",\"children\":["
                + band(44) + ","
                + row(1) + "," + row(2) + "," + row(3) + "," + row(4) + "," + row(5) + ","
                + band(28) + "]}}";
        let rh = (530.0 - 44.0 - 28.0) * (1.0 / 5.0);
        let y1 = 44.0;
        let y2 = y1 + rh;
        let y3 = y2 + rh;
        let y4 = y3 + rh;
        let y5 = y4 + rh;
        let yNote = y5 + rh;
        let got = parseDoc(doc) |> Option.map(spec ->
            Flex.leafRects(UiDoc.build(_ -> dummyAtlas(), spec),
                           { position = { x = 0.0, y = 0.0 }, size = { x = 480.0, y = 530.0 } })
                |> List.map(rect4));
        Assert.assertEq(
            expected = Some(
                       (0.0, 0.0, 480.0, 44.0)
                    :: (0.0, y1, 480.0, rh) :: (0.0, y2, 480.0, rh) :: (0.0, y3, 480.0, rh)
                    :: (0.0, y4, 480.0, rh) :: (0.0, y5, 480.0, rh)
                    :: (0.0, yNote, 480.0, 28.0)
                    :: Nil),
            got)

    // ── build: 配置と回転の FP を固定する ──

    @Test
    def testCirclePlacedAtRectCenter(): Unit \ Assert =
        // 100×40 の中央寄せ root に circle r10 → rect (40,10,20,20)、at = 左上 = (40,10)。
        let doc = "{\"root\": {\"name\":\"g\",\"mainAlign\":\"center\",\"crossAlign\":\"center\",\"children\":["
                + "{\"name\":\"c\",\"widget\":\"circle\",\"radius\":10.0,\"color\":\"#ff0000\"}]}}";
        let got = parseDoc(doc) |> Option.map(spec ->
            UiDoc.render(_ -> dummyAtlas(), spec,
                         { position = { x = 0.0, y = 0.0 }, size = { x = 100.0, y = 40.0 } })
                |> List.map(p -> (p#at#x, p#at#y)));
        Assert.assertEq(expected = Some((40.0, 10.0) :: Nil), got)

    @Test
    def testPolyRotationMatchesRenderRotated(): Unit \ Assert =
        // 時計の針: JSON（左上相対の整数頂点 + rotation）が、コードで書いた
        // 「lineQuad → Render.rotated → at = 中心」と頂点まで一致する。
        let doc = "{\"root\": {\"name\":\"g\",\"widget\":\"poly\",\"color\":\"#ffffff\",\"rotation\":0.13,"
                + "\"points\":[[28,24],[28,2],[24,2],[24,24]]}}";
        let expectedVerts = Render.rotated(0.13, Render.lineQuad({ x = 0.0, y = 0.0 }, { x = 0.0, y = -22.0 }, 4.0))
            |> List.map(v -> (v#x, v#y));
        let got = parseDoc(doc) |> Option.flatMap(spec ->
            UiDoc.render(_ -> dummyAtlas(), spec,
                         { position = { x = 0.0, y = 0.0 }, size = { x = 52.0, y = 48.0 } })
                |> List.head)
            |> Option.flatMap(placed -> match placed#item {
                case Render.Item.Poly(p) => Some(((placed#at#x, placed#at#y), List.map(v -> (v#x, v#y), p#vertices)))
                case _                   => None
            });
        Assert.assertEq(expected = Some(((26.0, 24.0), expectedVerts)), got)

    @Test
    def testTextBuildsWithDummyAtlas(): Unit \ Assert =
        // グリフ無しアトラスでも text ノードが 1 描画物になる（寸法は pin しない）。
        let doc = "{\"root\": {\"name\":\"g\",\"children\":["
                + "{\"name\":\"t\",\"widget\":\"text\",\"text\":\"hi\",\"fontSize\":9.0}]}}";
        let got = parseDoc(doc) |> Option.map(spec ->
            UiDoc.render(_ -> dummyAtlas(), spec,
                         { position = { x = 0.0, y = 0.0 }, size = { x = 100.0, y = 40.0 } })
                |> List.length);
        Assert.assertEq(expected = Some(1), got)

    // ── UiSpec 経路との一致（方言の二重化解消の pin） ──

    @Test
    def testUiSpecParseAgreesWithUiDoc(): Unit \ Assert =
        // 同じ JSON を UiSpec.parse（射影）と UiDoc.parse に通し、box/text の中身が一致する。
        let doc = "{\"root\": {\"name\":\"g\",\"dir\":\"row\",\"children\":["
                + "{\"name\":\"b\",\"widget\":\"box\",\"color\":\"#112233\",\"cornerRadius\":3.0},"
                + "{\"name\":\"t\",\"widget\":\"text\",\"text\":\"hi\",\"fontSize\":9.0}]}}";
        let viaSpec = JsonCompat.parse(doc)
            |> Option.flatMap(json -> UiSpec.parse(json) |> Result.toOption)
            |> Option.flatMap(spec -> match spec {
                case UiSpec.Spec.Spec(root) => match root#children {
                    case UiSpec.Spec.Spec(b) :: UiSpec.Spec.Spec(t) :: Nil =>
                        b#box |> Option.flatMap(box -> t#text |> Option.map(text ->
                            (colorTuple(box#color), box#cornerRadius, text#text, text#fontSize)))
                    case _ => None
                }
            });
        let viaDoc = parseDoc(doc) |> Option.flatMap(spec -> match childrenOf(spec) {
            case b :: t :: Nil => match (widgetOf(b), widgetOf(t)) {
                case (UiDoc.Widget.BoxW(box), UiDoc.Widget.TextW(text)) =>
                    Some((colorTuple(box#color), box#cornerRadius, text#text, text#fontSize))
                case _ => None
            }
            case _ => None
        });
        Assert.assertEq(expected = viaDoc, viaSpec)

    @Test
    def testShapeSpawnsAndExtracts(): Unit \ Assert =
        // circle 図形ノードが UiSpec 経路（spawnRoot → extractShapes）でも 1 個の絵になる。
        let doc = "{\"root\": {\"name\":\"g\",\"children\":["
                + "{\"name\":\"c\",\"widget\":\"circle\",\"radius\":10.0,\"color\":\"#ff0000\"}]}}";
        let count = JsonCompat.parse(doc)
            |> Option.flatMap(json -> UiSpec.parse(json) |> Result.toOption)
            |> Option.map(spec -> {
                let (rootId, ui) = UiSpec.spawnRoot(spec, UiStore.empty());
                let rects = UiLayout.computeLayout(
                    {styles = ui#styles, parents = ui#parents, order = ui#order,
                     measures = Map.empty(), visible = ui#visible},
                    rootId, {position = {x = 0.0, y = 0.0}, size = {x = 100.0, y = 100.0}});
                let vis = UiHierarchy.resolveInherited(ui#visible, ui#parents, rootId, ui#order);
                List.length(UiExtract.extractShapes(ui, rects, vis))
            });
        Assert.assertEq(expected = Some(1), count)

    @Test
    def testPolyRotationIsLoudErrorViaUiSpec(): Unit \ Assert =
        // rotation 付き poly は Flex 経路（UiDoc）では通り、UiStore 経路（UiSpec）では loud に Err —
        // 「黙って無視」を作らない契約の pin。
        let doc = "{\"root\": {\"name\":\"g\",\"widget\":\"poly\",\"color\":\"#ffffff\",\"rotation\":0.1,"
                + "\"points\":[[0,0],[4,0],[2,4]]}}";
        let uiSpecOk = JsonCompat.parse(doc) |> Option.map(json -> Result.isOk(UiSpec.parse(json)));
        let uiDocOk  = JsonCompat.parse(doc) |> Option.map(json -> Result.isOk(UiDoc.parse(json)));
        Assert.assertEq(expected = (Some(false), Some(true)), (uiSpecOk, uiDocOk))
}
