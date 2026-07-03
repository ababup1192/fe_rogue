/// UiWidget の選択カーソル純関数を固定する。
/// selectionMove（単純回り込み）と selectionMoveSkipping（disabled スキップ）を pin する。
mod TestUiWidget {

    // ════════════════════════════════════════════════════════
    // selectionMove: 端で回り込む
    // ════════════════════════════════════════════════════════

    /// count=3 のとき 2 から +1 で 0（末尾→先頭）、0 から -1 で 2（先頭→末尾）。
    @Test
    def testSelectionMoveWraps(): Unit \ Assert =
        Assert.assertEq(
            expected = (0, 2),
            (UiWidget.selectionMove(3, 1, 2), UiWidget.selectionMove(3, -1, 0)))

    /// count<=0（項目なし）は 0。
    @Test
    def testSelectionMoveEmpty(): Unit \ Assert =
        Assert.assertEq(expected = 0, UiWidget.selectionMove(0, 1, 0))

    // ════════════════════════════════════════════════════════
    // selectionMoveSkipping: disabled をまたいで動く
    // ════════════════════════════════════════════════════════

    /// index1・2 が disabled のリスト（0,3 のみ選択可）。
    ///   0 --+1--> 3（1,2 を飛ばす）、3 --+1--> 0（末尾で回り込み）、
    ///   0 --(-1)--> 3（先頭で回り込み）、3 --(-1)--> 0。
    @Test
    def testSkipDisabledMiddle(): Unit \ Assert =
        let disabled = i -> i == 1 or i == 2;
        Assert.assertEq(
            expected = (3, 0, 3, 0),
            (UiWidget.selectionMoveSkipping(4, 1, 0, disabled),
             UiWidget.selectionMoveSkipping(4, 1, 3, disabled),
             UiWidget.selectionMoveSkipping(4, -1, 0, disabled),
             UiWidget.selectionMoveSkipping(4, -1, 3, disabled)))

    /// 全項目 disabled なら現在位置を保つ（移動先が無い）。
    @Test
    def testSkipAllDisabledStays(): Unit \ Assert =
        let disabled = _ -> true;
        Assert.assertEq(
            expected = 2,
            UiWidget.selectionMoveSkipping(4, 1, 2, disabled))

    /// 自分だけが選択可能なら、動かそうとしても同じ位置に留まる。
    @Test
    def testSkipOnlySelfEnabledStays(): Unit \ Assert =
        let disabled = i -> i != 1;
        Assert.assertEq(
            expected = (1, 1),
            (UiWidget.selectionMoveSkipping(4, 1, 1, disabled),
             UiWidget.selectionMoveSkipping(4, -1, 1, disabled)))

    /// disabled が無いときは selectionMove と同じ（隣へ 1 つ・端で回り込み）。
    @Test
    def testSkipNoneBehavesLikePlainMove(): Unit \ Assert =
        let noneDisabled = _ -> false;
        Assert.assertEq(
            expected = (1, 0),
            (UiWidget.selectionMoveSkipping(3, 1, 0, noneDisabled),
             UiWidget.selectionMoveSkipping(3, 1, 2, noneDisabled)))
}
