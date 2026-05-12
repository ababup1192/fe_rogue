/// 永続化（セーブ／ロード）のための汎用機構。
///
/// 「`Json.JsonElement` に双方向変換できるならディスクに書き出せる」という
/// 最小制約を `Saveable` trait として表現し、`Persistence.save` /
/// `Persistence.load` がその制約を持つ任意の型を受け取って I/O を行う。
///
/// Yarn 固有のセーブデータは `Game.SaveManager` 側で
/// `instance Saveable[SaveData]` を定義することで本機構に乗せる。
/// 別ジャンルのデータ（ハイスコア、設定、インベントリなど）も
/// 同じ手順で永続化できる。
///
/// 設計方針:
///   - I/O とエンコーディングを完全に分離する
///   - `Saveable` は実装側責任。trait に default は置かない
///   - 形式不一致は `None`／`Err(message)` で握り潰さず素直に伝える
pub trait Saveable[a] {

    /// 値を `Json.JsonElement` へ変換する。エンコードは全域関数を想定し
    /// 失敗を返さない（ドメイン上常に成功するため）。
    pub def toJson(value: a): Json.JsonElement

    /// `Json.JsonElement` から値を復元する。形式不一致は `None`。
    /// パース後のスキーマ検証もここで完結させる。
    pub def fromJson(element: Json.JsonElement): Option[a]
}

mod Persistence {

    /// `Saveable` を実装した値を `path` へ JSON で書き出す。
    /// 親ディレクトリは事前に作成されている前提
    /// （`Fs.WriteFile` は親ディレクトリを自動作成しない）。
    /// 失敗時は `Err(message)` を返す。
    pub def save(path: String, value: a): Result[String, Unit] \ Fs.FileWrite with Saveable[a] =
        let json = Saveable.toJson(value);
        let pretty = Json.Write.toPrettyString(2, json);
        let result = run {
            Fs.WriteFile.write({str = pretty}, path)
        } with Fs.WriteFile.runWithFileWrite;
        match result {
            case Ok(_)      => Ok(())
            case Err(error) => Err("save write failed: ${error}")
        }

    /// `Saveable` を実装した型を `path` から読み出す。
    /// ファイル不在・パース失敗・形式不一致は `None`。
    pub def load(path: String): Option[a] \ Fs.FileRead with Saveable[a] =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(Json.Parse.parse)
            |> Option.flatMap(Saveable.fromJson)
}
