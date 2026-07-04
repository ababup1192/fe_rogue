/// Yarn のダイアログ行を、表示層（RichTextLabel）が解釈できる BBCode 文字列へ変換する。
/// 表示層が知っているタグだけをこの出口から出すことで、markup と表示の責務を分けられる。
/// 現状は `Markup.BBCode.parse |> render` の round-trip で、`[color=red]` 等が
/// あれば構造を保ち、無ければ実質そのまま返す。
/// 利用例: typewriter で可視部分を切り出した後の文字列に `toBBCode` をかける。
/// 注意: 先に `toBBCode` をかけると `[color=red]` のタグ文字までが typewriter の
///       文字送りに数えられ、`[co` のように途中で切れて崩れる。必ず slice 後にかける。
mod Yarn.Markup {

    /// Yarn テキストを BBCode 文字列へ変換する。
    pub def toBBCode(yarnText: String): String =
        Markup.BBCode.parse(yarnText)
            |> Markup.BBCode.render
}
