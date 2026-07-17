/// UiSlider — 値を左右キーやドラッグでつまみ動かす部品の純粋ヘルパ。
/// 値そのもの（音量・明るさ等）は state で持ち回り、見た目（塗り幅・つまみの位置）は
/// project が導く。ui.json 側は名前付きの track/fill/knob の組で表現し、apply が
/// 数値を書き込むだけ（widget の新種は増やさない）。
mod UiSlider {

    /// スライダーの値。value は [min, max] にクランプされている前提、notch は
    /// 左右キー 1 回ぶんの刻み幅。
    pub type alias State = { value = Float64, min = Float64, max = Float64, notch = Float64 }

    /// 左右キー 1 回ぶんの入力（delta = -1/0/+1）で value を notch ぶん動かし、
    /// [min, max] へクランプする。ホールドで加速する仕組みは持たない
    /// （呼び側が InputMap.taps で単発 tap を渡す想定）。
    pub def step(delta: Int32, st: State): State =
        let moved = st#value + Int32.toFloat64(delta) * st#notch;
        { value = clamp(moved, st#min, st#max) | st }

    /// マウス x 座標（design 座標）から値を逆算する。trackWidth <= 0 のときは
    /// 動かしようがないので min を返す。
    pub def dragValue(cursorX: Float64, trackLeftX: Float64, trackWidth: Float64, st: State): Float64 =
        if (trackWidth <= 0.0) st#min
        else {
            let t = clamp((cursorX - trackLeftX) / trackWidth, 0.0, 1.0);
            st#min + t * (st#max - st#min)
        }

    /// 今の値を track 上の見た目（塗り幅・つまみの x）へ投影する。
    /// fillWidth はトラック左端からの塗り幅、knobX はトラック左端基準のつまみ中心 x。
    pub def projectTo(st: State, trackWidth: Float64): { fillWidth = Float64, knobX = Float64 } =
        let span = st#max - st#min;
        let t = if (span <= 0.0) 0.0 else clamp((st#value - st#min) / span, 0.0, 1.0);
        { fillWidth = trackWidth * t, knobX = trackWidth * t }

    /// namePath 配下の `${namePath}/fill` に塗り幅、`${namePath}/knob` につまみの
    /// フロー外オフセット（x = knobX、y は既存の abs.y を保つ）を書き込む。
    /// knob のフロー外オフセットは ui.json 側で y だけ決め打ちしてある前提
    /// （UiStore.setAbs は x/y をまとめて上書きするため、y は widthPxOf 等と違って
    /// 読み戻さず track の中央 y をここへ渡す設計にしてある）。
    pub def apply(namePath: String, st: State, trackWidth: Float64, knobY: Float64, ui: UiStore.UiWorld): UiStore.UiWorld =
        let proj = projectTo(st, trackWidth);
        ui
            |> UiStore.setWidthPx("${namePath}/fill", proj#fillWidth)
            |> UiStore.setAbs("${namePath}/knob", { x = proj#knobX, y = knobY })

    def clamp(v: Float64, lo: Float64, hi: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))
}
