// Tests for JsonOps — Inspector が JSON ツリーを書き換えるときに使う純粋関数群
//
// すべての関数が副作用なしなので、手作りの Util.Json.Json で直接テストできる。
// 検証の観点:
//   - 子インデックス・キー列が想定どおり辿れるか
//   - 範囲外・スキーマ不一致のときに元データを壊さず返すか
//   - パース系は受理する文字列と拒否する文字列を境界で区別できるか

mod TestJsonOps {

    /// Util.Json.Json には ToString instance が無いので、
    /// assertEq で値を比較するときは pretty-print した文字列で突き合わせる。
    /// 構造の意味は保たれ、テスト失敗時のメッセージも人間が読める形になる。
    def asJString(elem: Util.Json.Json): String =
        Util.Json.toPrettyString(2, elem)

    // ========================================================================
    // replaceListAt — 不変リストの idx 番目を差し替える
    // ========================================================================

    /// 3 要素リストの先頭 (idx=0) を差し替えると最初の要素だけ変わる
    @Test
    def testReplaceListAtFirst(): Unit \ Assert =
        Assert.assertEq(
            expected = 99i32 :: 20i32 :: 30i32 :: Nil,
            JsonOps.replaceListAt(0i32, 99i32, 10i32 :: 20i32 :: 30i32 :: Nil))

    /// 3 要素リストの末尾 (idx=2) を差し替えると最後の要素だけ変わる
    @Test
    def testReplaceListAtLast(): Unit \ Assert =
        Assert.assertEq(
            expected = 10i32 :: 20i32 :: 99i32 :: Nil,
            JsonOps.replaceListAt(2i32, 99i32, 10i32 :: 20i32 :: 30i32 :: Nil))

    /// idx がリストの長さ以上だと元のリストをそのまま返す（クラッシュさせない）
    @Test
    def testReplaceListAtOutOfRange(): Unit \ Assert =
        Assert.assertEq(
            expected = 10i32 :: 20i32 :: 30i32 :: Nil,
            JsonOps.replaceListAt(5i32, 99i32, 10i32 :: 20i32 :: 30i32 :: Nil))

    /// 空リストに対しては空リストを返す
    @Test
    def testReplaceListAtEmpty(): Unit \ Assert =
        Assert.assertEq(
            expected = (Nil: List[Int32]),
            JsonOps.replaceListAt(0i32, 99i32, Nil))

    // ========================================================================
    // setAtKeyPath — JObject の中をキー列で降りて末端を差し替える
    // ========================================================================

    /// キー列が空なら obj 全体を newValue で置き換える
    @Test
    def testSetAtKeyPathEmptyKeysReplacesEverything(): Unit \ Assert =
        let original = Util.Json.Json.JObject(Map#{"x" => Util.Json.Json.JNumber(1.0ff)});
        let replacement = Util.Json.Json.JString("hello");
        Assert.assertEq(
            expected = asJString(replacement),
            asJString(JsonOps.setAtKeyPath(original, Nil, replacement)))

    /// 単一キーで JObject のフィールドを差し替える
    @Test
    def testSetAtKeyPathSingleKeyReplacesField(): Unit \ Assert =
        let original = Util.Json.Json.JObject(Map#{
            "x" => Util.Json.Json.JNumber(1.0ff),
            "y" => Util.Json.Json.JNumber(2.0ff)});
        let expected = Util.Json.Json.JObject(Map#{
            "x" => Util.Json.Json.JNumber(1.0ff),
            "y" => Util.Json.Json.JNumber(99.0ff)});
        Assert.assertEq(
            expected = asJString(expected),
            asJString(JsonOps.setAtKeyPath(original, "y" :: Nil, Util.Json.Json.JNumber(99.0ff))))

    /// 2 段ネストしたキー列で内側のフィールドを差し替える。
    /// 外側オブジェクトの他のフィールドは保持される
    @Test
    def testSetAtKeyPathTwoLevelNested(): Unit \ Assert =
        let inner    = Util.Json.Json.JObject(Map#{"r" => Util.Json.Json.JNumber(0.5ff)});
        let original = Util.Json.Json.JObject(Map#{
            "color" => inner,
            "name"  => Util.Json.Json.JString("hero")});
        let expectedInner = Util.Json.Json.JObject(Map#{"r" => Util.Json.Json.JNumber(1.0ff)});
        let expected = Util.Json.Json.JObject(Map#{
            "color" => expectedInner,
            "name"  => Util.Json.Json.JString("hero")});
        Assert.assertEq(
            expected = asJString(expected),
            asJString(JsonOps.setAtKeyPath(original, "color" :: "r" :: Nil, Util.Json.Json.JNumber(1.0ff))))

    /// 入力が JObject でなければ何もせず元の値を返す（スキーマ違反でクラッシュしない）
    @Test
    def testSetAtKeyPathNonObjectReturnsUnchanged(): Unit \ Assert =
        let original = Util.Json.Json.JString("not an object");
        Assert.assertEq(
            expected = asJString(original),
            asJString(JsonOps.setAtKeyPath(original, "x" :: Nil, Util.Json.Json.JNumber(1.0ff))))

    // ========================================================================
    // setAtNodePath — children を辿ったノードのキーを差し替える
    // ========================================================================

    /// nodePath が空 + subKeys が空なら root 全体を newValue に置き換える
    @Test
    def testSetAtNodePathEmptyBothReplacesRoot(): Unit \ Assert =
        let original = Util.Json.Json.JObject(Map#{"name" => Util.Json.Json.JString("a")});
        let replacement = Util.Json.Json.JString("replaced");
        Assert.assertEq(
            expected = asJString(replacement),
            asJString(JsonOps.setAtNodePath({root = original, nodePath = Nil,
                                                subKeys = Nil, newValue = replacement})))

    /// nodePath が空 + subKeys にキーがあれば root の該当キーを差し替える
    @Test
    def testSetAtNodePathEmptyPathWithKey(): Unit \ Assert =
        let original = Util.Json.Json.JObject(Map#{
            "name" => Util.Json.Json.JString("a"),
            "x"    => Util.Json.Json.JNumber(0.0ff)});
        let expected = Util.Json.Json.JObject(Map#{
            "name" => Util.Json.Json.JString("a"),
            "x"    => Util.Json.Json.JNumber(50.0ff)});
        Assert.assertEq(
            expected = asJString(expected),
            asJString(JsonOps.setAtNodePath({root = original, nodePath = Nil,
                                                subKeys = "x" :: Nil,
                                                newValue = Util.Json.Json.JNumber(50.0ff)})))

    /// 子インデックス [0] で 1 段降りて、その子の "x" を差し替える。
    /// 親のフィールドと他の兄弟は保持される
    ///
    /// 入力構造:
    ///   root: { name: "parent", children: [ { name: "child0", x: 0 } ] }
    ///   nodePath = [0], subKeys = ["x"], newValue = 50
    ///
    /// 期待:
    ///   root: { name: "parent", children: [ { name: "child0", x: 50 } ] }
    @Test
    def testSetAtNodePathOneLevelDescent(): Unit \ Assert =
        let child = Util.Json.Json.JObject(Map#{
            "name" => Util.Json.Json.JString("child0"),
            "x"    => Util.Json.Json.JNumber(0.0ff)});
        let original = Util.Json.Json.JObject(Map#{
            "name"     => Util.Json.Json.JString("parent"),
            "children" => Util.Json.Json.JArray(Vector#{child})});
        let expectedChild = Util.Json.Json.JObject(Map#{
            "name" => Util.Json.Json.JString("child0"),
            "x"    => Util.Json.Json.JNumber(50.0ff)});
        let expected = Util.Json.Json.JObject(Map#{
            "name"     => Util.Json.Json.JString("parent"),
            "children" => Util.Json.Json.JArray(Vector#{expectedChild})});
        Assert.assertEq(
            expected = asJString(expected),
            asJString(JsonOps.setAtNodePath({root = original, nodePath = 0i32 :: Nil,
                                                subKeys = "x" :: Nil,
                                                newValue = Util.Json.Json.JNumber(50.0ff)})))

    /// nodePath の途中で children が存在しなければ root を変えず返す
    @Test
    def testSetAtNodePathMissingChildrenLeavesRoot(): Unit \ Assert =
        let original = Util.Json.Json.JObject(Map#{
            "name" => Util.Json.Json.JString("parent")});
        Assert.assertEq(
            expected = asJString(original),
            asJString(JsonOps.setAtNodePath({root = original, nodePath = 0i32 :: Nil,
                                                subKeys = "x" :: Nil,
                                                newValue = Util.Json.Json.JNumber(50.0ff)})))

    /// nodePath の idx が children の範囲外なら root を変えず返す
    @Test
    def testSetAtNodePathIndexOutOfRange(): Unit \ Assert =
        let child = Util.Json.Json.JObject(Map#{
            "name" => Util.Json.Json.JString("only")});
        let original = Util.Json.Json.JObject(Map#{
            "children" => Util.Json.Json.JArray(Vector#{child})});
        Assert.assertEq(
            expected = asJString(original),
            asJString(JsonOps.setAtNodePath({root = original, nodePath = 5i32 :: Nil,
                                                subKeys = "x" :: Nil,
                                                newValue = Util.Json.Json.JNumber(50.0ff)})))

    // ========================================================================
    // getAtNodePath — 子インデックス列でノードを取り出す
    // ========================================================================

    /// 取り出した結果を文字列化する。None は固定マーカー "<none>" で表す。
    /// テストの assertEq で None と Some を同じ assertEq に乗せるための小ヘルパ。
    def asJStringOpt(opt: Option[Util.Json.Json]): String =
        match opt {
            case Some(elem) => asJString(elem)
            case None       => "<none>"
        }

    /// nodePath が空なら root をそのまま返す
    @Test
    def testGetAtNodePathEmptyReturnsRoot(): Unit \ Assert =
        let root = Util.Json.Json.JObject(Map#{"name" => Util.Json.Json.JString("a")});
        Assert.assertEq(
            expected = asJString(root),
            asJStringOpt(JsonOps.getAtNodePath(root, Nil)))

    /// children[0] を 1 段降りて取得する
    @Test
    def testGetAtNodePathOneLevelDescent(): Unit \ Assert =
        let child = Util.Json.Json.JObject(Map#{"name" => Util.Json.Json.JString("child")});
        let root  = Util.Json.Json.JObject(Map#{
            "name"     => Util.Json.Json.JString("parent"),
            "children" => Util.Json.Json.JArray(Vector#{child})});
        Assert.assertEq(
            expected = asJString(child),
            asJStringOpt(JsonOps.getAtNodePath(root, 0i32 :: Nil)))

    /// Container + Panel を経由したエンジン名抽出: tree [1, 0, 0] (CanvasLayer →
    /// Container → Panel → Slot0Bg) から ["Inventory", "Slot0Bg"] が返る。
    /// Container と Panel は透過なので acc には積まれない
    @Test
    def testExtractNodeNamesSkipsContainerAndPanel(): Unit \ Assert =
        let slot0Bg = Util.Json.Json.JObject(Map#{
            "type" => Util.Json.Json.JString("ColorRect"),
            "name" => Util.Json.Json.JString("Slot0Bg")});
        let panel = Util.Json.Json.JObject(Map#{
            "kind"     => Util.Json.Json.JString("Panel"),
            "children" => Util.Json.Json.JArray(Vector#{slot0Bg})});
        let layout = Util.Json.Json.JObject(Map#{
            "kind"     => Util.Json.Json.JString("HBoxContainer"),
            "children" => Util.Json.Json.JArray(Vector#{panel})});
        let container = Util.Json.Json.JObject(Map#{
            "type"   => Util.Json.Json.JString("Container"),
            "layout" => layout});
        let selectionHighlight = Util.Json.Json.JObject(Map#{
            "type" => Util.Json.Json.JString("ColorRect"),
            "name" => Util.Json.Json.JString("SelectionHighlight")});
        let root = Util.Json.Json.JObject(Map#{
            "type"     => Util.Json.Json.JString("CanvasLayer"),
            "name"     => Util.Json.Json.JString("Inventory"),
            "children" => Util.Json.Json.JArray(Vector#{selectionHighlight, container})});
        Assert.assertEq(
            expected = Some("Inventory" :: "Slot0Bg" :: Nil),
            JsonOps.extractNodeNames(root, 1i32 :: 0i32 :: 0i32 :: Nil))

    /// Container を経由した nodePath descent: tree [1, 0, 0] が
    /// CanvasLayer.children[1] (Container) → layout.children[0] (Panel) →
    /// Panel.children[0] (Slot0Bg) と辿れることと、その先で setAtNodePath が
    /// 正しく書き戻せること
    @Test
    def testSetAtNodePathThroughContainerAndPanel(): Unit \ Assert =
        let slot0Bg = Util.Json.Json.JObject(Map#{
            "type"  => Util.Json.Json.JString("ColorRect"),
            "name"  => Util.Json.Json.JString("Slot0Bg"),
            "alpha" => Util.Json.Json.JNumber(0.8ff)});
        let slot0Icon = Util.Json.Json.JObject(Map#{
            "type" => Util.Json.Json.JString("TextureRect"),
            "name" => Util.Json.Json.JString("Slot0Icon")});
        let panel = Util.Json.Json.JObject(Map#{
            "kind"     => Util.Json.Json.JString("Panel"),
            "children" => Util.Json.Json.JArray(Vector#{slot0Bg, slot0Icon})});
        let layout = Util.Json.Json.JObject(Map#{
            "kind"     => Util.Json.Json.JString("HBoxContainer"),
            "children" => Util.Json.Json.JArray(Vector#{panel})});
        let container = Util.Json.Json.JObject(Map#{
            "type"   => Util.Json.Json.JString("Container"),
            "layout" => layout});
        let selectionHighlight = Util.Json.Json.JObject(Map#{
            "type" => Util.Json.Json.JString("ColorRect"),
            "name" => Util.Json.Json.JString("SelectionHighlight")});
        let root = Util.Json.Json.JObject(Map#{
            "type"     => Util.Json.Json.JString("CanvasLayer"),
            "name"     => Util.Json.Json.JString("Inventory"),
            "children" => Util.Json.Json.JArray(Vector#{selectionHighlight, container})});
        // getAtNodePath で Slot0Bg に辿れる
        let got = JsonOps.getAtNodePath(root, 1i32 :: 0i32 :: 0i32 :: Nil);
        Assert.assertEq(expected = asJString(slot0Bg), asJStringOpt(got));
        // setAtNodePath で Slot0Bg の alpha を 0.5 に書き換えて root を再構成できる
        let updated = JsonOps.setAtNodePath({root = root,
                                              nodePath = 1i32 :: 0i32 :: 0i32 :: Nil,
                                              subKeys = "alpha" :: Nil,
                                              newValue = Util.Json.Json.JNumber(0.5ff)});
        let updatedSlot0Bg = JsonOps.getAtNodePath(updated, 1i32 :: 0i32 :: 0i32 :: Nil);
        let expectedSlot0Bg = Util.Json.Json.JObject(Map#{
            "type"  => Util.Json.Json.JString("ColorRect"),
            "name"  => Util.Json.Json.JString("Slot0Bg"),
            "alpha" => Util.Json.Json.JNumber(0.5ff)});
        Assert.assertEq(expected = asJString(expectedSlot0Bg), asJStringOpt(updatedSlot0Bg))

    /// idx が範囲外なら None
    @Test
    def testGetAtNodePathIndexOutOfRange(): Unit \ Assert =
        let child = Util.Json.Json.JObject(Map#{"name" => Util.Json.Json.JString("only")});
        let root  = Util.Json.Json.JObject(Map#{
            "children" => Util.Json.Json.JArray(Vector#{child})});
        Assert.assertEq(
            expected = "<none>",
            asJStringOpt(JsonOps.getAtNodePath(root, 5i32 :: Nil)))

    /// children が存在しないノードを辿ろうとすると None
    @Test
    def testGetAtNodePathMissingChildrenReturnsNone(): Unit \ Assert =
        let root = Util.Json.Json.JObject(Map#{"name" => Util.Json.Json.JString("leaf")});
        Assert.assertEq(
            expected = "<none>",
            asJStringOpt(JsonOps.getAtNodePath(root, 0i32 :: Nil)))

    // ========================================================================
    // parseBigDecimal — Inspector の数値入力フォームから値を取り出す
    // ========================================================================

    /// 正の小数文字列 "1.5" はパースされ、値は 1.5 になる
    @Test
    def testParseBigDecimalDecimalValue(): Unit \ Assert =
        match JsonOps.parseBigDecimal("1.5") {
            case Some(value) =>
                Assert.assertEq(expected = 1.5, value.doubleValue())
            case None => bug!("expected Some(BigDecimal) for '1.5'")
        }

    /// 前後の空白は無視され "  3.14  " は 3.14 として読まれる
    @Test
    def testParseBigDecimalTrimsWhitespace(): Unit \ Assert =
        match JsonOps.parseBigDecimal("  3.14  ") {
            case Some(value) =>
                Assert.assertEq(expected = 3.14, value.doubleValue())
            case None => bug!("expected Some(BigDecimal) for '  3.14  '")
        }

    /// 整数文字列も受理する
    @Test
    def testParseBigDecimalIntegerValue(): Unit \ Assert =
        match JsonOps.parseBigDecimal("42") {
            case Some(value) =>
                Assert.assertEq(expected = 42.0, value.doubleValue())
            case None => bug!("expected Some(BigDecimal) for '42'")
        }

    /// 数字でない文字列、空文字列、後ろにゴミが付く文字列はいずれも None。
    /// まとめて 1 アサートで確認する
    @Test
    def testParseBigDecimalRejectsInvalidStrings(): Unit \ Assert =
        let toMarker = _ -> ();
        Assert.assertEq(
            expected = ((None: Option[Unit]), (None: Option[Unit]), (None: Option[Unit])),
            (JsonOps.parseBigDecimal("abc")    |> Option.map(toMarker),
             JsonOps.parseBigDecimal("")       |> Option.map(toMarker),
             JsonOps.parseBigDecimal("1.5xyz") |> Option.map(toMarker)))
}
