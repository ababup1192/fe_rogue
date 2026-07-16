// TestFileIndex — /files の走査が除外ディレクトリに「降りない」ことを固定する。
// 実ディスクは使わず、子一覧を返す関数を偽物に差し替えて走査だけを見る。

mod TestFileIndex {

    /// 偽のディレクトリ木:
    ///   /            … assets/  build/  top.ui.json  README.md
    ///   /assets      … Hud.ui.json  hitbox.json  nested/
    ///   /assets/nested … Deep.ui.json
    /// build/ の中身を聞かれたら即バグ扱い — 除外が「結果のフィルタ」でなく
    /// 「走査の打ち切り」であることをここで証明する。
    def fakeChildren(relDir: String): List[FileIndex.DirEntry] =
        match relDir {
            case ""              => {name = "assets", isDir = true} :: {name = "build", isDir = true}
                                    :: {name = "top.ui.json", isDir = false} :: {name = "README.md", isDir = false} :: Nil
            case "assets"        => {name = "Hud.ui.json", isDir = false} :: {name = "hitbox.json", isDir = false}
                                    :: {name = "nested", isDir = true} :: Nil
            case "assets/nested" => {name = "Deep.ui.json", isDir = false} :: Nil
            case "build"         => bug!("walkJson must not descend into build/")
            case other           => bug!("walkJson visited an unexpected directory: ${other}")
        }

    /// 集まるのは .json の相対パスだけ (.md は落ちる)。build/ は最初から歩かない
    /// (歩けば fakeChildren の bug! で即座に赤になる)。
    @Test
    def testWalkJsonPrunesExcludedDirs(): Unit \ Assert =
        Assert.assertEq(
            expected = "assets/Hud.ui.json" :: "assets/hitbox.json" :: "assets/nested/Deep.ui.json" :: "top.ui.json" :: Nil,
            FileIndex.walkJson(fakeChildren, "") |> List.sort)

    // ══ /changes の対象集合と token ═══════════════════════

    /// 対象に残るのは ui / hitbox / fx / *.preview.json / project.json / 実在パレット。
    /// 走査に無いパレット参照 (missing.json) と無関係な .json (level.json 等) は落ちる。
    @Test
    def testChangeTargetsPicksEditorFacingFiles(): Unit \ Assert =
        let all = "assets/hud.ui.json" :: "assets/hud.preview.json" :: "assets/hitbox.json"
               :: "assets/explosion.fx.json"
               :: "assets/palette.json" :: "assets/level.json" :: "project.json" :: "devbox.json" :: Nil;
        Assert.assertEq(
            expected = "assets/explosion.fx.json" :: "assets/hitbox.json" :: "assets/hud.preview.json"
                    :: "assets/hud.ui.json" :: "assets/palette.json" :: "project.json" :: Nil,
            FileIndex.changeTargets("assets/palette.json" :: "assets/missing.json" :: Nil, all))

    /// パレットが *.ui.json でもあるような重複指定は 1 件に畳まれる。
    @Test
    def testChangeTargetsDedupes(): Unit \ Assert =
        Assert.assertEq(
            expected = "a.ui.json" :: Nil,
            FileIndex.changeTargets("a.ui.json" :: Nil, "a.ui.json" :: Nil))

    /// token は「同じ一覧なら同じ・mtime が 1 つ変わる/件数が変わると別」の集計値。
    @Test
    def testChangeTokenReactsToMtimeAndCount(): Unit \ Assert =
        let base = ("a.ui.json", 100i64) :: ("b.ui.json", 200i64) :: Nil;
        let touched = ("a.ui.json", 100i64) :: ("b.ui.json", 201i64) :: Nil;
        let removed = ("a.ui.json", 100i64) :: Nil;
        Assert.assertEq(
            expected = (true, false, false),
            (FileIndex.changeToken(base) == FileIndex.changeToken(base),
             FileIndex.changeToken(base) == FileIndex.changeToken(touched),
             FileIndex.changeToken(base) == FileIndex.changeToken(removed)))
}
