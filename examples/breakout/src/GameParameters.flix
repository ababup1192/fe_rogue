// GameParameters — Game の縁が読み Step へ値で渡す調整パラメータの番地。遊びながら回す:
// assets/parameters.json を編集して F1 を押すと、その場で効きが変わる。
//
// 運用: 遊びながら json の値を調整 → 決まったらコード内の既定値（Bounce / Field の定数）へ昇格する。
// 既定値はあくまでコードの定数が正で、json は一時的な上書きにすぎない: ファイルが無い・JSON が
// 壊れている・キーが足りない、のどれでも既定値で動く（fail-open）。ギャラリーと Replay は
// 常に既定値を使うので、テストの pin と GIF の決定論はパラメータ弄りの影響を受けない。
// ファイル読みの effect（Fs.FileRead）は loop の縁だけが使い、update は Params を値として受け取る。

mod GameParameters {
    import java.math.BigDecimal
    use Util.Json.Json
    use Util.Json.Json.{JObject, JNumber}

    /// 調整できるパラメータ一式。それぞれの意味は既定値を持つ定数（Bounce / Field）の doc を参照。
    pub type alias Params = {
        maxBounceAngle = Float64,    // パドル反射の最大角（ラジアン・垂直からの傾き）
        speedGainPerHit = Float64,   // パドルヒット毎の加速倍率
        edgeSpeedBonus = Float64,    // 端当ての追加加速（|offset| 比例の最大値）
        maxSpeedFactor = Float64,    // 速さの上限（基準速度に対する倍率）
        paddleSpeed = Float64,       // パドルの移動速度（px/秒）
        trailLength = Int32          // ボール残像リングの長さ（フレーム数）
    }

    /// コード内定数そのままの既定パラメータ。playingWorld・Replay・ギャラリーはこれ, F1 だけが差し替える。
    pub def defaults(): Params = {
        maxBounceAngle = Bounce.maxBounceAngle(),
        speedGainPerHit = Bounce.speedGainPerHit(),
        edgeSpeedBonus = Bounce.edgeSpeedBonus(),
        maxSpeedFactor = Bounce.maxSpeedFactor(),
        paddleSpeed = Field.paddleSpeed(),
        trailLength = Field.trailLength() }

    /// パラメータファイルの置き場所。
    pub def path(): String = "assets/parameters.json"

    /// F1 リロードの入口: parameters.json が読めて JSON として立っていれば、そのキーで既定値を
    /// 上書きしたパラメータを返す。読めなければ既定値（fail-open）。
    pub def load(): Params \ Fs.FileRead =
        let readResult = run { Fs.ReadFile.read(path()) } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(fromJson)
            |> Option.getWithDefault(defaults())

    /// JSON テキストからパラメータを組む純粋な芯（テストはここを直接叩く）。
    /// ファイル全体が JSON でなければ None。キー単位では、無い・数値でないキーは既定値のまま。
    pub def fromJson(text: String): Option[Params] =
        JsonCompat.parse(String.trim(text)) |> Option.map(fromParsed)

    def fromParsed(json: Json): Params = match json {
        case JObject(map) =>
            let base = defaults();
            { maxBounceAngle = num("maxBounceAngle", base#maxBounceAngle, map),
              speedGainPerHit = num("speedGainPerHit", base#speedGainPerHit, map),
              edgeSpeedBonus = num("edgeSpeedBonus", base#edgeSpeedBonus, map),
              maxSpeedFactor = num("maxSpeedFactor", base#maxSpeedFactor, map),
              paddleSpeed = num("paddleSpeed", base#paddleSpeed, map),
              trailLength = int("trailLength", base#trailLength, map) }
        case _ => defaults()
    }

    /// key の数値を読む。無い・数値でないときは fallback。
    def num(key: String, fallback: Float64, map: Map[String, Json]): Float64 =
        match Map.get(key, map) {
            case Some(JNumber(bd)) => bd.doubleValue()
            case _                 => fallback
        }

    /// key の整数を読む（数値の小数部は捨てる）。無い・数値でないときは fallback。
    def int(key: String, fallback: Int32, map: Map[String, Json]): Int32 =
        match Map.get(key, map) {
            case Some(JNumber(bd)) => Float64.floor(bd.doubleValue()) |> Float64.tryToInt32 |> Option.getWithDefault(fallback)
            case _                 => fallback
        }
}
