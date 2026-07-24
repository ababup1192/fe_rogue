// WavesDoc — shooter.waves.json（敵の波の配置）の宣言ドキュメント層。
// 1 波 = 1 つの文字格子（rows）。行の文字が「そのマスに敵がいるか」を表す:
//   '.'（と空白・知らない文字）= いない、それ以外（'X' など）= 敵 1 体。
// rpg のマップ rows と同じ発想 — 格子を書き換えれば別の攻めになる。
// 波を降りてこさせる・当てる・全滅を判定する規則はコード（World）側。
// fail-open — 読めない・壊れているときは defaults() へ倒し、ゲームは必ず起動する。
mod WavesDoc {
    use Util.Json.Json

    /// 波の並び。waves = 波の列（先頭から順に出てくる）。
    /// 各波は文字格子（rows）。cols は「一番長い行の長さ」を敵の横並び数として使う。
    pub type alias Doc = {
        version = Int32,
        waves = List[List[String]]
    }

    pub def path(): String = "assets/shooter.waves.json"

    /// 「敵がいるマス」を表す文字か（'.'・空白・知らない文字は空きに倒す — fail-open）。
    /// ここだけが「格子の文字 → 敵の有無」を決める唯一の入口。
    pub def isEnemy(ch: Char): Bool =
        not (ch == '.' or ch == ' ')

    /// コード側の既定値。3 つの波で「読んで学べる」最小の攻め。
    /// 波が進むほど密度と幅が上がる（原始的な難度カーブ）。
    ///   波1: まばらな 1 行            波2: 2 行の隊列          波3: くさび形の 3 行
    pub def defaults(): Doc =
        { version = 1,
          waves =
              ( ".X.X.X.X."
             :: Nil )
           :: ( "XXXXXXXX"
             :: ".X.X.X.X"
             :: Nil )
           :: ( "...XX..."
             :: "..XXXX.."
             :: ".XXXXXX."
             :: Nil )
           :: Nil }

    /// 波の数。全滅させるべき波の総数。
    pub def waveCount(doc: Doc): Int32 =
        List.length(doc#waves)

    /// n 番目（0 始まり）の波の格子。範囲外は空リスト（fail-open）。
    pub def waveAt(n: Int32, doc: Doc): List[String] =
        List.nth(n, doc#waves) |> Option.getWithDefault(Nil)

    /// テキストから Doc へ（fail-open）。JSON でない・形が違うフィールドは既定へ倒す。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          waves = wavesOr(d#waves, "waves", root) }

    /// 「文字列の配列の配列」を読む。形が違う・要素に配列でないものが混じるときは既定へ倒す。
    def wavesOr(fallback: List[List[String]], key: String, obj: Map[String, Json]): List[List[String]] =
        Map.get(key, obj)
            |> Option.flatMap(JsonCodec.decodeList(json ->
                JsonCodec.decodeList(JsonCodec.expectString, json)))
            |> Option.getWithDefault(fallback)

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        let readResult = run { Fs.ReadFile.read(p) } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(fromJson)
            |> Option.getWithDefault(defaults())
}
