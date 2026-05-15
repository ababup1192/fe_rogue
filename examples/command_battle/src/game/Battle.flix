/// 戦闘ロジック — DQ1 風ダメージ計算式の純粋関数群。
///
/// 純粋関数で構成して `Math.Random` を直接呼ばず、 乱数値 (0.0..1.0) は呼び出し側が引数で
/// 与える。 これにより:
///   - テストで決定的に検証できる (例: rng=0.5 で必ず同じ値)
///   - effect 制約が伝播しない (Battle 自身は effectful にならない)
///   - 後で `Math.Random.randomFloat64` 等で 1 度引いて渡せばゲーム側で乱数化できる
mod Battle {

    /// 通常攻撃ダメージ式 (DQ1 ベースだがばらつき重視で 四捨五入):
    ///   base   = (attack * 2 - defense) / 4
    ///   factor = 0.75 + rng * 0.25     (= 0.75 .. 1.0)
    ///   dmg    = max(1, round(base * factor))
    ///
    /// `Math.Random.randomFloat64` は半開区間 [0.0, 1.0) なので factor は 1.0 にギリギリ
    /// 到達せず、 単純 floor だと結果が一定値に張り付く（base=4 だと常に 3）。
    /// `+ 0.5` で四捨五入相当にして、 計算上の最大値もしっかり出るようにする。
    ///
    /// 守備力が極端に高くて base が 0 以下になっても、 最低 1 ダメージは入る（DQ1 仕様）。
    /// 引数名に `def` は Flix の予約語なので `defense` を使う。
    pub def computeAttack(attack: Int32, defense: Int32, rng: Float64): Int32 =
        let base = (attack * 2 - defense) / 4;
        let factor = 0.75 + clamp01(rng) * 0.25;
        let dmg = Float64.tryToInt32(Int32.toFloat64(base) * factor + 0.5)
                    |> Option.getWithDefault(0);
        Int32.max(1, dmg)

    /// じゅもんダメージ式（PR4 で利用）:
    ///   spell 固有の威力 range [minPower, maxPower] を rng で一様に振る。
    pub def computeSpell(minPower: Int32, maxPower: Int32, rng: Float64): Int32 =
        let span = maxPower - minPower;
        let extra = Float64.tryToInt32(clamp01(rng) * Int32.toFloat64(span))
                       |> Option.getWithDefault(0);
        Int32.max(0, minPower + extra)

    /// rng 値を 0.0..1.0 にクランプする（呼び出し側が範囲外の値を渡しても安全）
    def clamp01(rng: Float64): Float64 =
        Float64.max(0.0, Float64.min(1.0, rng))
}
