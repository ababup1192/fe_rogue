// FileIndex — 編集対象プロジェクト配下のファイル一覧と、安全な読み書きの窓口。
// パスは常に「プロジェクトディレクトリ (dir) からの相対」で受け渡す。
// ブラウザから来るパスをそのまま信じるとプロジェクト外を読み書きできてしまうので、
// 読み書きは必ず resolveInside の門番を通す。

mod FileIndex {
    import java.io.{File => JFile}

    /// 一覧から除外するディレクトリ名。生成物・依存・履歴はエディタの編集対象にしない。
    def excludedDirs(): Set[String] = Set#{"build", "lib", ".git", "gallery", ".devbox"}

    /// dir 配下の編集対象ファイルを列挙する。*.ui.json は ui、hitbox.json は hitbox。
    /// 返るパスは dir 相対。
    pub def listFiles(dir: String): {ui = List[String], hitbox = List[String]} \ Fs.Glob =
        // `**` が直下 (深さ 0) のファイルに掛かるかは glob 実装に依存するため、
        // 直下用の `*.json` も重ねて引いて取りこぼしを防ぐ。
        let all = (globJson(dir, "**/*.json") ::: globJson(dir, "*.json"))
            |> List.distinct
            |> List.filter(path -> not isExcluded(path))
            |> List.sort;
        { ui     = all |> List.filter(path -> String.endsWith(suffix = ".ui.json", path)),
          hitbox = all |> List.filter(path -> baseName(path) == "hitbox.json") }

    /// パターンに合うファイルを dir 相対パスのリストで返す。列挙できなければ空。
    def globJson(dir: String, pattern: String): List[String] \ Fs.Glob =
        Fs.Glob.glob(dir, pattern)
            |> Result.getWithDefault(Nil)
            |> List.map(path -> stripRoot(dir, path))

    /// glob は絶対パス or rootDir 相対で返すので、rootDir プレフィックスを剥がして相対形に揃える。
    def stripRoot(dir: String, path: String): String =
        if (String.startsWith(prefix = dir + "/", path))
            path.substring(String.length(dir) + 1)
        else if (String.startsWith(prefix = dir, path))
            path.substring(String.length(dir))
        else
            path

    /// パスのどこかの階層が除外ディレクトリ名に一致するか。
    def isExcluded(path: String): Bool =
        String.splitOn(substr = "/", path)
            |> List.exists(segment -> Set.memberOf(segment, excludedDirs()))

    /// パスの最後の要素 (ファイル名)。
    def baseName(path: String): String =
        String.splitOn(substr = "/", path) |> List.last |> Option.getWithDefault(path)

    // ── 読み書き ──────────────────────────────────────────

    /// リクエストで来た相対パスを dir 配下の絶対パスへ解決する。
    /// 絶対パス・`..` 入り・正規化すると dir の外へ出るものは None。
    /// ブラウザから来る値でプロジェクト外を読み書きさせないための門番。
    pub def resolveInside(dir: String, relPath: String): Option[String] \ IO =
        let hasDotDot = String.splitOn(substr = "/", relPath) |> List.exists(segment -> segment == "..");
        if (String.startsWith(prefix = "/", relPath) or hasDotDot)
            None
        else {
            let rootCanonical = new JFile(dir).getCanonicalPath();
            let target = new JFile("${dir}/${relPath}").getCanonicalPath();
            if (String.startsWith(prefix = rootCanonical + "/", target)) Some(target) else None
        }

    /// dir 相対パスのファイルを読む。プロジェクト外・読めないは Err(理由)。
    pub def readInside(dir: String, relPath: String): Result[String, String] \ IO =
        match resolveInside(dir, relPath) {
            case None => Err("path is outside the project: ${relPath}")
            case Some(fullPath) =>
                let readResult = run { Fs.ReadFile.read(fullPath) }
                    with Fs.ReadFile.runWithFileRead
                    with Fs.FileRead.runWithIO;
                readResult |> Result.mapErr(ioError -> "read failed: ${ioError}")
        }

    /// dir 相対パスへ文字列を書き込む。プロジェクト外・親ディレクトリ不在は Err(理由)。
    pub def writeInside(str: {str = String}, dir: String, relPath: String): Result[String, Unit] \ IO =
        match resolveInside(dir, relPath) {
            case None => Err("path is outside the project: ${relPath}")
            case Some(fullPath) =>
                let parent = new JFile(fullPath).getParentFile();
                // 新しいディレクトリは作らない: 置き場所の打ち間違いが静かにディレクトリを増やすのを防ぐ。
                if (Object.isNull(parent) or not parent.isDirectory())
                    Err("parent directory does not exist: ${relPath}")
                else {
                    let writeResult = run { Fs.WriteFile.write(str, fullPath) }
                        with Fs.WriteFile.runWithFileWrite
                        with Fs.FileWrite.runWithIO;
                    writeResult
                        |> Result.mapErr(ioError -> "write failed: ${ioError}")
                        |> Result.map(_ -> ())
                }
        }
}
