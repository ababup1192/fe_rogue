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
}
