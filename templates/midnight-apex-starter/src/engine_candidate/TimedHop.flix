// TimedHop — 滞空中の時間と高さだけを扱う純粋な規則。
// コース記号、機体、音を知らないため、別のゲームでもそのまま読み替えられる。
mod TimedHop {

    /// 地上、または決められた時間だけ続く空中。
    pub enum State {
        case Grounded,
        case Airborne({ elapsed = Float64, duration = Float64 })
    }

    /// 地上から始まる状態。
    pub def grounded(): State = State.Grounded

    /// 地上にいる時だけジャンプを始める。空中で台を越えても二段ジャンプしない。
    pub def start(duration: Float64, state: State): State =
        match state {
            case State.Grounded =>
                State.Airborne({
                    elapsed = 0.0,
                    duration = Float64.max(0.001, duration)
                }),
            case State.Airborne(_) => state
        }

    /// 経過時間を進め、予定時間を使い切った拍で地上へ戻す。
    pub def step(deltaTime: Float64, state: State): State =
        match state {
            case State.Grounded => state,
            case State.Airborne(air) =>
                let elapsed = air#elapsed + Float64.max(0.0, deltaTime);
                if (elapsed >= air#duration)
                    State.Grounded
                else
                    State.Airborne({ elapsed = elapsed | air })
        }

    /// 壁やライバルとの接触を無効にする判断へ使う。
    pub def isAirborne(state: State): Bool =
        match state {
            case State.Grounded => false,
            case State.Airborne(_) => true
        }

    /// 0→最高点→0の放物線。位置はViewだけが読み、当たり判定には混ぜない。
    pub def height(maxHeight: Float64, state: State): Float64 =
        match state {
            case State.Grounded => 0.0,
            case State.Airborne(air) =>
                let progress = Float64.min(1.0, air#elapsed / air#duration);
                Float64.max(0.0, maxHeight) * 4.0 * progress * (1.0 - progress)
        }
}
