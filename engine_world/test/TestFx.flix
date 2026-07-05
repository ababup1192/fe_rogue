// Fx.derive のテスト。玩具の piece（sokoban 非依存）で、件数・決定論・個性の蛇口の
// 結線・時刻の受け渡しを固定する。

mod TestFx {

    /// 件数: count 個ちょうど出る。
    @Test
    def testCount(): Unit \ Assert =
        let out = Fx.derive(5, 0.0, (i, _, _) -> i);
        Assert.assertEq(expected = 5, List.length(out))

    /// 決定論: 同じ入力は毎回同じ列。
    @Test
    def testDeterministic(): Unit \ Assert =
        let piece = (i, rand, t) -> (i, rand(2), t);
        Assert.assertEq(
            expected = Fx.derive(8, 1.25, piece),
            Fx.derive(8, 1.25, piece))

    /// 個性の蛇口: piece が受け取る rand(k) は Hash01.at(i, k)。番号 i もそのまま届く。
    @Test
    def testRandTapWired(): Unit \ Assert =
        let out = Fx.derive(6, 0.0, (i, rand, _) -> (i, rand(3)));
        Assert.assertEq(
            expected = List.map(i -> (i, Hash01.at(i, 3)), List.range(0, 6)),
            out)

    /// 時刻: piece には呼び出し時の t が全粒に届く。
    @Test
    def testTimePassedThrough(): Unit \ Assert =
        let out = Fx.derive(4, 2.5, (_, _, t) -> t);
        Assert.assertEq(expected = 2.5 :: 2.5 :: 2.5 :: 2.5 :: Nil, out)

    /// seed 0 の deriveSeeded は derive と同じ列（既存の群れの絵を変えない互換の土台）。
    @Test
    def testDeriveSeededZeroMatchesDerive(): Unit \ Assert =
        let piece = (i, rand, t) -> (i, rand(2), t);
        Assert.assertEq(
            expected = Fx.derive(6, 0.5, piece),
            Fx.deriveSeeded({seed = 0, count = 6}, 0.5, piece))

    /// seed が違えば同じ番号の粒でも別の個性を引く（撃つたびの表情替えの土台）。
    @Test
    def testDeriveSeededChangesIdentity(): Unit \ Assert =
        let piece = (_, rand, _) -> rand(1);
        Assert.assertEq(expected = false,
            Fx.deriveSeeded({seed = 1, count = 4}, 0.0, piece)
                == Fx.deriveSeeded({seed = 2, count = 4}, 0.0, piece))
}
