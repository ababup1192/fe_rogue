// DocTable のテスト。テストするのは「テーブル 1 枚から 3 つの形が正しく導出されるか」だけ —
// リロード関数の中身(ファイル読み)は各 Doc 側の橋渡しテストの仕事。
mod TestDocTable {

    def rows(): List[DocTable.Entry[Int32]] =
        DocTable.row("theme", "a.theme.json", w -> checked_ecast(w + 1)) ::
        DocTable.row("sprite", "p.sprite.json", w -> checked_ecast(w * 2)) ::
        DocTable.unnamedRow("mob.sprite.json", w -> checked_ecast(w + 10)) ::
        DocTable.row("sprite", "t.sprite.json", w -> checked_ecast(w)) :: Nil

    /// watchFile へ渡す形は監視する行(id が None でも監視する)を並び順のまま持つ。
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
            DocTable.activeDocs(rows(), 0))

    /// withoutWatch の行は watchFile に出ない(保存を検知しても読み直さない)。
    @Test
    def testRowWithoutWatchIsNotWatched(): Unit \ Assert =
        let rs = DocTable.row("ui", "a.ui.json", w -> checked_ecast(w + 1))
                     |> DocTable.withoutWatch :: Nil;
        Assert.assertEq(expected = Nil, DocTable.reloads(rs) |> List.map(fst))

    /// withoutReloadAll の行は F1 の一括に出ない(別の行が巻き添えで作り直す Doc)。
    @Test
    def testRowWithoutReloadAllIsSkippedByReloadAll(): Unit \ {Assert, IO} =
        let rs = DocTable.row("fx", "a.fx.json", w -> checked_ecast(w + 1))
                     |> DocTable.withoutReloadAll :: Nil;
        let got = run { DocTable.reloadAll(rs, 0) } with Fs.FileRead.runWithIO;
        Assert.assertEq(expected = 0, got)

    /// 場面つきの 1 行。activeWhen が false の world では名乗らない。
    def phased(): List[DocTable.Entry[Int32]] =
        DocTable.row("battle", "b.battle.json", w -> checked_ecast(w + 1))
            |> DocTable.withActiveWhen(w -> w > 0) :: Nil

    @Test
    def testActiveWhenHidesRow(): Unit \ Assert =
        Assert.assertEq(expected = Nil, DocTable.activeDocs(phased(), 0))

    @Test
    def testActiveWhenShowsRow(): Unit \ Assert =
        Assert.assertEq(expected = ("battle", "b.battle.json" :: Nil) :: Nil,
            DocTable.activeDocs(phased(), 1))

    /// 名乗らない場面でも監視は続く（保存即反映は場面に依らない）。
    @Test
    def testHiddenRowIsStillWatched(): Unit \ Assert =
        Assert.assertEq(expected = "b.battle.json" :: Nil,
            DocTable.reloads(phased()) |> List.map(fst))

    /// 名乗らない場面でも F1 の一括では読み直す（次に出たとき古いままにしない）。
    @Test
    def testHiddenRowIsStillReloadedByReloadAll(): Unit \ {Assert, IO} =
        let got = run { DocTable.reloadAll(phased(), 0) } with Fs.FileRead.runWithIO;
        Assert.assertEq(expected = 1, got)

    /// 同じ id の 2 行のうち片方だけが出る場面では、出ている方のパスだけが束なる。
    @Test
    def testActiveDocsKeepsOnlyShownPathsOfSameId(): Unit \ Assert =
        let rs = DocTable.row("ui", "dialog.ui.json", w -> checked_ecast(w)) ::
                 DocTable.row("ui", "choices.ui.json", w -> checked_ecast(w))
                     |> DocTable.withActiveWhen(w -> w > 0) :: Nil;
        Assert.assertEq(expected = ("ui", "dialog.ui.json" :: Nil) :: Nil,
            DocTable.activeDocs(rs, 0))

    /// 読み直しの片面を外した行も「表示中」には出続ける（reloadOn は名乗りに効かない）。
    @Test
    def testRowWithoutReloadAllStillNamesItself(): Unit \ Assert =
        let rs = DocTable.row("fx", "a.fx.json", w -> checked_ecast(w))
                     |> DocTable.withoutReloadAll :: Nil;
        Assert.assertEq(expected = ("fx", "a.fx.json" :: Nil) :: Nil,
            DocTable.activeDocs(rs, 0))

    /// 保存を見ない行も同じく「表示中」には出続ける（novel の ui.json がこの形）。
    @Test
    def testRowWithoutWatchStillNamesItself(): Unit \ Assert =
        let rs = DocTable.row("ui", "a.ui.json", w -> checked_ecast(w))
                     |> DocTable.withoutWatch :: Nil;
        Assert.assertEq(expected = ("ui", "a.ui.json" :: Nil) :: Nil,
            DocTable.activeDocs(rs, 0))

    /// 修飾子は重ね掛けでき、順序は結果に効かない。
    @Test
    def testModifiersCommute(): Unit \ Assert =
        let base = () -> DocTable.row("x", "x.json", w -> checked_ecast(w));
        let a = base() |> DocTable.withoutReloadAll |> DocTable.withActiveWhen(w -> w > 0);
        let b = base() |> DocTable.withActiveWhen(w -> w > 0) |> DocTable.withoutReloadAll;
        Assert.assertEq(expected = (a#reloadOn, DocTable.activeDocs(a :: Nil, 1)),
            (b#reloadOn, DocTable.activeDocs(b :: Nil, 1)))
}
