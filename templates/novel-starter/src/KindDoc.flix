// KindDoc — novel.kind.json（手触りの数値）の宣言ドキュメント層。
// Doc は「初期値の宣言」まで: 規則（文字送りの進め方・暗くする条件）はコード側。
// fail-open — 読めない・壊れているときは defaults() へ倒し、ゲームは必ず起動する。
mod KindDoc {
    use Util.Json.Json

    /// 手触りの数値。cps = 文字送りの速さ（1 秒あたりの文字数）、
    /// dim = 灯りが 1 つ消えるごとに部屋へ重なる暗さ（0〜1 の濃さ）。
    pub type alias Doc = {
        version = Int32,
        cps = Float64,
        dim = Float64
    }

    pub def path(): String = "assets/novel.kind.json"

    /// コード側の既定値（assets/novel.kind.json と同じ値から出発する）。
    pub def defaults(): Doc =
        { version = 1, cps = 30.0, dim = 0.22 }

    /// テキストから Doc へ（fail-open）。JSON でない・形が違うフィールドは既定へ倒す。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          cps = JsonCodec.floatOr("cps", d#cps, root),
          dim = JsonCodec.floatOr("dim", d#dim, root) }

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        let readResult = run { Fs.ReadFile.read(p) } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(fromJson)
            |> Option.getWithDefault(defaults())
}
