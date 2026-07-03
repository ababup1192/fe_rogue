/// LevelUpPanelUi の本文整形（段階表示ゲート）テスト
///
/// レベルアップ演出は「出し終えた行数」`revealed` に応じて、現在値・矢印・新値・+1 を段階的に出す。
/// この「どの行にどの列を出すか」の純関数（colBeforeOf / colArrowOf / colAfterOf / colPlusOf）と
/// ヘッダ整形（formatHeader）を pin する。
///
/// フィクスチャ（3 ステータス）:
///   idx0 HP  20 -> 21  (gained)
///   idx1 力   5 ->  5  (据え置き)
///   idx2 技   7 ->  8  (gained)
mod TestLevelUpPanelUi {

    /// テスト用の 3 行ぶんの StatChange 列。
    def changes(): List[LevelSystem.StatChange] =
        ({label = "HP", before = 20, after = 21, gained = true}: LevelSystem.StatChange) ::
        ({label = "力", before = 5,  after = 5,  gained = false}: LevelSystem.StatChange) ::
        ({label = "技", before = 7,  after = 8,  gained = true}: LevelSystem.StatChange) :: Nil

    // ════════════════════════════════════════════════════════
    // ヘッダ
    // ════════════════════════════════════════════════════════

    /// ヘッダは「{兵種名}   Lv {前} -> Lv {後}」。
    @Test
    def testFormatHeader(): Unit \ Assert =
        let result: LevelSystem.Result =
            {unitName = "ロード", fromLevel = 4, toLevel = 5, changes = Nil};
        Assert.assertEq(
            expected = "ロード   Lv 4 -> Lv 5",
            LevelUpPanelUi.formatHeader(result))

    // ════════════════════════════════════════════════════════
    // ラベル列（常に全行）
    // ════════════════════════════════════════════════════════

    /// ラベル列は revealed に関係なく全行のステータス名を縦に並べる。
    @Test
    def testColLabelsShowsAllRows(): Unit \ Assert =
        Assert.assertEq(
            expected = "HP\n力\n技",
            LevelUpPanelUi.colLabelsOf(changes()))

    // ════════════════════════════════════════════════════════
    // 現在値列（revealed でゲート・上昇有無に依らず出す）
    // ════════════════════════════════════════════════════════

    /// 現在値は「出し終えた行（offset + i < revealed）」にだけ出す（上昇有無は問わない）。
    /// revealed=2 → idx0,1 を出し idx2 は空。
    @Test
    def testColBeforeRevealGate(): Unit \ Assert =
        Assert.assertEq(
            expected = "20\n5\n",
            LevelUpPanelUi.colBeforeOf(changes(), 0, 2))

    /// offset は「右列の global index 起点」。offset=1・revealed=2 なら idx0 だけ出る
    /// （global index 1 < 2 のみ）。
    @Test
    def testColBeforeOffsetShiftsThreshold(): Unit \ Assert =
        Assert.assertEq(
            expected = "20\n\n",
            LevelUpPanelUi.colBeforeOf(changes(), 1, 2))

    // ════════════════════════════════════════════════════════
    // 矢印 / 新値 / +1 列（出した行のうち「上昇した行」だけ）
    // ════════════════════════════════════════════════════════

    /// 全行出し切り（revealed=3）で、上昇した行（idx0/idx2）だけ矢印・新値・+1 が出て、
    /// 据え置き（idx1）は空になること（3 列まとめて 1 assert で確認）。
    @Test
    def testGainedOnlyColumns(): Unit \ Assert =
        let arrow = LevelUpPanelUi.colArrowOf(changes(), 0, 3);
        let after = LevelUpPanelUi.colAfterOf(changes(), 0, 3);
        let plus  = LevelUpPanelUi.colPlusOf(changes(), 0, 3);
        Assert.assertEq(
            expected = ("->\n\n->", "21\n\n8", "+1\n\n+1"),
            (arrow, after, plus))

    /// まだ出していない行（revealed=0）は上昇していても新値・+1 を出さない（全空）。
    @Test
    def testNotYetRevealedIsEmpty(): Unit \ Assert =
        let after = LevelUpPanelUi.colAfterOf(changes(), 0, 0);
        let plus  = LevelUpPanelUi.colPlusOf(changes(), 0, 0);
        Assert.assertEq(
            expected = ("\n\n", "\n\n"),
            (after, plus))
}
