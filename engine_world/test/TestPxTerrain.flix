// PxTerrain のテスト。bayer4 は座標だけで決まる純関数なので値域と重なりを検算し、
// fill は色 1 色・水平な帯（ディザも輪郭の端数も出ない入力）で件数が span に追随するかを見る。

mod TestPxTerrain {

    /// 4x4 の 16 マスは全部 0..1 の中にあり、値は 16 通り全部違う。
    @Test
    def testBayer4ValuesAreDistinctAndInUnitRange(): Unit \ Assert =
        let values = List.range(0, 4) |> List.flatMap(y ->
            List.range(0, 4) |> List.map(x -> PxTerrain.bayer4(x, y)));
        let inRange = values |> List.forAll(v -> v > 0.0 and v < 1.0);
        Assert.assertEq(expected = (true, 16),
            (inRange, values |> List.toSet |> Set.size))

    /// 色 1 色・上下とも水平・cell の倍数の帯なら、件数は升目の数だけ。
    /// span を 2 倍にすると件数も 2 倍になる（幅 16 → 4 枚・幅 32 → 8 枚）。
    @Test
    def testFillItemCountFollowsSpan(): Unit \ Assert =
        let flatFill = x1 -> PxTerrain.fill(
            { z = 0, span = { x0 = 0.0, x1 = x1 },
              topAt = _ -> 0.0, bottomAt = _ -> 16.0,
              rampAt = _ -> Vector#{Color.rgb(0.5, 0.5, 0.5)},
              valueAt = _ -> 0.0, cell = 8.0 });
        Assert.assertEq(expected = (4, 8),
            (List.length(flatFill(16.0)), List.length(flatFill(32.0))))
}
