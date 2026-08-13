// DocTable のテスト。テストするのは「テーブル 1 枚から 3 つの形が正しく導出されるか」だけ —
// リロード関数の中身(ファイル読み)は各 Doc 側の橋渡しテストの仕事。
mod TestDocTable {

    def rows(): List[DocTable.Entry[Int32]] =
        { docId = Some("theme"), path = "a.theme.json", reload = w -> checked_ecast(w + 1) } ::
        { docId = Some("sprite"), path = "p.sprite.json", reload = w -> checked_ecast(w * 2) } ::
        { docId = None, path = "mob.sprite.json", reload = w -> checked_ecast(w + 10) } ::
        { docId = Some("sprite"), path = "t.sprite.json", reload = w -> checked_ecast(w) } :: Nil

    /// watchFile へ渡す形はテーブルの全行(id が None でも監視する)を並び順のまま持つ。
    @Test
    def testReloadsKeepsEveryRowInOrder(): Unit \ Assert =
        Assert.assertEq(
            expected = "a.theme.json" :: "p.sprite.json" :: "mob.sprite.json"
                :: "t.sprite.json" :: Nil,
            DocTable.reloads(rows()) |> List.map(fst))

    /// 一括リロードはテーブルの並び順に適用する — 「導出 Doc は依存先より後ろの行に」の
    /// この決まりを順序が支える。rows の関数は非可換(逆順なら 21)なので順序が固定される。
    @Test
    def testReloadAllAppliesRowsInOrder(): Unit \ {Assert, IO} =
        let got = run { DocTable.reloadAll(rows(), 0) } with Fs.FileRead.runWithIO;
        Assert.assertEq(expected = 12, got)

    /// ActiveDocs へ渡す形は id ごとに束なり、None の行は出ず、離れた同 id 行も
    /// 最初に現れた位置へ集まる。
    @Test
    def testActiveDocsGroupsByIdAndSkipsNone(): Unit \ Assert =
        Assert.assertEq(
            expected = ("theme", "a.theme.json" :: Nil)
                :: ("sprite", "p.sprite.json" :: "t.sprite.json" :: Nil) :: Nil,
            DocTable.activeDocs(rows()))
}
