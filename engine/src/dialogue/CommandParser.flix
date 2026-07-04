/// Yarn の `<<command args>>` の中身（`<<` `>>` を除いた文字列）を「コマンド名」と
/// 「引数列」に分解する純粋関数。
/// コマンド解釈側が名前と引数の切り出しを毎回書かずに済む。
/// 利用例: "bgm play title loop" を ("bgm", ["play","title","loop"]) にする。
/// 注意: クォート文字列（`"..."` 内の空白）は扱わない。必要になったら拡張する。
mod Dialogue.CommandParser {

    /// 連続する空白を区切り文字として分解し、先頭トークンをコマンド名、残りを引数列に分ける。
    /// 空文字や空白のみのときは `("", Nil)` を返す。
    ///
    /// 例:
    ///   - "wait 0.5"            → ("wait", "0.5" :: Nil)
    ///   - "bgm play title loop" → ("bgm", "play" :: "title" :: "loop" :: Nil)
    ///   - "save"                → ("save", Nil)
    ///   - ""                    → ("", Nil)
    pub def parse(line: String): (String, List[String]) =
        let tokens = String.splitOn(substr = " ", line)
            |> List.map(String.trim)
            |> List.filter(token -> not String.isEmpty(token));
        match tokens {
            case Nil          => ("", Nil)
            case head :: rest => (head, rest)
        }
}
