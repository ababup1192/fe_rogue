// ActiveDocs — 走っているゲームが「いま表示に使っている Doc(JSON)はどれか」を
// debug/active-docs.json に名乗る窓口。別プロセスのエディタ(Studio)がこれを読み、
// ファイル一覧の該当ファイルに「表示中」の印を付ける。
// キーは project.json の editor 宣言 id(theme / sprite / kind 等)と一致させる —
// エディタ側がグループの突き合わせに使うため。値はパス 1 本でも列でもよい。
// 全 Doc を常時名乗らないこと: いまの場面で絵や進行に効いている物だけを渡す
// (何でも「表示中」では印の意味が死ぬ)。
mod ActiveDocs {
    use Util.Json.Json.{JObject, JString, JArray}

    /// 書き出し先。debug/ は .gitignore 済みの作業用置き場。
    pub def path(): String = "debug/active-docs.json"

    /// entries(editor 宣言 id → 表示中パスの列)をエディタが読む形の JSON にする。
    /// 例: { "active": { "theme": "assets/x.theme.json", "ui": ["a.ui.json", "b.ui.json"] } }
    pub def json(entries: List[(String, List[String])]): String =
        entries
            |> List.map(entry -> { let (id, paths) = entry; (id, pathsJson(paths)) })
            |> List.toMap
            |> fields -> JObject(Map#{"active" => JObject(fields)})
            |> Util.Json.toPrettyString(2)

    /// パス 1 本は文字列、複数は列で書く(エディタはどちらも同じ形に読む)。
    def pathsJson(paths: List[String]): Util.Json.Json =
        match paths {
            case one :: Nil => JString(one)
            case many       => JArray(List.map(JString, many) |> List.toVector)
        }

    /// 毎フレームのシステムから呼ぶ。一覧が前回書いた物(World の activeDocsWritten)と
    /// 同じなら何もしない — 場面が変わった瞬間だけ実 IO が走る。書き込みの失敗は握り潰す
    /// (エディタ向けの補助情報で、書けない環境でもゲーム本体を止める理由にならない)。
    /// World には `activeDocsWritten = String` の欄を足し、出発点は "" にする。
    pub def step(entries: List[(String, List[String])],
                 w: { activeDocsWritten = String | r }): { activeDocsWritten = String | r } \ Fs.FileWrite =
        let current = json(entries);
        if (current == w#activeDocsWritten) w
        else {
            run {
                discard Fs.WriteFile.write({str = current}, path())
            } with Fs.WriteFile.runWithFileWrite;
            { activeDocsWritten = current | w }
        }
}
