// Prng（splitmix64）と World の seeded-PRNG carry のテスト（slice `rng-world`）。
//
// 期待値の出所:
//   - frozen 列（seed0/seed42）は COMPILED IMPL の reduction ドメインと一致する標準 splitmix64 から生成。
//   - near-maxValue 列（seedMAX）は **独立した参照実装**（Python の任意精度 splitmix64 を 64bit マスク）で
//     hand-derive したもので、Flix 実装から再生成していない。ゆえに shift/reduction の正しさについて
//     self-confirming にならず、`Int64.logicalRightShift` の zero-fill と Int64 wrap を本当に検証する。

mod TestPrng {

    /// seed st から n 個 percent を draw 順に集める純粋ヘルパー。
    def drawN(n: Int32, st: Prng.State): List[Int32] =
        if (n <= 0) Nil
        else
            let (p, st1) = Prng.nextPercent(st);
            p :: drawN(n - 1, st1)

    // (a) determinism — 同じ seed なら同じ列。
    @Test
    def testDeterministicSameSeed(): Unit \ Assert =
        Assert.assertEq(
            expected = drawN(32, Prng.seed(12345i64)),
            drawN(32, Prng.seed(12345i64)))

    // (a') 別 seed は別の列（自明な定数化のガード）。
    @Test
    def testDifferentSeedDiffers(): Unit \ Assert =
        Assert.assertEq(
            expected = true,
            drawN(16, Prng.seed(1i64)) != drawN(16, Prng.seed(2i64)))

    // (b) range invariant — 全 draw が 0..99。256 draw を fold して min/max を取る。
    @Test
    def testRangeInvariant(): Unit \ Assert =
        let xs = drawN(256, Prng.seed(777i64));
        let lo = List.foldLeft(Int32.min, 999, xs);
        let hi = List.foldLeft(Int32.max, -1, xs);
        Assert.assertEq(expected = (true, true), (lo >= 0, hi <= 99))

    // (c) frozen first-16（seed 0）— COMPILED IMPL の reduction と一致する標準 splitmix64 から生成。
    @Test
    def testFrozenSeed0(): Unit \ Assert =
        Assert.assertEq(
            expected = 88 :: 43 :: 2 :: 97 :: 10 :: 32 :: 17 :: 77 :: 24 :: 95 :: 39 :: 76 :: 52 :: 55 :: 70 :: 51 :: Nil,
            drawN(16, Prng.seed(0i64)))

    // (c') frozen first-16（seed 42）。
    @Test
    def testFrozenSeed42(): Unit \ Assert =
        Assert.assertEq(
            expected = 74 :: 15 :: 27 :: 34 :: 3 :: 86 :: 21 :: 80 :: 33 :: 61 :: 20 :: 49 :: 51 :: 52 :: 66 :: 20 :: Nil,
            drawN(16, Prng.seed(42i64)))

    // (d) nextPercent が state を advance する（2 連続 draw で内部状態が変わる）。
    @Test
    def testStateAdvances(): Unit \ Assert =
        let st0 = Prng.seed(99i64);
        let (_, st1) = Prng.nextPercent(st0);
        let (_, st2) = Prng.nextPercent(st1);
        Assert.assertEq(
            expected = (true, true),
            (Prng.rawState(st1) != Prng.rawState(st0),
             Prng.rawState(st2) != Prng.rawState(st1)))

    // (e) SHIFT-SEMANTICS + Int64-wrap：Int64.maxValue を seed にすると s+gamma が overflow して負値へ wrap し、
    //     splitmix64 の中間値も負になる＝logicalRightShift の zero-fill が効かないと結果がずれる。
    //     期待値は独立参照実装（Python）で hand-derive。Flix 実装からの再生成ではない。
    @Test
    def testNearMaxValueIndependentOracle(): Unit \ Assert =
        Assert.assertEq(
            expected = 16 :: 94 :: 92 :: 12 :: 32 :: 11 :: 17 :: 54 :: Nil,
            drawN(8, Prng.seed(9223372036854775807i64)))

    // (f) unitToPercent boundary mapping — SINGLE SOURCE OF TRUTH の floor 写像を厳密固定する。
    //     unitToPercent は live `World.RngDraw` ハンドラ（Game.flix）と Prng.nextPercent / oracle が
    //     共有する唯一の reduction。ここを floor→round や *100→*99 に変えると live combat の分布 AND
    //     oracle が lockstep でずれて golden-trace は素通り＝live が無言で変わる。range [0,99] だけでなく
    //     **正確な floor 対応**（0.0→0 / 0.5→50 / 0.01→1 / 0.99→99 / 0.999999999→99）を固定する。
    @Test
    def testUnitToPercentBoundaries(): Unit \ Assert =
        Assert.assertEq(
            expected = (0, 50, 1, 99, 99),
            (Prng.unitToPercent(0.0),
             Prng.unitToPercent(0.5),
             Prng.unitToPercent(0.01),
             Prng.unitToPercent(0.99),
             Prng.unitToPercent(0.999999999)))

    // ────────────────────────────────────────────────────────
    // World への seeded-PRNG carry（フレーム更新を生き延びるか）
    // ────────────────────────────────────────────────────────

    // World.drawPercent が seed 列を返し、state を world に書き戻す。
    @Test
    def testWorldDrawPercentSequence(): Unit \ Assert =
        let w0 = World.seedRng(0i64, World.empty());
        let (k1, w1) = World.drawPercent(w0);
        let (k2, _)  = World.drawPercent(w1);
        Assert.assertEq(expected = (88, 43), (k1, k2))

    // multi-frame CARRY: seed → draw k1 → applyCmd + refreshMirror → draw k2。
    // k2 が同じ seed 列の続き（43）になる＝rng がフレーム更新（refreshMirror）と store 書込
    // （applyCmd）を verbatim carry したことの証明。
    // 直接 w1 から引いた k2direct とも一致させ、更新が PRNG を進めも巻き戻しもしないことを固定。
    @Test
    def testRngSurvivesFrameUpdate(): Unit \ Assert =
        let w0 = World.seedRng(0i64, World.empty());
        let (k1, w1) = World.drawPercent(w0);
        let (k2direct, _) = World.drawPercent(w1);
        let wCarried = World.refreshMirror(
            World.applyCmd(World.Cmd.SetHp(World.EntityRef.Player(0), 5), w1));
        let (k2carried, _) = World.drawPercent(wCarried);
        Assert.assertEq(
            expected = (88, 43, 43),
            (k1, k2direct, k2carried))

}
