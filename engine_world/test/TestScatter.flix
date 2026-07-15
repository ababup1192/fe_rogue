// Scatter のテスト。同じ入力なら同じ配置が出る決定性と、無限の配置（visible をずらしても
// 同じセルの物は同じ位置）を固定する。加えて、星空相当の place を書いたときに旧 Starfield が
// 出していた星の絶対座標が再現されることを pin し、機構の互換性を保証する。

mod TestScatter {

    def smallVisible(): Rect2.Rect2 =
        { position = { x = 0.0, y = 0.0 }, size = { x = 64.0, y = 64.0 } }

    def spec(): {cell = Float64, salt = Int32} =
        { cell = 32.0, salt = 11 }

    // 星空相当の place: rand(0) が閾値を超えたセルには何も置かない。置くセルはセル内の
    // 相対位置を rand(1), rand(2) で決め、絶対座標 (x, y) だけを返す。
    def starPlace(cell: {col = Int32, row = Int32}, rand: Int32 -> Float64): List[(Float64, Float64)] =
        if (rand(0) > 0.5) Nil
        else
            let cs = spec()#cell;
            let px = (Int32.toFloat64(cell#col) + rand(1)) * cs;
            let py = (Int32.toFloat64(cell#row) + rand(2)) * cs;
            (px, py) :: Nil

    /// 決定性：同じ visible + spec + place を2回呼ぶと、結果列が完全に一致する。
    @Test
    def testDeterministic(): Unit \ Assert =
        Assert.assertEq(
            expected = Scatter.field(smallVisible(), spec(), starPlace),
            Scatter.field(smallVisible(), spec(), starPlace))

    /// salt を変えるとパターンが変わる（同じ visible でも別の配置になる＝レイヤを重ねられる）。
    @Test
    def testSaltChangesPattern(): Unit \ Assert =
        let otherSpec = { salt = 47 | spec() };
        let a = Scatter.field(smallVisible(), spec(), starPlace);
        let b = Scatter.field(smallVisible(), otherSpec, starPlace);
        Assert.assertEq(expected = false, a == b)

    /// 無限の配置：visible をセル1個分だけ右へずらしても、共通するセルの物は同じ絶対位置に
    /// 現れる（スクロールしても物が動かない＝seamless の核）。
    @Test
    def testSameCellSameResultAcrossShiftedVisible(): Unit \ Assert =
        let shifted = { position = { x = 32.0, y = 0.0 }, size = { x = 64.0, y = 64.0 } };
        let a = Scatter.field(smallVisible(), spec(), starPlace);
        let b = Scatter.field(shifted, spec(), starPlace);
        let shared = List.filter(xy -> List.memberOf(xy, b), a);
        Assert.assertEq(expected = true, List.length(shared) > 0)

    /// 総数を pin する（実測値。小さい visible + cell=32 の格子ぶん、星空相当の place）。
    @Test
    def testResultCount(): Unit \ Assert =
        Assert.assertEq(expected = 11, List.length(Scatter.field(smallVisible(), spec(), starPlace)))

    /// 旧 Starfield と同じ星空 place を書いたとき、旧 TestStarfield が pin していた先頭星の
    /// 座標が再現される（機構＋チャンネル割当の互換性 pin）。
    @Test
    def testFirstResultMatchesOldStarfieldPin(): Unit \ Assert =
        let results = Scatter.field(smallVisible(), spec(), starPlace);
        Assert.assertEq(
            expected = Some((1.8463446096617102, 8.344069677909662)),
            List.head(results))
}
