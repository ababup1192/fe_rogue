// RulesDoc — race.rules.json（手触りと収支の数値）の宣言ドキュメント層。
// Doc は「調整したい数値の初期値の宣言」まで。走る・曲がる・抜く・周回するの規則そのものは
// コード（World）側にある。ここに if 文を書き始めたら Doc の境界を越えている合図。
// fail-open — 読めない・壊れているときは defaults() へ倒し、ゲームは必ず起動する。
mod RulesDoc {
    use Util.Json.Json

    /// 手触りと収支の数値。いじると何が変わるかは各フィールドのコメントのとおり。
    ///   forwardSpeed  … 前へ進む速さ（コースが下へ流れる速さ・px/秒）。大きいほど疾走感。
    ///   steerSpeed    … ←→ でハンドルを切ったときの横移動の速さ（px/秒）。大きいほど機敏。
    ///   offRoadSlow   … 道の外（草）に出たときに前進速度へ掛かる係数（0..1）。小さいほど強く減速。
    ///   rivalSpeedA   … ライバル A の前進速さ（px/秒）。自機の forwardSpeed より速いと追われる。
    ///   rivalSpeedB   … ライバル B の前進速さ（px/秒）。
    ///   lapLength     … 1 周の距離（px）。この距離ぶん前進すると lap が 1 増える。
    ///   totalLaps     … ゴールに必要な周回数。この周回に達したら WIN。
    ///   scorePerPass  … ライバルを 1 台抜くたびに入る得点。
    ///   finishBonus   … ゴール（WIN）到達時の追加得点。
    pub type alias Doc = {
        version = Int32,
        forwardSpeed = Float64,
        steerSpeed = Float64,
        offRoadSlow = Float64,
        rivalSpeedA = Float64,
        rivalSpeedB = Float64,
        lapLength = Float64,
        totalLaps = Int32,
        scorePerPass = Int32,
        finishBonus = Int32
    }

    pub def path(): String = "assets/race.rules.json"

    /// コード側の既定値（assets/race.rules.json と同じ値から出発する）。
    pub def defaults(): Doc =
        { version = 1,
          forwardSpeed = 120.0,
          steerSpeed = 130.0,
          offRoadSlow = 0.45,
          rivalSpeedA = 96.0,
          rivalSpeedB = 108.0,
          lapLength = 900.0,
          totalLaps = 3,
          scorePerPass = 300,
          finishBonus = 1000 }

    /// テキストから Doc へ（fail-open）。JSON でない・形が違うフィールドは既定へ倒す。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.decodeObject(fromRoot, text)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          forwardSpeed = JsonCodec.floatOr("forwardSpeed", d#forwardSpeed, root),
          steerSpeed = JsonCodec.floatOr("steerSpeed", d#steerSpeed, root),
          offRoadSlow = JsonCodec.floatOr("offRoadSlow", d#offRoadSlow, root),
          rivalSpeedA = JsonCodec.floatOr("rivalSpeedA", d#rivalSpeedA, root),
          rivalSpeedB = JsonCodec.floatOr("rivalSpeedB", d#rivalSpeedB, root),
          lapLength = JsonCodec.floatOr("lapLength", d#lapLength, root),
          totalLaps = JsonCodec.intOr("totalLaps", d#totalLaps, root),
          scorePerPass = JsonCodec.intOr("scorePerPass", d#scorePerPass, root),
          finishBonus = JsonCodec.intOr("finishBonus", d#finishBonus, root) }

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        JsonCompat.loadOr(fromJson, defaults(), p)
}
