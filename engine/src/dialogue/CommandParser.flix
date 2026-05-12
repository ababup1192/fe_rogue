/// Yarn の `<<command args>>` 文字列を「コマンド名」と「引数列」に分解する純粋関数。
///
/// VM の `WaitingCommand(text)` で受け取る `text` には `<<` `>>` は含まれず、中身だけが
/// 入っている（例: "wait 0.5"、"bgm play title loop"）。これを空白区切りで切り、
/// 先頭をコマンド名、残りを引数列として返す。
///
/// クォート文字列（`"..."` 内に空白を含む）は当面サポートしない（YAGNI）。必要になった
/// ときに本モジュールを拡張する。
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
