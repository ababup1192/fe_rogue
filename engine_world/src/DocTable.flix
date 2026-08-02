// DocTable — Doc(JSON) の台帳。1 行 = 「Studio の editor 宣言 id・監視パス・読み直し」。
// 同じ Doc 一覧を watchFile の配線・一括リロード(F1)・ActiveDocs の名乗りへ別々に
// 手写しすると、足し忘れで「保存しても効かない」「表示中の印が付かない」がすぐ起きる。
// ゲームは台帳 1 枚だけを書き、3 つの形はここが導出する。
mod DocTable {

    /// 台帳の 1 行。docId は project.json の editor 宣言 id(ActiveDocs のキー)。
    /// None の行は監視・リロードはするが Studio には名乗らない。
    pub type alias Entry[w] = { docId = Option[String], path = String,
                                reload = w -> w \ {Fs.FileRead} }

    /// App.game の reloads(保存即反映の watchFile)へそのまま渡す形。
    pub def reloads(rows: List[Entry[w]]): List[(String, w -> w \ {Fs.FileRead})] =
        rows |> List.map(r -> (r#path, r#reload))

    /// 台帳の並び順に全 Doc を読み直す(App.reloadOn の一括リロードへ渡す形)。
    /// 導出 Doc(他の Doc の値から焼き直す物)は、依存先より後ろの行に置くこと。
    pub def reloadAll(rows: List[Entry[w]], world: w): w \ Fs.FileRead =
        rows |> List.foldLeft((acc, r) -> { let f = r#reload; f(acc) }, world)

    /// ActiveDocs.step へ渡す形(id → パスの列)。同じ id の行は、行が離れていても
    /// 最初に現れた位置へ台帳の並びのまま束ねる。
    pub def activeDocs(rows: List[Entry[w]]): List[(String, List[String])] =
        let ids = rows |> List.filterMap(r -> r#docId) |> List.distinct;
        ids |> List.map(id -> (id, rows |> List.filterMap(r ->
            if (r#docId == Some(id)) Some(r#path) else None)))
}
