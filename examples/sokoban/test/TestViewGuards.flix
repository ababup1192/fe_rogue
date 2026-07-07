// TestViewGuards — 絵の健全性を fail で守る検査（生成はしない）。
// UI 2 ページ（Title / Clear）を幾何リンタにかけ、違反（非抑制 Finding）があれば
// その説明文が差分にそのまま並ぶ。末尾の bool は「リンタがちゃんと要素を見た」
// ことの保証: ブリッジが空リストを返して空虚に clean になる退行を防ぐ。
// ロボットのパーツ数も同じ思想の下限ガード（描画関数が空を返す退行の検出）。

mod TestViewGuards {

    @Test
    def testUiPagesPassRenderLint(): Unit \ {Assert, IO} =
        let atlas = Harness.atlas();
        match Harness.ui() {
            case None     => Assert.assertEq(expected = "spawned", "the ui specs failed to spawn")
            case Some(ui) =>
                let titleInput = GameGallery.lintInput(
                    "screen_title", atlas, ui, Worldline.make(Board.titleWorld(), Sokoban.historyCap()));
                let clearInput = GameGallery.lintInput(
                    "screen_clear", atlas, ui, GameGallery.clearedAndRainingLine());
                Assert.assertEq(
                    expected = ((Nil: List[String]), (Nil: List[String]), true, true),
                    (SokobanLint.activeDetails(RenderLint.check(titleInput)),
                     SokobanLint.activeDetails(RenderLint.check(clearInput)),
                     not List.isEmpty(titleInput#elements),
                     not List.isEmpty(clearInput#elements)))
        }

    @Test
    def testRobotDrawingsProvideParts(): Unit \ {Assert, IO} =
        let (candidateItems, candidatePolys, directionItems) = RobotGallery.partCounts();
        Assert.assertEq(expected = (true, 1, true),
            (candidateItems > 50, candidatePolys, directionItems > 30))
}
