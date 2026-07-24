// RulesDoc — shooter.rules.json（手触りと収支の数値）の宣言ドキュメント層。
// Doc は「調整したい数値の初期値の宣言」まで。撃つ・当たる・降りるの規則そのものは
// コード（World）側にある。ここに if 文を書き始めたら Doc の境界を越えている合図。
// fail-open — 読めない・壊れているときは defaults() へ倒し、ゲームは必ず起動する。
mod RulesDoc {
    use Util.Json.Json

    /// 手触りと収支の数値。いじると何が変わるかは各フィールドのコメントのとおり。
    ///   playerSpeed   … 自機の左右移動の速さ（px/秒）。大きいほど機敏。
    ///   bulletSpeed   … 弾が上へ飛ぶ速さ（px/秒）。大きいほど速い。
    ///   fireInterval  … 連射の間隔（秒）。小さいほど速く撃てる。押しっぱなしで撃つ。
    ///   enemyFallSpeed … 敵の波が降りてくる速さ（px/秒）。大きいほど攻めが激しい。
    ///   enemyStep     … 敵 1 体の見た目の 1 辺（px）。当たり判定の大きさも兼ねる。
    ///   scorePerKill  … 敵 1 体撃破の得点。
    ///   waveClearBonus … 波を 1 つ全滅させたときの追加得点。
    pub type alias Doc = {
        version = Int32,
        playerSpeed = Float64,
        bulletSpeed = Float64,
        fireInterval = Float64,
        enemyFallSpeed = Float64,
        enemyStep = Float64,
        scorePerKill = Int32,
        waveClearBonus = Int32
    }

    pub def path(): String = "assets/shooter.rules.json"

    /// コード側の既定値（assets/shooter.rules.json と同じ値から出発する）。
    pub def defaults(): Doc =
        { version = 1,
          playerSpeed = 150.0,
          bulletSpeed = 260.0,
          fireInterval = 0.28,
          enemyFallSpeed = 24.0,
          enemyStep = 18.0,
          scorePerKill = 100,
          waveClearBonus = 500 }

    /// テキストから Doc へ（fail-open）。JSON でない・形が違うフィールドは既定へ倒す。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          playerSpeed = JsonCodec.floatOr("playerSpeed", d#playerSpeed, root),
          bulletSpeed = JsonCodec.floatOr("bulletSpeed", d#bulletSpeed, root),
          fireInterval = JsonCodec.floatOr("fireInterval", d#fireInterval, root),
          enemyFallSpeed = JsonCodec.floatOr("enemyFallSpeed", d#enemyFallSpeed, root),
          enemyStep = JsonCodec.floatOr("enemyStep", d#enemyStep, root),
          scorePerKill = JsonCodec.intOr("scorePerKill", d#scorePerKill, root),
          waveClearBonus = JsonCodec.intOr("waveClearBonus", d#waveClearBonus, root) }

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        let readResult = run { Fs.ReadFile.read(p) } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(fromJson)
            |> Option.getWithDefault(defaults())
}
