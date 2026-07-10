// GameParameters — Controls が App の reloadOn 経由で読み、Step へ値で渡す調整パラメータ。遊びながら回す:
// assets/parameters.json を編集して F1 を押すと、その場で手触りが変わる。
//
// 運用: 遊びながら json の値を調整 → 決まったらコード内の既定値（Jump の定数）へ昇格する。
// 既定値はあくまでコードの定数が正で、json は一時的な上書きにすぎない: ファイルが無い・JSON が
// 壊れている・キーが足りない、のどれでも既定値で動く（fail-open）。ギャラリーと Replay は
// 常に既定値を使うので、テストの pin と GIF の決定論はパラメータ弄りの影響を受けない。
// ファイル読みの effect（Fs.FileRead）は Controls.reloadParams だけが使い、update は Params を値として受け取る。

mod GameParameters {
    import java.math.BigDecimal
    use Util.Json.Json
    use Util.Json.Json.{JObject, JNumber}

    /// 調整できるパラメータ一式。それぞれの意味は既定値を持つ定数（Jump）の doc を参照。
    pub type alias Params = {
        jumpHeight = Float64,       // 頂点までの高さ px
        timeToApex = Float64,       // 頂点までの秒
        fallGravityMult = Float64,  // 下降の重力倍率
        apexBand = Float64,         // 頂点帯とみなす |vy| の上限 px/s
        apexGravityMult = Float64,  // 頂点帯の重力倍率
        cutMult = Float64,          // 離した瞬間の上昇速度倍率
        maxFallSpeed = Float64,     // 落下の終端速度 px/s
        maxRunSpeed = Float64,      // 走りの最高速 px/s
        groundAccel = Float64,      // 地上の加速 px/s²
        groundDecel = Float64,      // 地上の減速 px/s²
        airAccel = Float64,         // 空中の加速 px/s²
        airDecel = Float64,         // 空中の減速 px/s²
        coyoteTime = Float64,       // コヨーテタイム 秒
        bufferTime = Float64        // ジャンプバッファ 秒
    }

    /// コード内定数そのままの既定パラメータ。initialWorld・Replay・ギャラリーはこれ、F1 だけが差し替える。
    pub def defaults(): Params = {
        jumpHeight = Jump.jumpHeight(),
        timeToApex = Jump.timeToApex(),
        fallGravityMult = Jump.fallGravityMult(),
        apexBand = Jump.apexBand(),
        apexGravityMult = Jump.apexGravityMult(),
        cutMult = Jump.cutMult(),
        maxFallSpeed = Jump.maxFallSpeed(),
        maxRunSpeed = Jump.maxRunSpeed(),
        groundAccel = Jump.groundAccel(),
        groundDecel = Jump.groundDecel(),
        airAccel = Jump.airAccel(),
        airDecel = Jump.airDecel(),
        coyoteTime = Jump.coyoteTime(),
        bufferTime = Jump.bufferTime() }

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
            { jumpHeight = num("jumpHeight", base#jumpHeight, map),
              timeToApex = num("timeToApex", base#timeToApex, map),
              fallGravityMult = num("fallGravityMult", base#fallGravityMult, map),
              apexBand = num("apexBand", base#apexBand, map),
              apexGravityMult = num("apexGravityMult", base#apexGravityMult, map),
              cutMult = num("cutMult", base#cutMult, map),
              maxFallSpeed = num("maxFallSpeed", base#maxFallSpeed, map),
              maxRunSpeed = num("maxRunSpeed", base#maxRunSpeed, map),
              groundAccel = num("groundAccel", base#groundAccel, map),
              groundDecel = num("groundDecel", base#groundDecel, map),
              airAccel = num("airAccel", base#airAccel, map),
              airDecel = num("airDecel", base#airDecel, map),
              coyoteTime = num("coyoteTime", base#coyoteTime, map),
              bufferTime = num("bufferTime", base#bufferTime, map) }
        case _ => defaults()
    }

    /// key の数値を読む。無い・数値でないときは fallback。
    def num(key: String, fallback: Float64, map: Map[String, Json]): Float64 =
        match Map.get(key, map) {
            case Some(JNumber(bd)) => bd.doubleValue()
            case _                 => fallback
        }
}
