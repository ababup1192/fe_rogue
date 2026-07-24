// DocValue — 小さなゲームDocが共通して使う、安全な値読み込み。
mod DocValue {
    use Util.Json.Json

    /// 小数に許す範囲。書き損じた欄だけ既定値へ戻す。
    pub enum FloatRule {
        case Any
        case Positive
        case NonNegative
        case UnitInterval
    }

    /// 整数に許す範囲。
    pub enum IntRule {
        case Any
        case Positive
        case NonNegative
    }

    /// JSON文字列をオブジェクトとして読む。
    pub def root(text: String): Option[Map[String, Json]] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)

    /// 小数を読み、用途ごとの安全範囲に入らなければ既定値を返す。
    pub def float(key: String, fallback: Float64, rule: FloatRule,
                  rootObject: Map[String, Json]): Float64 =
        let value = JsonCodec.floatOr(key, fallback, rootObject);
        let valid = match rule {
            case FloatRule.Any => true
            case FloatRule.Positive => value > 0.0
            case FloatRule.NonNegative => value >= 0.0
            case FloatRule.UnitInterval => value >= 0.0 and value <= 1.0
        };
        if (valid) value else fallback

    /// 整数を読み、用途ごとの安全範囲に入らなければ既定値を返す。
    pub def int(key: String, fallback: Int32, rule: IntRule,
                rootObject: Map[String, Json]): Int32 =
        let value = JsonCodec.intOr(key, fallback, rootObject);
        let valid = match rule {
            case IntRule.Any => true
            case IntRule.Positive => value > 0
            case IntRule.NonNegative => value >= 0
        };
        if (valid) value else fallback

    /// 文字列は欠けた欄だけ既定値へ戻す。
    pub def text(key: String, fallback: String,
                 rootObject: Map[String, Json]): String =
        JsonCodec.stringOr(key, fallback, rootObject)

    /// ファイルが無い、または全体が壊れていても既定値でゲームを続ける。
    pub def load(filePath: String, fallback: a,
                 decode: String -> Option[a]): a \ Fs.FileRead =
        let readResult =
            run { Fs.ReadFile.read(filePath) } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(decode)
            |> Option.getWithDefault(fallback)
}
