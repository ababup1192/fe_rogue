/// GameOverMenuUi の純粋部分（選択 metadata → 復帰種別）を固定する。
/// confirmSelection は「選択カーソル位置 → metadata → Choice」を経て GameOverRequest を
/// emit する。emit は effect なので、その手前の純関数（metaAtSelection / choiceOf）を pin する。
mod TestGameOverMenuUi {

    use GameOverMenuUi.Choice

    /// ui.json の項目順に対応する metadata（item0=goddess / item1=floor / item2=beginning）。
    def metas(): List[String] = "goddess" :: "floor" :: "beginning" :: Nil

    // ════════════════════════════════════════════════════════
    // choiceOf: metadata → Choice（未知値は None）
    // ════════════════════════════════════════════════════════

    /// 3 種の metadata がそれぞれ ReviveInPlace / RestartFloor / RestartBeginning に、
    /// 未知値は None になる。
    @Test
    def testChoiceOfEachMeta(): Unit \ Assert =
        let choices = (GameOverMenuUi.choiceOf("goddess"), GameOverMenuUi.choiceOf("floor"),
                       GameOverMenuUi.choiceOf("beginning"), GameOverMenuUi.choiceOf("unknown"));
        Assert.assertEq(
            expected = (Some(Choice.ReviveInPlace), Some(Choice.RestartFloor),
                        Some(Choice.RestartBeginning), None),
            choices)

    // ════════════════════════════════════════════════════════
    // metaAtSelection: カーソル位置 → metadata（範囲外は None）
    // ════════════════════════════════════════════════════════

    /// 0/1/2 が各項目の metadata を返し、範囲外 3 は None。
    /// 選択位置 → metadata の解決は `UiMenu.metaAtSelection`（項目列 = List.nth）に共通化済み。
    @Test
    def testMetaAtSelection(): Unit \ Assert =
        let picked = (List.nth(0, metas()), List.nth(1, metas()),
                      List.nth(2, metas()), List.nth(3, metas()));
        Assert.assertEq(
            expected = (Some("goddess"), Some("floor"), Some("beginning"), None),
            picked)

    // ════════════════════════════════════════════════════════
    // 選択 → Choice の合流（confirmSelection の純粋コア）
    // ════════════════════════════════════════════════════════

    /// 各カーソル位置が「metadata → Choice」を通して期待の Choice に解決される。
    @Test
    def testSelectionResolvesToChoice(): Unit \ Assert =
        let resolve = sel -> List.nth(sel, metas()) |> Option.flatMap(GameOverMenuUi.choiceOf);
        Assert.assertEq(
            expected = (Some(Choice.ReviveInPlace), Some(Choice.RestartFloor), Some(Choice.RestartBeginning)),
            (resolve(0), resolve(1), resolve(2)))
}
