// ResourceDiscovery — `<projectRoot>/resources/*.json` を 1 階層走査して
// サイドカー `<name>.schema.json` を持つ data ファイルを Resource として列挙する。
//
// 検出ルール:
//   - "resources/*.json" を glob (1 階層のみ、再帰しない)
//   - "*.schema.json" で終わるパスは schema 候補
//   - それ以外の "*.json" は data 候補。対応する "<name>.schema.json" が同セットにあれば
//     Resource として採用
//
// プロジェクトルートに resources/ が無い、または対応 schema が無い data ファイルは
// 単にリストから外す (エラー扱いはしない)。

mod ResourceDiscovery {

    /// IDE が扱う 1 つの Resource。dataPath / schemaPath はどちらも絶対パス
    /// (Fs.Glob.glob が絶対パスで返す前提)。displayName は basename のみ
    /// (例: "units.json")。Resource 一覧でユーザに見せる短い名前。
    pub type alias ResourceEntry = {
        dataPath    = String,
        schemaPath  = String,
        displayName = String
    }

    /// projectRoot 配下の resources/ を走査して ResourceEntry のリストを返す。
    /// 走査は 1 階層 (再帰なし)。schema ペアを持たない data は除外する。
    pub def discover(projectRoot: String): List[ResourceEntry] \ Fs.Glob =
        let allJson = Fs.Glob.glob(projectRoot, "resources/*.json")
            |> Result.getWithDefault(Nil);
        let schemaSet = allJson
            |> List.filter(p -> String.endsWith({suffix = ".schema.json"}, p))
            |> List.toSet;
        allJson
            |> List.filter(p -> not String.endsWith({suffix = ".schema.json"}, p))
            |> List.filterMap(dataPath ->
                // ".json" (5 文字) を剥がして ".schema.json" に置き換える
                let stem = dataPath.substring(0, String.length(dataPath) - 5);
                let expectedSchemaPath = stem + ".schema.json";
                if (Set.memberOf(expectedSchemaPath, schemaSet))
                    Some({
                        dataPath    = dataPath,
                        schemaPath  = expectedSchemaPath,
                        displayName = basename(dataPath)
                    })
                else
                    None
            )

    /// パスの末尾のスラッシュ後 1 区間を返す。"/a/b/c.json" → "c.json"。
    /// 区切り文字が無ければ入力をそのまま返す。
    def basename(path: String): String =
        basenameRec(path, String.length(path) - 1)

    def basenameRec(path: String, idx: Int32): String =
        if (idx < 0) path
        else if (String.charAt(idx, path) == '/') path.substring(idx + 1, String.length(path))
        else basenameRec(path, idx - 1)
}
