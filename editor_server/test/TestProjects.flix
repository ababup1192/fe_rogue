// TestProjects — プロジェクト切替の純粋な部分 (最近開いた履歴の並べ方・探索起点の分解) を固定する。
// 探索や履歴ファイルの読み書きそのもの (IO) は curl での通し確認に任せる。

mod TestProjects {

    // ========================================================================
    // 最近開いた履歴 (pushRecent)
    // ========================================================================

    /// 新しい dir は先頭へ。既にある dir は重複させず先頭へ移すだけ。
    @Test
    def testPushRecentDedup(): Unit \ Assert =
        Assert.assertEq(
            expected = ("/b" :: "/a" :: "/c" :: Nil, "/a" :: "/b" :: "/c" :: Nil),
            (Projects.pushRecent("/b", "/a" :: "/b" :: "/c" :: Nil),
             Projects.pushRecent("/a", "/a" :: "/b" :: "/c" :: Nil)))

    /// 履歴は最新 10 件で打ち切る: 満杯 (10 件) へ 1 件積むと、一番古い末尾が落ちる。
    @Test
    def testPushRecentCap(): Unit \ Assert =
        let full = List.range(0, 10) |> List.map(i -> "/p${i}");
        let pushed = Projects.pushRecent("/new", full);
        Assert.assertEq(
            expected = (10, Some("/new"), false),
            (List.length(pushed), List.head(pushed), List.memberOf("/p9", pushed)))

    // ========================================================================
    // 探索起点 (EDITOR_SCAN_ROOTS) の分解
    // ========================================================================

    /// コロン区切り。空要素 (先頭・連続コロン) は捨てる。
    @Test
    def testSplitRoots(): Unit \ Assert =
        Assert.assertEq(
            expected = ("/a" :: "/b/c" :: Nil, "/only" :: Nil),
            (Projects.splitRoots("/a::/b/c"), Projects.splitRoots(":/only")))

    /// 一覧に見せる題名の代用: パスの最後の要素 (末尾スラッシュがあっても同じ)。
    @Test
    def testBaseNameOf(): Unit \ Assert =
        Assert.assertEq(
            expected = ("liars_room", "liars_room"),
            (Projects.baseNameOf("/Users/x/liars_room"), Projects.baseNameOf("/Users/x/liars_room/")))
}
