// CameraRig — 描画物の列にカメラ（オフセット）を掛ける小さな道具箱。
// カメラは状態でなく毎フレーム導出する値なので、変換の保存や復元は要らない。
// 使い方: World に `trauma`（揺れの蓄積量 [0,1]）と `fxClock`（通し時計）のフィールドを持たせれば、
// addTrauma で積み・tick で減衰させ・shakeOffset で揺れを導ける（どれも record をそのまま渡せる）。
// 描画物には apply / applyPoly でレイヤーごとに一括適用する。
mod CameraRig {

    /// レイヤーの見方。いまはオフセットだけ（ズームや視差を足す日はここが伸びる）。
    pub type alias Camera = { offset = Vec2.Vec2 }

    /// 動かないカメラ（HUD などスクリーン空間のレイヤー用）。
    pub def fixed(): Camera = { offset = Vec2.zero() }

    /// カメラを描画物の列（(置き場所, RenderItem)）に適用する。多角形（Poly）も置き場所ごと
    /// 動くので、種類を問わずこの 1 本で足りる。
    pub def apply(cam: Camera, items: List[(Vec2.Vec2, Render.RenderItem)]): List[(Vec2.Vec2, Render.RenderItem)] =
        List.map(entry -> { let (pos, item) = entry; (Vec2.add(pos, cam#offset), item) }, items)

    // ── 画面シェイク（trauma 方式）──

    /// シェイクの調整値。maxOffset は trauma 満タン（1.0）のときの揺れ幅（px）、
    /// freq は揺れの速さ（ノイズの格子点が 1 秒に進む数）、decayPerSecond は trauma の
    /// 1 秒あたりの減衰量。
    pub type alias ShakeSpec = { maxOffset = Float64, freq = Float64, decayPerSecond = Float64 }

    /// 揺れを積む: trauma に amount を加算する（上限 1.0）。減衰（tick）より速く積めば蓄積し、
    /// 単発では出ない大揺れが連打で現れる。trauma フィールドを持つ record ならそのまま渡せる。
    pub def addTrauma(amount: Float64, state: { trauma = Float64 | r }): { trauma = Float64 | r } =
        { trauma = Float64.min(1.0, state#trauma + amount) | state }

    /// 揺れの経年: trauma を減衰させ（下限 0.0）、通し時計 fxClock を進める。毎フレーム 1 回 dt を渡す。
    pub def tick(dt: Float64, spec: ShakeSpec, state: { trauma = Float64, fxClock = Float64 | r }): { trauma = Float64, fxClock = Float64 | r } =
        { trauma = Float64.max(0.0, state#trauma - spec#decayPerSecond * dt),
          fxClock = state#fxClock + dt | state }

    /// trauma からの揺れ幅（px）: trauma² × maxOffset。二乗なので単発の小さな trauma は
    /// ほとんど揺れず、蓄積すると急に効く。
    pub def shakeStrength(trauma: Float64, maxOffset: {maxOffset = Float64}): Float64 =
        if (trauma <= 0.0) 0.0
        else trauma * trauma * maxOffset#maxOffset

    /// シェイクのオフセット（px）: 揺れ幅（shakeStrength）× 滑らかノイズ [-1, 1]。
    /// fxClock は常に進む時計（ノイズの位相）。trauma が 0 なら揺れない。
    pub def shakeOffset(spec: ShakeSpec, state: { trauma = Float64, fxClock = Float64 | r }): Vec2.Vec2 =
        let strength = shakeStrength(state#trauma, maxOffset = spec#maxOffset);
        if (strength <= 0.0) Vec2.zero()
        else {
            let t = state#fxClock * spec#freq;
            { x = strength * smoothNoise(t, 0),
              y = strength * smoothNoise(t, 1) }
        }

    /// 滑らかな 1D ノイズ [-1, 1]: 整数の格子点に Hash01 の値を置き、間を quintic フェード
    /// （6t⁵-15t⁴+10t³）で補間する。格子点でちょうど Hash01 に一致し、間は連続に繋がるので、
    /// カメラが飛び回らず滑らかに揺れる。channel で x/y の系列を分ける。
    pub def smoothNoise(t: Float64, channel: Int32): Float64 =
        let i = Float64.floor(t);
        let frac = t - i;
        let fade = frac * frac * frac * (frac * (frac * 6.0 - 15.0) + 10.0);
        let idx = Float64.tryToInt32(i) |> Option.getWithDefault(0);
        let a = 2.0 * Hash01.at(idx, channel) - 1.0;
        let b = 2.0 * Hash01.at(idx + 1, channel) - 1.0;
        a + (b - a) * fade
}
