// Prng — 純粋・決定論的な splitmix64 PRNG
//
// 役割: golden-trace / roll-sequence 等価テストが「同じ seed → 同じ draw 列」を再現できる
// 値→値の PRNG。エフェクトを一切持たない（`World.rng` フィールドに dormant に載る）。
//
// IMPORTANT（live との関係）: live combat の数値はこの Prng を一切通らない。live な
// `World.RngDraw` ハンドラは `Math.Random.randomFloat64()` に delegate し、その reduction
// 式は CombatDriver の旧 `rollPercent` 本体と character-for-character 同一（BODY-IDENTITY）。
// この Prng は test / trace ハーネスだけが行使する。
//
// REDUCTION（rollPercent とドメイン一致）: 64bit 出力の上位 53bit を [0,1) の Float64 unit に
// 写し `Float64.truncateToInt32(Float64.floor(unit * 100.0))` で 0..99 を得る。rollPercent の
// `Float64.truncateToInt32(Float64.floor(randomFloat64() * 100.0))` と同じ floor/truncate 経路。
//
// SHIFT-SEMANTICS: splitmix64 は UNSIGNED 右シフトを要する。Flix の `>>>`(= Int64.rightShift)は
// 符号拡張（arithmetic）なので使わず、stdlib の `Int64.logicalRightShift`（zero-fill を保証）を使う。
// これで probe 不要・sign-fill バグ無し。

mod Prng {

    /// PRNG 状態（splitmix64 の 64bit カウンタを 1 つ wrap）。
    pub enum State(Int64)

    /// 任意の Int64 を seed にして初期状態を作る。
    pub def seed(s: Int64): State = State.State(s)

    /// 状態の生 Int64（テスト/シリアライズ補助）。
    pub def rawState(st: State): Int64 = let State.State(s) = st; s

    // splitmix64 の finalizer（mix）。定数は signed Int64 表現:
    //   0xBF58476D1CE4E5B9 = -4658895280553007687
    //   0x94D049BB133111EB = -7723592293110705685
    // Int64 乗算は two's-complement で wrap する（mod 2^64）。
    def mix(z0: Int64): Int64 =
        let z1 = Int64.bitwiseXor(z0, Int64.logicalRightShift(dist = 30, z0)) * -4658895280553007687i64;
        let z2 = Int64.bitwiseXor(z1, Int64.logicalRightShift(dist = 27, z1)) * -7723592293110705685i64;
        Int64.bitwiseXor(z2, Int64.logicalRightShift(dist = 31, z2))

    // 状態を 1 歩進め、mix 済み 64bit 出力と次状態を返す。
    //   golden gamma 0x9E3779B97F4A7C15 = -7046029254386353131
    def next64(st: State): (Int64, State) =
        let State.State(s) = st;
        let s1 = s + -7046029254386353131i64;
        (mix(s1), State.State(s1))

    /// [0,1) の unit を 0..99 へ畳む reduction の SINGLE SOURCE OF TRUTH。
    /// 旧 rollPercent / live `World.RngDraw` ハンドラ（Game.flix）と Prng.nextPercent の双方が
    /// この一本を呼ぶ。式が二箇所に複製されると live と oracle が無言で乖離するため exactly once に集約する。
    pub def unitToPercent(unit: Float64): Int32 =
        Float64.truncateToInt32(Float64.floor(unit * 100.0))

    /// 0..99 の一様乱数を 1 つ引き、次状態を返す（rollPercent と同じ reduction ドメイン）。
    pub def nextPercent(st: State): (Int32, State) =
        let (z, st1) = next64(st);
        let top53 = Int64.logicalRightShift(dist = 11, z);          // 上位 53bit
        let unit  = Int64.toFloat64(top53) / 9007199254740992.0;    // / 2^53 → [0,1)
        (unitToPercent(unit), st1)

}
