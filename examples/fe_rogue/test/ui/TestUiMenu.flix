/// UiMenu の選択ハイライト箱の位置決め・防御クランプの純関数を pin する。
///
/// applyHighlight / clampSelection は UiWorld を触る結線だが、その中核ロジック
/// （行ピッチと選択 index から塗り箱の abs を出す・選択を範囲内へ収める）は
/// `highlightPlacement` / `clampIndex` の純関数へ切り出してある。ここはその純関数を直接観測する。
mod TestUiMenu {

    /// highlightPlacement の結果を (x, y) タプルの Option で読む（比較しやすくする）。
    def placement(itemCount: Int32, sel: Int32): Option[(Float64, Float64)] =
        UiMenu.highlightPlacement(itemCount, sel, 8.0, 0.5) |> Option.map(v -> (v#x, v#y))

    // ════════════════════════════════════════════════════════
    // highlightPlacement: 塗り箱を `inset + sel × rowPitch` へ決定論的に置く
    //   rowPitch=8, inset=0.5 のとき  sel0 → y0.5 / sel1 → y8.5 / sel2 → y16.5、x は常に inset=0.5
    // ════════════════════════════════════════════════════════

    /// 3 項目で sel=0/1/2 の箱 abs が (0.5,0.5)/(0.5,8.5)/(0.5,16.5)。
    @Test
    def testPlacementPositionsPerRow(): Unit \ Assert =
        Assert.assertEq(
            expected = (Some((0.5, 0.5)), Some((0.5, 8.5)), Some((0.5, 16.5))),
            (placement(3, 0), placement(3, 1), placement(3, 2)))

    /// 範囲外 sel=99 は末尾(2)へ、負 sel=-5 は先頭(0)へクランプして置く。
    @Test
    def testPlacementClampsOutOfRange(): Unit \ Assert =
        Assert.assertEq(
            expected = (Some((0.5, 16.5)), Some((0.5, 0.5))),
            (placement(3, 99), placement(3, -5)))

    /// 項目 0 個なら None（塗り箱を隠す合図）。
    @Test
    def testPlacementNoneWhenNoItems(): Unit \ Assert =
        Assert.assertEq(expected = None, placement(0, 0))

    // ════════════════════════════════════════════════════════
    // clampIndex: 選択 index を [0, 項目数) へ収める
    // ════════════════════════════════════════════════════════

    /// 範囲外(99)→末尾2、負(-5)→0、範囲内(1)→1、項目0→0。
    @Test
    def testClampIndex(): Unit \ Assert =
        Assert.assertEq(
            expected = (2, 0, 1, 0),
            (UiMenu.clampIndex(3, 99), UiMenu.clampIndex(3, -5),
             UiMenu.clampIndex(3, 1), UiMenu.clampIndex(0, 5)))
}
