// Starfield のテスト。同じ入力なら同じ星原が出る決定性と、無限の空（visible をずらしても
// 同じセルの星は同じ位置）を固定する。Vec2 / Color は Eq 非導出のため、比較は
// 個数やスカラー成分に絞る（TestGrid / TestTextDraw と同じ流儀）。

mod TestStarfield {

    def dim(): Color    = { r = 0.3f32, g = 0.3f32, b = 0.5f32 }
    def mid(): Color    = { r = 0.5f32, g = 0.6f32, b = 0.8f32 }
    def bright(): Color = { r = 0.9f32, g = 0.9f32, b = 1.0f32 }

    def spec(): Starfield.Spec =
        { cell = 32.0, salt = 11, z = -20,
          sizes = (1.0, 2.0, 3.0), colors = (dim(), mid(), bright()) }

    def smallVisible(): Rect2.Rect2 =
        { position = { x = 0.0, y = 0.0 }, size = { x = 64.0, y = 64.0 } }

    // PlacedItem を (x, y) の組へ落とす。座標だけ比較できれば決定性・pin には十分。
    def toXY(items: List[Render.PlacedItem]): List[(Float64, Float64)] =
        List.map(p -> (p#at#x, p#at#y), items)

    /// 決定性：同じ visible + spec を2回呼ぶと、星の位置列が完全に一致する。
    @Test
    def testDeterministic(): Unit \ Assert =
        Assert.assertEq(
            expected = toXY(Starfield.field(smallVisible(), spec())),
            toXY(Starfield.field(smallVisible(), spec())))

    /// 星の総数を pin する（実測値。小さい visible + cell=32 の格子ぶん）。
    @Test
    def testStarCount(): Unit \ Assert =
        Assert.assertEq(expected = 11, List.length(Starfield.field(smallVisible(), spec())))

    /// 先頭の星の位置を具体値で pin する（Hash01 の実出力に対する回帰）。
    @Test
    def testFirstStarPosition(): Unit \ Assert =
        let stars = Starfield.field(smallVisible(), spec());
        let first = List.head(stars) |> Option.map(s -> (s#at#x, s#at#y));
        Assert.assertEq(expected = Some((1.8463446096617102, 8.344069677909662)), first)

    /// salt を変えるとパターンが変わる（同じ visible でも別の星原になる＝レイヤを重ねられる）。
    @Test
    def testSaltChangesPattern(): Unit \ Assert =
        let s = spec();
        let otherSalt = { salt = 47 | s };
        let a = toXY(Starfield.field(smallVisible(), s));
        let b = toXY(Starfield.field(smallVisible(), otherSalt));
        Assert.assertEq(expected = false, a == b)

    /// 無限の空：visible をセル1個分だけ右へずらしても、共通するセルの星は同じ絶対位置に
    /// 現れる（スクロールしても星が動かない＝seamless の核）。
    @Test
    def testSameCellSameStarAcrossShiftedVisible(): Unit \ Assert =
        let shifted = { position = { x = 32.0, y = 0.0 }, size = { x = 64.0, y = 64.0 } };
        let a = toXY(Starfield.field(smallVisible(), spec()));
        let b = toXY(Starfield.field(shifted, spec()));
        let shared = List.filter(xy -> List.memberOf(xy, b), a);
        Assert.assertEq(expected = true, List.length(shared) > 0)
}
