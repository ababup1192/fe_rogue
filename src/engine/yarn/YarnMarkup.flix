/// Yarn ダイアログ行を RichTextLabel が解釈できる BBCode 文字列へ変換する層。
///
/// 現状は `Markup.BBCode.parse |> Markup.BBCode.render` の round-trip。
/// 文字列に `[color=red]` 等の BBCode タグが含まれていれば構造を保ったまま、
/// 含まれていなければ実質的に identity 変換となる。
///
/// 将来 Yarn 固有のマークアップ（`[wave]` `[shake]` 等）を対応させたいときは、
/// このモジュールでトークン列を巡回し、未対応タグを `[color=...]` などへ
/// 書き換える「変換」段を追加する想定。RichTextLabel が知っているタグだけが
/// この出口から出ていく状態を保つことで、表示層と markup 層の責務を分離する。
///
/// 注意 (typewriter との順序問題):
/// `Dialogue.formatBody` は `revealProgress` で文字を `String.take` する。
/// 先に `toBBCode` をかけてしまうと `[color=red]` のタグ文字数まで progress に
/// 算入され、表示が崩れる（途中で `[co` のようにタグが切れた表示になる）。
/// そのため呼び出しは **typewriter slice 後** （`Dialogue.formatBody` の戻り値に対して）
/// の位置で行うこと。実際に story.yarn にマークアップを書き始める時点で、
/// `Dialogue.formatBody` 側を「可視文字数ベースで slice する」関数に切り替える
/// 追加 PR が必要。
mod Yarn.Markup {

    /// Yarn テキストを BBCode 文字列へ変換する。
    pub def toBBCode(yarnText: String): String =
        Markup.BBCode.parse(yarnText)
            |> Markup.BBCode.render
}
