/// CatalogId — 実行時 resource からカタログ id を逆引きする共通ヘルパ。
///
/// 各カタログ（武器 / 杖 / 消費 / 指輪）は `CatalogContainer[t]`（id → resource の Map）を持つが、
/// resource 側に id フィールドを持たない。スナップショット保存では「resource → id」の逆引きが要る。
/// resource の表示名 `name` はカタログ内で一意（各カタログの `load` で `assertUniqueNames` 検査）なので、
/// それをキーに逆引きする。`name` の String 等値だけで照合するため、resource 全体の Eq には依存しない。
mod CatalogId {

    /// `targetName` を name に持つ entry の id を返す。`nameOf` は resource から表示名を取り出す射影。
    /// name はカタログ内で一意なので最初の一致を返せば十分。見つからなければ `None`。
    /// 呼ぶのはフロア進入 / 保存時のみで頻度が低いため、Map 全走査（n は数十）で問題ない。
    pub def idByName(nameOf: t -> String, targetName: String,
                      container: CatalogContainer[t]): Option[String] =
        CatalogContainer.entriesOf(container)
            |> Map.toList
            |> List.findMap(entry -> {
                let (id, resource) = entry;
                if (nameOf(resource) == targetName) Some(id) else None
            })

    /// カタログ内の name が一意であることを検査し、検査済みの container をそのまま返す
    /// （`load` で `X.X(requireUniqueNames(...))` と書いて結果を使える pass-through 形）。
    /// 重複があれば即 panic（将来の name typo / 重複を起動時に検出して `idByName` の一意逆引きを保証）。
    /// `label` は panic メッセージ用のカタログ名。
    pub def requireUniqueNames(label: String, nameOf: t -> String,
                                container: CatalogContainer[t]): CatalogContainer[t] =
        let names = CatalogContainer.entriesOf(container)
            |> Map.toList
            |> List.map(entry -> nameOf(snd(entry)));
        if (List.length(names) == Set.size(List.toSet(names))) container
        else bug!("${label}: カタログに name 重複があります（idByName が一意逆引きできません）")
}
