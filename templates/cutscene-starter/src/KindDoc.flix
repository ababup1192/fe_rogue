// KindDoc — rpg.kind.json（手触りの数値）の宣言ドキュメント層。
// Doc は「初期値の宣言」まで: 規則（歩き方・会話の進め方）はコード（World）側。
// fail-open — 読めない・壊れているときは defaults() へ倒し、ゲームは必ず起動する。
mod KindDoc {
    use Util.Json.Json

    /// 手触りの数値。walk = 歩く速さ（1 秒あたりのマス数）、
    /// wisp = 火の玉（敵）が詰める速さ（1 秒あたりのマス数。主人公よりやや遅くして
    /// 「走れば振り切れる」の手触りにする）、
    /// cps = ふきだしの文字送りの速さ（1 秒あたりの文字数）、
    /// bubbleSize / bubbleGap / bubblePad / bubbleWidth = ふきだしの文字の大きさ・行間・
    /// 内側の余白・本文の最大幅（すべて px）。
    pub type alias Doc = {
        version = Int32,
        walk = Float64,
        wisp = Float64,
        cps = Float64,
        bubbleSize = Float64,
        bubbleGap = Float64,
        bubblePad = Float64,
        bubbleWidth = Float64
    }

    pub def path(): String = "assets/rpg.kind.json"

    /// コード側の既定値（assets/rpg.kind.json と同じ値から出発する）。
    pub def defaults(): Doc =
        { version = 1, walk = 6.0, wisp = 3.5, cps = 20.0,
          bubbleSize = 10.0, bubbleGap = 3.0, bubblePad = 6.0, bubbleWidth = 200.0 }

    /// テキストから Doc へ（fail-open）。JSON でない・形が違うフィールドは既定へ倒す。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          walk = JsonCodec.floatOr("walk", d#walk, root),
          wisp = JsonCodec.floatOr("wisp", d#wisp, root),
          cps = JsonCodec.floatOr("cps", d#cps, root),
          bubbleSize = JsonCodec.floatOr("bubbleSize", d#bubbleSize, root),
          bubbleGap = JsonCodec.floatOr("bubbleGap", d#bubbleGap, root),
          bubblePad = JsonCodec.floatOr("bubblePad", d#bubblePad, root),
          bubbleWidth = JsonCodec.floatOr("bubbleWidth", d#bubbleWidth, root) }

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        let readResult = run { Fs.ReadFile.read(p) } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(fromJson)
            |> Option.getWithDefault(defaults())
}
