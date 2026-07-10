// Jump — ジャンプと走りの手触りの式（本作の要）。すべて World を知らない純関数。
//
// 重力は「重力加速度」でなく「頂点の高さ jumpHeight と頂点までの時間 timeToApex」で指定する:
//   初速 = -2h/t, 上昇の重力 = 2h/t²（等加速度運動の閉じた式）。
// 「もう少し高く」「もう少しキビキビ」を高さと時間で直接回せて、数値の意味が失われない。
//
// 手触りの 4 要素:
//   可変ジャンプ高 … ボタンを離した瞬間、上昇速度を cutMult 倍に削る（短押し = 低く飛ぶ）
//   コヨーテタイム … 離床後 coyoteTime 秒はまだ地上扱いでジャンプできる
//   ジャンプバッファ … 着地前 bufferTime 秒以内の押下は着地の瞬間に飛ぶ
//   非対称の重力   … 下降は fallGravityMult 倍で速く落ち、頂点付近（|vy| が apexBand 未満）は
//                     apexGravityMult 倍でふわりと滞空する

mod Jump {
    use GameParameters.Params

    // ── 既定値（コード内定数が正。parameters.json はこれを一時的に上書きするだけ）──

    pub def jumpHeight(): Float64 = 96.0            // 頂点までの高さ px
    pub def timeToApex(): Float64 = 24.0 / 64.0     // 頂点までの秒（1/64 の倍数で pin を厳密に）
    pub def fallGravityMult(): Float64 = 1.8        // 下降の重力倍率
    pub def apexBand(): Float64 = 40.0              // |vy| がこれ未満なら頂点帯 px/s
    pub def apexGravityMult(): Float64 = 0.5        // 頂点帯の重力倍率
    pub def cutMult(): Float64 = 0.4                // 離した瞬間の上昇速度倍率
    pub def maxFallSpeed(): Float64 = 900.0         // 落下の終端速度 px/s
    pub def maxRunSpeed(): Float64 = 160.0          // 走りの最高速 px/s
    pub def dashMult(): Float64 = 1.75              // B ダッシュ中の最高速倍率（160 → 280）
    pub def dashAccel(): Float64 = 80.0             // P スピード帯（|vx| > 160）の加速 px/s²
    pub def groundAccel(): Float64 = 900.0          // 地上の加速 px/s²
    pub def groundDecel(): Float64 = 1200.0         // 地上の減速（摩擦）px/s²
    pub def airAccel(): Float64 = 500.0             // 空中の加速（空中制御の強さ）px/s²
    pub def airDecel(): Float64 = 100.0             // 空中の減速（慣性がよく残る）px/s²
    pub def coyoteTime(): Float64 = 6.0 / 64.0      // 離床後もジャンプできる猶予 秒
    pub def bufferTime(): Float64 = 8.0 / 64.0      // 着地前の押下を拾う猶予 秒

    // ── 重力（縦）──

    /// ジャンプの初速（負 = 上向き）。頂点の高さと時間から導く: -2h/t。
    pub def jumpVelocity(p: Params): Float64 =
        -2.0 * p#jumpHeight / p#timeToApex

    /// 上昇の重力加速度: 2h/t²。下降・頂点帯は gravityScale が倍率を掛ける。
    pub def riseGravity(p: Params): Float64 =
        2.0 * p#jumpHeight / (p#timeToApex * p#timeToApex)

    /// いまの縦速度に応じた重力の倍率。上昇 = 1.0、頂点帯 = 緩く、下降 = 強く。
    pub def gravityScale(p: Params, vy: Float64): Float64 =
        if (vy < -p#apexBand) 1.0
        else if (vy <= p#apexBand) p#apexGravityMult
        else p#fallGravityMult

    /// 重力を 1 フレームぶん適用する（落下は maxFallSpeed で頭打ち）。
    pub def applyGravity(p: Params, dt: Float64, vy: Float64): Float64 =
        Float64.min(vy + riseGravity(p) * gravityScale(p, vy) * dt, p#maxFallSpeed)

    // ── 走り（横）──

    /// horizontalStep へ渡す走りの状況（同型の引数が並ぶので名前渡し）。
    pub type alias Run = { grounded = Bool, dash = Bool, dir = Float64, vx = Float64 }

    /// 横速度を 1 フレームぶん進める。dir ∈ {-1,0,1}。
    /// 入力ありは目標速度 dir×maxRunSpeed（B ダッシュ中は dashMult 倍）へ加速で寄せ、
    /// 入力なしは 0 へ減速で寄せる。加速・減速とも地上/空中で別の値を使う
    /// （空中は減速が小さい = 慣性が残る）。
    ///
    /// P スピード（マリオの P メーター相当）: 加速は 2 帯構成で、|vx| が maxRunSpeed（160）
    /// までは今までどおりキビキビ、160 を超える帯は dashAccel（80px/s²）でじわじわ伸びる
    /// —— 160→280 に 1.5 秒（約 330px の助走）かかる。ダッシュを離したときの
    /// 目標 160 への戻りも同じ式が使われる: 帯の中は dashAccel で緩やかに落ちる。
    /// これも「勢いがなかなか死なない」P スピードらしい挙動（意図した仕様）。
    ///
    /// 空中だけ P 帯の適用が非対称（スマブラの DI 風のベクトル変更）:
    /// 進行方向と逆への入力（切り返し）は帯に関係なく常に airAccel（500px/s²）で強く効き、
    /// ダッシュジャンプ中でも空中で舵が切れる。進行方向への上積みだけが P 帯（dashAccel）
    /// —— 助走は地上でしか作れず、空中で速度は盛れない。
    pub def horizontalStep(p: Params, dt: Float64, running: Run): Float64 =
        if (running#dir != 0.0) {
            let accel =
                if (running#grounded)
                    (if (Float64.abs(running#vx) > p#maxRunSpeed) p#dashAccel else p#groundAccel)
                else {
                    // 空中: 切り返し（進行方向と逆への入力）は常に airAccel で強く効く（ベクトル変更）。
                    // 進行方向への上積みだけ P スピード帯（dashAccel）= 空中で速度は盛れない。
                    let steering = running#dir * running#vx < 0.0;
                    if (steering) p#airAccel
                    else if (Float64.abs(running#vx) > p#maxRunSpeed) p#dashAccel
                    else p#airAccel
                };
            let top = p#maxRunSpeed * (if (running#dash) p#dashMult else 1.0);
            approach(running#dir * top, accel * dt, running#vx)
        } else {
            let decel = if (running#grounded) p#groundDecel else p#airDecel;
            approach(0.0, decel * dt, running#vx)
        }

    /// current を target へ最大 step だけ寄せる（行き過ぎない）。
    def approach(target: Float64, step: Float64, current: Float64): Float64 =
        if (current < target) Float64.min(current + step, target)
        else Float64.max(current - step, target)

    // ── ジャンプの成立とカット ──

    /// このフレームで飛べるか: バッファに押下が残っていて、地上かコヨーテ猶予内。
    pub def canJump(grounded: Bool, coyoteLeft: Float64, bufferLeft: Float64): Bool =
        bufferLeft > 0.0 and (grounded or coyoteLeft > 0.0)

    /// ボタンを離した瞬間の上昇カット。上昇中（vy < 0）だけ削り、下降は素通し。
    pub def cutJump(p: Params, vy: Float64): Float64 =
        if (vy < 0.0) vy * p#cutMult else vy

    // ── タイマー ──

    /// 残り時間を 1 フレームぶん減らす（0 で止まる）。
    pub def tickTimer(dt: Float64, t: Float64): Float64 =
        Float64.max(0.0, t - dt)
}
