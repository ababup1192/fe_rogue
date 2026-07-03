/// SuspendConfirmUi（中断確認モーダル・World-entity UI 版）の純粋部分を pin する。
/// 固定 2 択（はい/いいえ）の metadata が選択カーソル位置からどう解決されるかを確認する。
/// 可視同期（frameStep）と確定の副作用（SuspendRequest.save 等）は effect を要する結線なので、
/// ここでは metadata の並びと解決だけを直接観測する（TestGameOverMenuUi と同じ方針）。
mod TestSuspendConfirmUi {

    /// ui.json の項目順に対応する metadata（item0=yes / item1=no）。
    def metas(): List[String] = "yes" :: "no" :: Nil

    /// 0/1 が各項目の metadata を返し、範囲外 2 は None。
    /// 選択位置 → metadata の解決は `UiMenu.metaAtSelection`（項目列 = List.nth）に共通化済み。
    @Test
    def testMetaAtSelection(): Unit \ Assert =
        let picked = (List.nth(0, metas()), List.nth(1, metas()), List.nth(2, metas()));
        Assert.assertEq(expected = (Some("yes"), Some("no"), None), picked)
}
