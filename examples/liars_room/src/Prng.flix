// Prng — 純粋・決定論的な splitmix64 乱数。
// 同じ seed からは常に同じ列が出るので、ステージ生成が再現可能になりテストで固定できる。
// 利用例: let (i, st1) = Prng.nextIntRange(lo = 0, hi = 7, st)
//
// 注意: splitmix64 は符号なし右シフトを要する。Flix の `>>>` は符号拡張なので使わず、
// stdlib の `Int64.logicalRightShift`（ゼロ埋め保証）を使う（fe_rogue の Prng と同じ判断）。
mod Prng {

    /// 乱数の状態（splitmix64 の 64bit カウンタを 1 つ包む）。
    pub enum State(Int64)

    /// 任意の Int64 を seed にして初期状態を作る。
    pub def seed(s: Int64): State = State.State(s)

    // splitmix64 の仕上げ混ぜ込み。定数は signed Int64 表現:
    //   0xBF58476D1CE4E5B9 = -4658895280553007687
    //   0x94D049BB133111EB = -7723592293110705685
    def mix(z0: Int64): Int64 =
        let z1 = Int64.bitwiseXor(z0, Int64.logicalRightShift(dist = 30, z0)) * -4658895280553007687i64;
        let z2 = Int64.bitwiseXor(z1, Int64.logicalRightShift(dist = 27, z1)) * -7723592293110705685i64;
        Int64.bitwiseXor(z2, Int64.logicalRightShift(dist = 31, z2))

    // 状態を 1 歩進め、混ぜ込み済みの 64bit 出力と次状態を返す。
    //   golden gamma 0x9E3779B97F4A7C15 = -7046029254386353131
    def next64(st: State): (Int64, State) =
        let State.State(s) = st;
        let s1 = s + -7046029254386353131i64;
        (mix(s1), State.State(s1))

    // [0,1) の一様乱数（上位 53bit を Float64 へ写す）。
    def nextUnit(st: State): (Float64, State) =
        let (z, st1) = next64(st);
        let top53 = Int64.logicalRightShift(dist = 11, z);
        (Int64.toFloat64(top53) / 9007199254740992.0, st1)

    /// [lo, hi) の一様な整数を 1 つ引く。空区間なら lo を返す。
    pub def nextIntRange(lo: {lo = Int32}, hi: {hi = Int32}, st: State): (Int32, State) =
        let (unit, st1) = nextUnit(st);
        let span = hi#hi - lo#lo;
        if (span <= 0)
            (lo#lo, st1)
        else
            (lo#lo + Float64.truncateToInt32(Float64.floor(unit * Int32.toFloat64(span))), st1)

    /// 五分五分の真偽を 1 つ引く。
    pub def nextBool(st: State): (Bool, State) =
        let (unit, st1) = nextUnit(st);
        (unit < 0.5, st1)

    /// リストから一様に 1 つ選ぶ（空リストなら None）。
    pub def pick(xs: List[a], st: State): (Option[a], State) =
        let (i, st1) = nextIntRange(lo = 0, hi = List.length(xs), st);
        (List.nth(i, xs), st1)
}
