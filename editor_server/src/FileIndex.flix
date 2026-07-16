// FileIndex — 編集対象プロジェクト配下のファイル一覧と、安全な読み書きの窓口。
// パスは常に「プロジェクトディレクトリ (dir) からの相対」で受け渡す。
// ブラウザから来るパスをそのまま信じるとプロジェクト外を読み書きできてしまうので、
// 読み書きは必ず resolveInside の門番を通す。

mod FileIndex {
    import java.io.{File => JFile}

    /// 走査から除外するディレクトリ名。生成物・依存・履歴はエディタの編集対象にしない。
    pub def excludedDirs(): Set[String] = Set#{"build", "lib", ".git", "gallery", ".devbox", "node_modules"}

    /// ディレクトリの中身 1 件 (名前と、ディレクトリかどうか)。
    pub type alias DirEntry = {name = String, isDir = Bool}

    /// dir 配下の編集対象ファイルを列挙する。*.ui.json は ui、hitbox.json は hitbox、
    /// *.fx.json は fx。返るパスは dir 相対。
    pub def listFiles(dir: String): {ui = List[String], hitbox = List[String], fx = List[String]} \ IO =
        let all = listAllJson(dir);
        { ui     = all |> List.filter(path -> String.endsWith(suffix = ".ui.json", path)),
          hitbox = all |> List.filter(path -> baseName(path) == "hitbox.json"),
          fx     = all |> List.filter(path -> String.endsWith(suffix = ".fx.json", path)) }

    /// dir 配下の .json ファイル全部 (prune 走査・dir 相対・ソート済み)。
    pub def listAllJson(dir: String): List[String] \ IO =
        walkJson(relDir -> childrenOf(dir, relDir), "") |> List.sort

    /// relDir ("" = プロジェクト直下) から下りながら .json ファイルの相対パスを集める。
    /// 除外ディレクトリには最初から降りない。
    // WhyNot: 「全部集めてから除外パスを捨てる」フィルタにしない — build/ は数十万ファイルに
    // 膨れることがあり、歩くだけで一覧の応答が数十秒かかるため。
    pub def walkJson(listChildren: String -> List[DirEntry] \ ef, relDir: String): List[String] \ ef =
        listChildren(relDir) |> List.flatMap(entry -> {
            let path = if (relDir == "") entry#name else "${relDir}/${entry#name}";
            if (entry#isDir) {
                if (Set.memberOf(entry#name, excludedDirs())) Nil else walkJson(listChildren, path)
            }
            else if (String.endsWith(suffix = ".json", entry#name)) path :: Nil
            else Nil
        })

    /// dir/relDir の中身を列挙する。読めないディレクトリは空扱い。
    def childrenOf(dir: String, relDir: String): List[DirEntry] \ IO =
        let absPath = if (relDir == "") dir else "${dir}/${relDir}";
        let entries = new JFile(absPath).listFiles();
        if (Object.isNull(entries)) Nil
        else Array.toList(entries)
            |> List.map(file -> ({name = file.getName(), isDir = file.isDirectory()}: DirEntry))

    /// パスの最後の要素 (ファイル名)。
    def baseName(path: String): String =
        String.splitOn(substr = "/", path) |> List.last |> Option.getWithDefault(path)

    // ── ディスク変更の見張り (/changes) ───────────────────

    /// /changes で mtime を報告する対象を選ぶ。all は prune 走査で見つかった .json 全部、
    /// palettes は ui 側の "paletteFile" 参照から逆引きした外部パレット。
    /// 対象 = 編集対象 (ui / hitbox / fx / palette) + プレビュー設定 (*.preview.json) + project.json。
    // WhyNot: all をそのまま報告しない — ゲームプロジェクトにはエディタと無関係な
    // .json (レベルデータ等) が大量にあり得て、応答が毎回無駄に太るため。
    pub def changeTargets(palettes: List[String], all: List[String]): List[String] =
        let picked = all |> List.filter(path ->
            String.endsWith(suffix = ".ui.json", path)
            or baseName(path) == "hitbox.json"
            or String.endsWith(suffix = ".fx.json", path)
            or String.endsWith(suffix = ".preview.json", path)
            or path == "project.json");
        // palette は all との突き合わせで実在確認を兼ねる (走査に無い参照先は報告しない)
        (picked ::: List.filter(path -> List.memberOf(path, all), palettes))
            |> List.distinct
            |> List.sort

    /// (パス, mtime) の一覧全体から決まる集計値。ファイルの増減でも、どれか 1 つの
    /// mtime 変化でも必ず別の値になる。エディタ画面はこれの変化だけ見れば
    /// 「何かが変わった」と分かる (どれが変わったかは個別の mtime で判定する)。
    pub def changeToken(entries: List[(String, Int64)]): String =
        let mix = entries |> List.foldLeft((acc, entry) -> {
            let (path, mtime) = entry;
            acc * 1000003i64 + Int32.toInt64(Hash.hash(path)) + mtime
        }, 0i64);
        "${List.length(entries)}-${mix}"

    /// dir 相対パスたちの mtime (ミリ秒)。走査と読みの合間に消えたファイルは
    /// (mtime 0 で報告せず) 一覧から落とす。
    pub def mtimesOf(dir: String, paths: List[String]): List[(String, Int64)] \ IO =
        paths |> List.filterMap(path -> {
            let mtime = new JFile("${dir}/${path}").lastModified();
            if (mtime == 0i64) None else Some((path, mtime))
        })

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
