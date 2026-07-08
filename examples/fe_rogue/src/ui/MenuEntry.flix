/// メニュー 1 行ぶんの項目データ。
/// text は表示テキスト、disabled は淡色・選択スキップ対象か、metadata は確定時に取り出す識別子。
/// 例: 「攻撃」項目に `Some("attack")` を持たせ、確定時に metadata で分岐する。
pub type alias ItemEntry = {
    text     = String,
    disabled = Bool,
    metadata = Option[String]
}
