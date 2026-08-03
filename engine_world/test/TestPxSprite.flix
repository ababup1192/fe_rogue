// PxSprite / PxSpriteDoc のテスト。テストするのは「パースの fail-open」
// 「未定義文字 = 透明」「anchor / flipX の座標規約」「横結合が面積を保つ」だけ —
// 絵そのもの(色の見た目)はテストしない。

mod TestPxSprite {

    def doc(): PxSpriteDoc.Doc =
        PxSpriteDoc.fromJson(String.unlines(
            "{" ::
            "  \"version\": 1," ::
            "  \"note\": \"test sprite\"," ::
            "  \"legend\": { \"a\": \"body\", \"b\": \"hair\", \"xx\": \"broken\", \"n\": 3 }," ::
            "  \"sprites\": {" ::
            "    \"guy\": {" ::
            "      \"anchor\": { \"x\": 1.0, \"y\": 2.0 }," ::
            "      \"frames\": {" ::
            "        \"f0\": [ \".aa.\", \"aaaa\", \"b?b.\" ]," ::
            "        \"bad\": [ \".a\", 7 ]" ::
            "      }" ::
            "    }," ::
            "    \"junk\": 5" ::
            "  }" ::
            "}" :: Nil))
            |> Option.getWithDefault(PxSpriteDoc.empty())

    /// fail-open: 壊れたテキストは None → 呼び手は empty へ倒す。empty は何も描かない。
    @Test
    def testBrokenTextFailsOpenToEmpty(): Unit \ Assert =
        let d = PxSpriteDoc.fromJson("{ not json")
            |> Option.getWithDefault(PxSpriteDoc.empty());
        Assert.assertEq(expected = 0,
            List.length(PxSprite.runs(d, "guy", "f0", { x = 0.0, y = 0.0 }, false, 1)))

    /// legend の 1 フィールド: 1 文字でないキー・文字列でない値は黙って捨て、
    /// 正しい項(a, b)だけが残る。note / version も読める。
    @Test
    def testLegendKeepsOnlyWellFormedEntries(): Unit \ Assert =
        let d = doc();
        Assert.assertEq(expected = (1, Some("test sprite"), Map#{'a' => "body", 'b' => "hair"}),
            (d#version, d#note, d#legend))

    /// rows 追随: コマの行がそのまま格子になる(行数・壊れたコマ bad と
    /// 壊れたスプライト junk は捨てられる)。
    @Test
    def testFramesFollowRows(): Unit \ Assert =
        let d = doc();
        let sp = Map.get("guy", d#sprites) |> Option.getWithDefault(
            { anchor = { x = 0.0, y = 0.0 }, frames = Map.empty() });
        Assert.assertEq(expected = (1, Some(".aa." :: "aaaa" :: "b?b." :: Nil), 1),
            (Map.size(d#sprites), Map.get("f0", sp#frames), Map.size(sp#frames)))

    /// 未定義文字('.' と '?')は透明: 被覆面積 = 定義済み文字数 × scale²。
    /// 横結合の正しさもこの面積保存で確かめる(f0 の定義済みセルは 2+4+2 = 8)。
    @Test
    def testCoverageEqualsDefinedCellsTimesScaleSq(): Unit \ Assert =
        let rs = PxSprite.runs(doc(), "guy", "f0", { x = 0.0, y = 0.0 }, false, 3);
        let area = rs |> List.foldLeft((acc, r) -> acc + r#w * r#h, 0.0);
        // 行ごとの run 数: ".aa." = 1、"aaaa" = 1、"b?b." = 2(透明で切れる)。
        Assert.assertEq(expected = (72.0, 4), (area, List.length(rs)))

    /// anchor 規約: at が anchor セル(1,2)の左上に来る。scale 2 で
    /// 先頭 run(".aa." の col1)は x = at.x + (1-1)*2 = 10、y = at.y + (0-2)*2 = 16。
    @Test
    def testAnchorPlacesAnchorCellAtPosition(): Unit \ Assert =
        let rs = PxSprite.runs(doc(), "guy", "f0", { x = 10.0, y = 20.0 }, false, 2);
        let head = List.head(rs) |> Option.getWithDefault(
            { x = -1.0, y = -1.0, w = 0.0, h = 0.0, key = "" });
        Assert.assertEq(expected = (10.0, 16.0, 4.0, 2.0), (head#x, head#y, head#w, head#h))

    /// flipX 規約: anchor を軸に左右が入れ替わる。ax=1 の絵で "b?b." (row2) の
    /// col0 は at の右へ、col2 は at の左へ写る。
    @Test
    def testFlipXMirrorsColumnsAroundAnchor(): Unit \ Assert =
        let rs = PxSprite.runs(doc(), "guy", "f0", { x = 0.0, y = 0.0 }, true, 1)
            |> List.filter(r -> r#key == "hair")
            |> List.map(r -> r#x);
        Assert.assertEq(expected = 1.0 :: -1.0 :: Nil, rs)

    /// 反転しても anchor（握るところ）は at のまま。
    /// 格子の真ん中 + anchorOffsetOf が at に戻ることで確かめる（両者が食い違うと、
    /// 反転した絵だけが横へ飛んで影・足元が置き去りになる）。
    @Test
    def testAnchorOffsetAgreesWithRunsUnderFlip(): Unit \ Assert =
        let centerX = flip -> {
            let rs = PxSprite.runs(doc(), "guy", "f0", { x = 0.0, y = 0.0 }, flip, 1);
            let lo = rs |> List.foldLeft((acc, r) -> Float64.min(acc, r#x), 999.0);
            let hi = rs |> List.foldLeft((acc, r) -> Float64.max(acc, r#x + r#w), -999.0);
            (lo + hi) / 2.0 + PxSprite.anchorOffsetOf(doc(), "guy", "f0", flip, 1)#x
        };
        Assert.assertEq(expected = (0.0, 0.0), (centerX(false), centerX(true)))

    /// scale 0 以下と、無いスプライト・無いコマは何も描かない(fail-open)。
    @Test
    def testMissingNamesAndZeroScaleDrawNothing(): Unit \ Assert =
        let d = doc();
        let z = { x = 0.0, y = 0.0 };
        Assert.assertEq(expected = (0, 0, 0),
            (List.length(PxSprite.runs(d, "guy", "f0", z, false, 0)),
             List.length(PxSprite.runs(d, "nobody", "f0", z, false, 1)),
             List.length(PxSprite.runs(d, "guy", "f9", z, false, 1))))

    /// コマの大きさは絵が決める（格子の列数・行数 × scale）。
    /// 固定値で持つと、絵を描き替えたとき当たりや置き場所が静かにズレる。
    @Test
    def testSizeOfFollowsTheDrawnGrid(): Unit \ Assert =
        let size = PxSprite.sizeOf(doc(), "guy", "f0", 3);
        Assert.assertEq(expected = Some((12.0, 9.0)), Option.map(v -> (v#x, v#y), size))

    /// 無いスプライト・無いコマは None（呼ぶ側が既定へ倒せるように）。
    @Test
    def testSizeOfIsNoneForUnknownNames(): Unit \ Assert =
        let xy = Option.map(v -> (v#x, v#y));
        Assert.assertEq(expected = (None, None),
            (xy(PxSprite.sizeOf(doc(), "nobody", "f0", 2)),
             xy(PxSprite.sizeOf(doc(), "guy", "nosuchframe", 2))))
}
