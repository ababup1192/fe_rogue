/// UnitInfoPopupScene の純粋判定部分のテスト
///
/// `process` の意思決定を切り出した `decideProcess`（effect なし）と、表示モード反転の
/// `flipMode` を、Scene[NodeTag] / effect を一切使わず値だけで検証する。
///
/// decideProcess の分類:
///   - カーソル非アクティブ + 未表示       → Keep（何もしない）
///   - カーソル非アクティブ + 表示中       → Hide
///   - アクティブ + 前回と同一ユニット同HP → Keep（再描画不要）
///   - アクティブ + 同一ユニットでHP変動   → Render（viewMode 維持）
///   - アクティブ + 別ユニットへ移動       → Render（viewMode を Status にリセット）
///   - アクティブ + カーソルが空マス       → Hide
mod TestUnitInfoPopupScene {

    use UnitInfoPopupScene.ViewMode
    use UnitInfoPopupScene.PopupAction

    // ════════════════════════════════════════════════════════
    // decideProcess
    // ════════════════════════════════════════════════════════

    /// 非アクティブ（PlayerCursor 以外 / バナー表示中）でもともと未表示なら何もしない。
    @Test
    def testKeepWhenInactiveAndNothingShown(): Unit \ Assert =
        let result = UnitInfoPopupScene.decideProcess(
            false, None, None, None, None, ViewMode.Status);
        Assert.assertEq(expected = PopupAction.Keep, result)

    /// 非アクティブだが表示中（prevIdent あり）なら隠す。
    @Test
    def testHideWhenInactiveButShown(): Unit \ Assert =
        let result = UnitInfoPopupScene.decideProcess(
            false, None, Some(("player", 1)), None, Some(10), ViewMode.Status);
        Assert.assertEq(expected = PopupAction.Hide, result)

    /// アクティブで前回と同一ユニット・同一 HP なら再描画不要（Keep）。
    @Test
    def testKeepWhenSameUnitSameHp(): Unit \ Assert =
        let result = UnitInfoPopupScene.decideProcess(
            true, Some(("enemy", 2)), Some(("enemy", 2)),
            Some(5), Some(5), ViewMode.Items);
        Assert.assertEq(expected = PopupAction.Keep, result)

    /// アクティブで同一ユニットだが HP が変動 → 再描画。viewMode は維持する。
    @Test
    def testRenderKeepsModeWhenSameUnitHpChanged(): Unit \ Assert =
        let result = UnitInfoPopupScene.decideProcess(
            true, Some(("enemy", 2)), Some(("enemy", 2)),
            Some(3), Some(5), ViewMode.Items);
        Assert.assertEq(
            expected = PopupAction.Render("enemy", 2, ViewMode.Items),
            result)

    /// アクティブで別ユニットへ移動 → 再描画。viewMode は Status にリセットする。
    @Test
    def testRenderResetsModeWhenUnitChanged(): Unit \ Assert =
        let result = UnitInfoPopupScene.decideProcess(
            true, Some(("player", 1)), Some(("enemy", 2)),
            Some(9), Some(5), ViewMode.Items);
        Assert.assertEq(
            expected = PopupAction.Render("player", 1, ViewMode.Status),
            result)

    /// アクティブで初めてユニットに乗った（前回未表示）→ Status で描画。
    @Test
    def testRenderStatusOnFirstAppearance(): Unit \ Assert =
        let result = UnitInfoPopupScene.decideProcess(
            true, Some(("player", 1)), None, Some(9), None, ViewMode.Status);
        Assert.assertEq(
            expected = PopupAction.Render("player", 1, ViewMode.Status),
            result)

    /// アクティブでカーソルが空マスへ移動（unitIdent=None, 表示中）→ Hide。
    @Test
    def testHideWhenCursorOnEmptyTile(): Unit \ Assert =
        let result = UnitInfoPopupScene.decideProcess(
            true, None, Some(("enemy", 2)), None, Some(5), ViewMode.Items);
        Assert.assertEq(expected = PopupAction.Hide, result)

    // ════════════════════════════════════════════════════════
    // flipMode
    // ════════════════════════════════════════════════════════

    /// Status → Items
    @Test
    def testFlipModeStatusToItems(): Unit \ Assert =
        Assert.assertEq(
            expected = ViewMode.Items,
            UnitInfoPopupScene.flipMode(ViewMode.Status))

    /// Items → Status
    @Test
    def testFlipModeItemsToStatus(): Unit \ Assert =
        Assert.assertEq(
            expected = ViewMode.Status,
            UnitInfoPopupScene.flipMode(ViewMode.Items))
}
