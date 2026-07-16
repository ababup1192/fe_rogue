// Projects — 「いまどのプロジェクトを編集しているか」を覚える器と、切替候補の探索・
// 最近開いた履歴。サーバはプロジェクト未選択のまま起動でき、GET /projects で候補を
// 見せて POST /project で切り替える。履歴は ~/.flix_ge_editor.json に残す。

mod Projects {
    import java.lang.System
    import java.io.{File => JFile}
    import java.util.concurrent.{ConcurrentHashMap => JMap}

    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JString}

    /// 選択中プロジェクトの入れ物 (キーは "dir" の 1 つだけ)。
    // WhyNot: Ref を使わない — Ref は region の寿命に縛られ、リクエストをまたいで生きる
    // 可変の入れ物にならないので、Caches と同じく Java の Map を器として借りる。
    pub type alias Selection = JMap[String, String]

    /// 器を作る。initial (起動時の EDITOR_DIR) があれば選択済みで始める。
    pub def makeSelection(initial: Option[String]): Selection \ IO =
        let selection: Selection = new JMap();
        match initial {
            case None      => selection
            case Some(dir) => { discard selection.put("dir", dir); selection }
        }

    /// いま選択中のプロジェクト。未選択なら None。
    pub def currentDir(selection: Selection): Option[String] \ IO =
        let value: String = selection.get("dir");
        if (Object.isNull(value)) None else Some(value)

    /// 選択を dir へ切り替える。
    pub def switchTo(dir: String, selection: Selection): Unit \ IO =
        discard selection.put("dir", dir)

    // ════════════════════════════════════════════════════════
    // 切替候補の探索
    // ════════════════════════════════════════════════════════

    /// プロジェクト探索の起点。EDITOR_SCAN_ROOTS (コロン区切り)、未設定なら $HOME/Desktop。
    pub def scanRootsFromEnv(): List[String] \ IO =
        let value = System.getenv("EDITOR_SCAN_ROOTS");
        if (Object.isNull(value) or value == "")
            "${System.getProperty("user.home")}/Desktop" :: Nil
        else
            splitRoots(value)

    /// コロン区切りの起点指定を分解する (空要素は捨てる)。
    pub def splitRoots(text: String): List[String] =
        String.splitOn(substr = ":", text) |> List.filter(root -> root != "")

    /// 各起点の深さ 2 まで (起点/* と 起点/*/*) で project.json を持つディレクトリを列挙する。
    pub def findProjects(roots: List[String]): List[String] \ IO =
        roots |> List.flatMap(root -> findUnder(depth = 2, root)) |> List.distinct |> List.sort

    /// dir 直下から depth 段ぶん下りながら project.json 持ちディレクトリを集める。
    def findUnder(depth: {depth = Int32}, dir: String): List[String] \ IO =
        if (depth#depth <= 0) Nil
        else subDirs(dir) |> List.flatMap(sub ->
            (if (hasProjectJson(sub)) sub :: Nil else Nil)
                ::: findUnder(depth = depth#depth - 1, sub))

    /// dir 直下のディレクトリ。隠しディレクトリと生成物・依存 (build 等) は探索しない。
    def subDirs(dir: String): List[String] \ IO =
        let entries = new JFile(dir).listFiles();
        if (Object.isNull(entries)) Nil
        else Array.toList(entries) |> List.filterMap(file ->
            if (file.isDirectory()
                and not String.startsWith(prefix = ".", file.getName())
                and not Set.memberOf(file.getName(), FileIndex.excludedDirs()))
                Some("${dir}/${file.getName()}")
            else None)

    /// dir が project.json を持つか (= エディタで開けるプロジェクトか)。
    pub def hasProjectJson(dir: String): Bool \ IO =
        new JFile("${dir}/project.json").isFile()

    /// 一覧に見せるプロジェクトの題名。project.json が読めなければディレクトリ名で代用。
    pub def titleOf(dir: String): String \ IO =
        (run { ProjectLoader.loadProject(dir) } with Fs.FileRead.runWithIO)
            |> Result.map(loadedProject -> loadedProject#config#title)
            |> Result.getWithDefault(baseNameOf(dir))

    /// パスの最後の要素 (ディレクトリ名)。
    pub def baseNameOf(dir: String): String =
        String.splitOn(substr = "/", dir)
            |> List.filter(segment -> segment != "")
            |> List.last
            |> Option.getWithDefault(dir)

    // ════════════════════════════════════════════════════════
    // 最近開いた履歴 (~/.flix_ge_editor.json)
    // ════════════════════════════════════════════════════════

    /// 履歴で覚える最大件数。
    def recentLimit(): Int32 = 10

    /// 履歴ファイルの置き場所。
    def recentFile(): String \ IO =
        "${System.getProperty("user.home")}/.flix_ge_editor.json"

    /// dir を履歴の先頭へ積む。既にあれば重複させず先頭へ移し、最新 10 件で打ち切る (純関数)。
    pub def pushRecent(dir: String, recent: List[String]): List[String] =
        (dir :: List.filter(other -> other != dir, recent)) |> List.take(recentLimit())

    /// 最近開いた順の履歴を読む。ファイルが無い・壊れているは空扱い (履歴が無くても本体は困らない)。
    pub def loadRecent(): List[String] \ IO =
        let readResult = run { Fs.ReadFile.read(recentFile()) }
            with Fs.ReadFile.runWithFileRead
            with Fs.FileRead.runWithIO;
        readResult
            |> Result.toOption
            |> Option.flatMap(text -> JsonCompat.parse(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.flatMap(obj -> Map.get("recent", obj))
            |> Option.flatMap(json -> recentFromJson(json))
            |> Option.getWithDefault(Nil)
            |> List.take(recentLimit())

    /// ["dir", ...] を読む。文字列でない要素は捨てる (壊れた 1 要素で履歴全部を失わない)。
    def recentFromJson(json: Json): Option[List[String]] =
        match json {
            case JArray(entries) => Some(entries |> Vector.toList |> List.filterMap(JsonCodec.expectString))
            case _               => None
        }

    /// 履歴を書き戻す。書けなくてもサーバは続行する (履歴は補助情報で、本体の切替は済んでいる)。
    pub def saveRecent(recent: List[String]): Unit \ IO =
        let json = JObject(Map#{"recent" => JArray(recent |> List.map(dir -> JString(dir)) |> List.toVector)});
        let writeResult = run { Fs.WriteFile.write(str = Util.Json.toPrettyString(2, json) + "\n", recentFile()) }
            with Fs.WriteFile.runWithFileWrite
            with Fs.FileWrite.runWithIO;
        writeResult |> Result.map(_ -> ()) |> Result.getWithDefault(())
}
