// UiBinding — 宣言的テキストバインディングの適用（完全純粋）
//
// ui.json の `bind` 宣言で各 text entity に付いた bind key（bindings store）を、実行時に値へ
// 解決して text へ流し込む汎用機構（Unity UXML のデータバインディング相当）。呼び側は
// 「bind key → 表示文字列」の resolver を渡すだけでよく、どの entity がどの key を持つかは
// ui.json 側の宣言に閉じる。resolver が None を返した key は現在の text を保つ。

mod UiBinding {

    /// bindings store を走査し、resolve が Some を返した entity の text を差し替える。
    /// resolve が None の key、text コンポーネントを持たない entity は据え置く。
    pub def apply(resolve: String -> Option[String], ui: UiStore.UiWorld): UiStore.UiWorld =
        ui#bindings |> Map.foldLeftWithKey((acc, id, key) ->
            match resolve(key) {
                case None       => acc
                case Some(text) => setTextById(id, text, acc)
            }, ui)

    /// entity id の text コンポーネント文字列を差し替える。text を持たなければ no-op。
    /// bindings は entity id をキーに持つため、名前パス経由でなく id で直接引く。
    def setTextById(id: EntityId, text: String, ui: UiStore.UiWorld): UiStore.UiWorld =
        match Map.get(id, ui#texts) {
            case None       => ui
            case Some(comp) => {texts = Map.insert(id, {text = text | comp}, ui#texts) | ui}
        }
}
