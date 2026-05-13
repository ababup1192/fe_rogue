/// `DialogueScene.choiceIndexAt` のユニットテスト。
///
/// このシーンは hit-test 自体（マウス位置 → ホバー対象ノード判定）を
/// `Scene.hoveredPathsAt` に任せ、`onHover(path, localPosition)` で受け取る側に専念する。
/// したがってテストすべき純粋ロジックは「Body のローカル Y → 選択肢 index」の写像だけ。
/// 行高さは Body の fontSize から動的に渡される（scene.json の fontSize 変更に追従する）。
mod TestDialogueScene {

    /// ローカル Y = 0 は行 0 にヒットする。
    @Test
    def testChoiceIndexAtZeroIsFirst(): Unit \ Assert =
        Assert.assertEq(expected = Some(0),
            DialogueScene.choiceIndexAt(0.0, 3, 8.0))

    /// ローカル Y = 8 (= lineHeight) は行 1 の先頭。`floor(8 / 8) = 1`。
    @Test
    def testChoiceIndexAtOnSecondLine(): Unit \ Assert =
        Assert.assertEq(expected = Some(1),
            DialogueScene.choiceIndexAt(8.0, 3, 8.0))

    /// 行 1 の途中（Y = 12）も行 1 にスナップする。
    @Test
    def testChoiceIndexAtMidLineSnapsToLine(): Unit \ Assert =
        Assert.assertEq(expected = Some(1),
            DialogueScene.choiceIndexAt(12.0, 3, 8.0))

    /// 最終選択肢の下（Y = 24、3 件中 0..2 のみ有効）は None。
    @Test
    def testChoiceIndexAtBelowChoicesReturnsNone(): Unit \ Assert =
        Assert.assertEq(expected = None,
            DialogueScene.choiceIndexAt(24.0, 3, 8.0))

    /// Y が負（Body 内で何故か上に飛ばされた場合）は None。
    @Test
    def testChoiceIndexAtNegativeYReturnsNone(): Unit \ Assert =
        Assert.assertEq(expected = None,
            DialogueScene.choiceIndexAt(-1.0, 3, 8.0))

    /// 選択肢が空（本文表示中・▼ 待ち相当）は常に None。
    @Test
    def testChoiceIndexAtNoChoicesReturnsNone(): Unit \ Assert =
        Assert.assertEq(expected = None,
            DialogueScene.choiceIndexAt(0.0, 0, 8.0))

    /// lineHeight が 0 以下なら割り算が定義されないので None。
    @Test
    def testChoiceIndexAtZeroLineHeightReturnsNone(): Unit \ Assert =
        Assert.assertEq(expected = None,
            DialogueScene.choiceIndexAt(8.0, 3, 0.0))

    /// fontSize=12 想定で lineHeight を渡すと、行境界も自動的に 12 に追従する。
    /// Y = 12 は行 1 の先頭（fontSize=8 の世界では行 1 中央）。
    @Test
    def testChoiceIndexAtScalesWithLineHeight(): Unit \ Assert =
        Assert.assertEq(expected = Some(1),
            DialogueScene.choiceIndexAt(12.0, 3, 12.0))
}
