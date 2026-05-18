// ResourceWriter — 編集 JSON をファイルへ書き戻す
//
// Persistence.save は `Saveable[a]` 制約付きで、IDE は data の Flix 型を知らないため
// 直接使えない。ここでは Json.JsonElement を pretty-print して Fs.WriteFile で書く。
//
// 保存前の検証:
//   - JSON 整形 round-trip (toPrettyString → parse) で「再パース可能」を保証
//   - Resource.checkConsistency は呼び出し側 (JavaFXIdeUI の Save ハンドラ) で行う

mod ResourceWriter {

    /// `path` に JSON を整形して書き出す。書き戻し直前に再パース可能性を検証する。
    /// 成功時は Ok(())、失敗時は Err(message)。
    pub def writeJson(path: String, json: Json.JsonElement): Result[String, Unit] \ Fs.FileWrite =
        let pretty = Json.Write.toPrettyString(2, json);
        // round-trip 検証: 整形後の文字列を再 parse して、整形前と一致するかを確認
        match Json.Parse.parse(pretty) {
            case None       => Err("internal error: pretty-printed JSON cannot be re-parsed")
            case Some(rt)   =>
                if (rt != json) Err("internal error: round-trip mismatch")
                else writeRaw(path, pretty)
        }

    def writeRaw(path: String, content: String): Result[String, Unit] \ Fs.FileWrite =
        let result = run {
            Fs.WriteFile.write({str = content}, path)
        } with Fs.WriteFile.runWithFileWrite;
        match result {
            case Ok(_)      => Ok(())
            case Err(error) => Err("write failed: ${error}")
        }
}
