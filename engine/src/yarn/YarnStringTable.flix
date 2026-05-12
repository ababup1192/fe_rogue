/// 文字列テーブル（lineRef → 表示テキスト）から行を引き、
/// `{0}` `{1}` ... の置換マーカーを解決する。
///
/// 純粋関数のみ。エンジン依存なし。
mod Yarn.StringTable {
    use Yarn.Types.LineRef

    /// `lineRef` から行テキストを取り出し、`{i}` を `substitutions[i]` に置き換えて返す。
    ///
    /// - 行が見つからない場合は `Err` で原因を返す
    /// - `substitutionCount` と実際の `{i}` 出現数の整合は確認しない
    ///   （余分は無視、足りない `{i}` はそのまま残る）
    pub def resolve(lineRef: LineRef,
                     substitutions: List[String],
                     table: Map[LineRef, String]):
                     Result[String, String] =
        match Map.get(lineRef, table) {
            case None      => Err("line not found: ${lineRef}")
            case Some(raw) => Ok(applySubstitutions(raw, substitutions))
        }

    /// `{0}` `{1}` ... を順に substitutions の値で置き換える。
    /// substitutions の長さだけマーカーを置換する（足りないインデックスは残す）。
    pub def applySubstitutions(raw: String, substitutions: List[String]): String =
        let indexed = List.zip(List.range(0, List.length(substitutions)), substitutions);
        List.foldLeft((acc, indexedValue) -> {
            let (index, value) = indexedValue;
            String.replace(src = "{${index}}", dst = value, acc)
        }, raw, indexed)
}
