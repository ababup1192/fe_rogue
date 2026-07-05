// FireFx（魔法の炎着弾）のテスト。絵ぜんぶが (見た目 Spec, 発生指定, 経過秒 t) の純粋な
// 導出であること —— 時間の外では空・同じ入力は同じ絵・seed で表情が変わる —— と、
// 5 プリセット全部がちゃんと絵を出すことを固定する。

mod TestFireFx {

    /// 検証用の発生指定（原点・seed 1・実寸）。
    def burst(): FireFx.Burst = {center = {x = 0.0, y = 0.0}, seed = 1, scale = 1.0}

    /// 四隅の座標を数のタプルへ写す（絵の比較用の取り出し）。
    def corners(quads: List[GameEngine.PolygonRenderCmd]): List[List[(Float64, Float64)]] =
        List.map(q -> List.map(v -> (v#x, v#y), q#vertices), quads)

    /// 演出は着弾前（t < 0）と終了後（t = duration）には何も描かず、燃え上がり中
    /// （0.2 秒 = 点火ずれ 0.22 秒がほぼ出揃う頃）には多数の舌が出ている。
    /// どの quad も四角形（頂点 4 つ）である。
    @Test
    def testFireIsAClosedFormOfTime(): Unit \ Assert =
        let spec = FireFx.standard();
        let mid = FireFx.quads(spec, burst(), 0.2);
        Assert.assertEq(expected = (0, 0, true, true),
            (List.length(FireFx.quads(spec, burst(), -0.1)),
             List.length(FireFx.quads(spec, burst(), spec#duration)),
             List.length(mid) > 10,
             List.forAll(q -> List.length(q#vertices) == 4, mid)))

    /// 同じ (seed, t) は 2 回尋ねても同じ絵（保存された状態がない証拠）。
    /// seed を変えると別の絵になる（撃つたびの表情替え）。
    @Test
    def testSeedChangesTheLook(): Unit \ Assert =
        let look = corners(FireFx.quads(FireFx.standard(), burst(), 0.2));
        Assert.assertEq(expected = (true, false),
            (look == corners(FireFx.quads(FireFx.standard(), burst(), 0.2)),
             look == corners(FireFx.quads(FireFx.standard(), {seed = 2 | burst()}, 0.2))))

    /// 5 プリセットすべてが燃え上がり中（0.2 秒）に絵を出す（空のプリセットがない）。
    @Test
    def testEveryPresetBurns(): Unit \ Assert =
        let litAt = spec -> List.length(FireFx.quads(spec, burst(), 0.2)) > 10;
        Assert.assertEq(expected = (true, true, true, true, true),
            (litAt(FireFx.standard()), litAt(FireFx.pillar()), litAt(FireFx.flare()),
             litAt(FireFx.smolder()), litAt(FireFx.arcane())))

    /// 不透明度は演出のどの瞬間でも 0..1 に収まる（点火直後・最盛期・燃え尽き際で確認）。
    @Test
    def testAlphaStaysWithinRange(): Unit \ Assert =
        let ok = t -> List.forAll(q -> q#alpha >= 0.0f32 and q#alpha <= 1.0f32,
                                  FireFx.quads(FireFx.standard(), burst(), t));
        Assert.assertEq(expected = (true, true, true), (ok(0.05), ok(0.2), ok(0.6)))
}
