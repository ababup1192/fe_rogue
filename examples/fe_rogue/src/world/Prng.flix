// Prng — combat ロールの oracle 用 PRNG。splitmix64 の本体は flix-random（Random）に委譲し、
// fe_rogue 側は「0..99 化の式」だけを持つ薄い層。
//
// 役割: golden-trace / roll-sequence 等価テストが「同じ seed → 同じ draw 列」を再現できる
// 値→値の PRNG。エフェクトを一切持たない（`World.rng` フィールドに dormant に載る）。
//
// IMPORTANT（live との関係）: live combat の数値はこの Prng を一切通らない。live な
// `World.RngDraw` ハンドラは `Math.Random.randomFloat64()` に delegate し、その 0..99 化は
// 下の `unitToPercent` と同一式を呼ぶ。unitToPercent を 1 本に保つのは、live と oracle が
// 無言で乖離しないため（両者が唯一の reduction を共有する）。
//
// WhyNot Random.int(0,100) 直呼び: それだと 0..99 化が Random 内に移り、live ハンドラの
// unitToPercent と別コピーになって単一集約が崩れる。生 unit を Random.float(0,1) から受け取り、
// 0..99 化だけ fe_rogue の unitToPercent で行うことで stream 共有と単一集約を両立する。

mod Prng {

    /// PRNG 状態（flix-random の種をそのまま使う）。
    pub type alias State = Random.Seed

    /// 任意の Int64 を seed にして初期状態を作る。
    pub def seed(s: Int64): State = Random.initialSeed(s)

    /// 状態の生 Int64（テスト/シリアライズ補助）。
    pub def rawState(st: State): Int64 = let Random.Seed.Seed(s) = st; s

    /// [0,1) の unit を 0..99 へ畳む reduction の SINGLE SOURCE OF TRUTH。
    /// live `World.RngDraw` ハンドラ（WorldDriver）と Prng.nextPercent の双方がこの一本を呼ぶ。
    /// 式が二箇所に複製されると live と oracle が無言で乖離するため exactly once に集約する。
    pub def unitToPercent(unit: Float64): Int32 =
        Float64.truncateToInt32(Float64.floor(unit * 100.0))

    /// 0..99 の一様乱数を 1 つ引き、次状態を返す（live rollPercent と同じ reduction ドメイン）。
    /// 生 unit（上位 53bit / 2^53）は Random.float(0,1) が供給し、0..99 化だけ unitToPercent で行う。
    pub def nextPercent(st: State): (Int32, State) =
        let (unit, st1) = Random.step(Random.float(lo = 0.0, hi = 1.0), st);
        (unitToPercent(unit), st1)

}
