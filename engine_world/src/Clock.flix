// Clock — 時間アキュムレータのプリミティブ（node 版の Timer ノードの最小版）
//
// node 版が Timer ノード＋TimerHandler で担っていた「dt を貯めて一定間隔で発火」「カウントダウン」を、
// Float64 だけの純関数に寄せる共有部品。spawn 間隔・スコア間隔・アニメのフレーム送り・Get Ready の
// 残り時間などが、すべてこの2関数で表せる（SpriteComp 等ゲーム固有型に非依存）。

mod Clock {

    /// 反復タイマー: acc に dt を足し、interval に達したら（== も含む）1回 fire（rest に余りを残す）。
    /// 達しなければ fired=false、rest=acc+dt（貯め続ける）。
    /// 1 tick で最大1回（dt ≪ interval が前提。dt が interval を超えても 1 回だけ発火し
    /// 余りは rest に繰り越す＝脱落しない）。Timer(oneShot=false) 相当。
    pub def tick(acc: Float64, dt: Float64, interval: Float64): {fired = Bool, rest = Float64} =
        let t = acc + dt;
        if (t < interval) {fired = false, rest = t}
        else {fired = true, rest = t - interval}

    /// カウントダウン: 残り時間を dt 減らし、0 で下げ止める。Timer(oneShot=true) 相当。
    pub def countdown(remaining: Float64, dt: Float64): Float64 =
        Float64.max(0.0, remaining - dt)
}
