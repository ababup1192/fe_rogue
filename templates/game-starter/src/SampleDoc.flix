// SampleDoc — sample.kind.json（手触りの数値）の宣言ドキュメント層。
// Doc は「初期値の宣言」まで: 規則（動き方）はコード（World）側。
// fail-open — 読めない・壊れているときは defaults() へ倒し、ゲームは必ず起動する。
mod SampleDoc {
    use Util.Json.Json

    pub type alias Doc = {
        version = Int32,
        speed = Float64
    }

    pub def path(): String = "assets/sample.kind.json"

    /// コード側の既定値（assets/sample.kind.json と同じ値から出発する）。
    pub def defaults(): Doc =
        { version = 1, speed = 120.0 }

    /// テキストから Doc へ（fail-open）。JSON でない・形が違うフィールドは既定へ倒す。
    pub def fromJson(text: String): Option[Doc] =
        DocJson.decodeObject(fromRoot, text)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          speed = JsonCodec.floatOr("speed", d#speed, root) }

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        DocJson.loadOr(fromJson, defaults(), p)
}
