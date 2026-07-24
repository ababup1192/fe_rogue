// RulesDoc — raise.rules.json（進行と収支の数値）の宣言ドキュメント層。
// Doc は「調整したい数値の初期値の宣言」まで。育てる・イベントを選ぶ・結末を決めるの
// 規則そのものはコード（World）側にある。ここに if 文を書き始めたら Doc の境界を越えている合図。
// fail-open — 読めない・壊れているときは defaults() へ倒し、ゲームは必ず起動する。
mod RulesDoc {
    use Util.Json.Json

    /// 進行と収支の数値。いじると何が変わるかは各フィールドのコメントのとおり。
    ///   dayCount    … 発表会までの日数。この日数ぶん行動を選ぶと結果になる。
    ///   eventChance … 行動のあとイベントが起きる確率（0〜1）。大きいほど波乱含み。
    ///   statCap     … 各パラメータの上限。これを超えて伸びない。
    ///   seed        … イベント抽選の決定的な乱数の種。同じ種なら同じ運びになる。
    pub type alias Doc = {
        version = Int32,
        dayCount = Int32,
        eventChance = Float64,
        statCap = Int32,
        seed = Int32
    }

    pub def path(): String = "assets/raise.rules.json"

    /// コード側の既定値（assets/raise.rules.json と同じ値から出発する）。
    pub def defaults(): Doc =
        { version = 1,
          dayCount = 6,
          eventChance = 0.35,
          statCap = 100,
          seed = 12345 }

    /// テキストから Doc へ（fail-open）。JSON でない・形が違うフィールドは既定へ倒す。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          dayCount = JsonCodec.intOr("dayCount", d#dayCount, root),
          eventChance = JsonCodec.floatOr("eventChance", d#eventChance, root),
          statCap = JsonCodec.intOr("statCap", d#statCap, root),
          seed = JsonCodec.intOr("seed", d#seed, root) }

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        let readResult = run { Fs.ReadFile.read(p) } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(fromJson)
            |> Option.getWithDefault(defaults())
}
