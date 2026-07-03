/// TurnEndHoldState — Shift 長押しゲージの論理状態を保持する effect
///
/// ターンスキップ長押しゲージ（`TurnEndHoldUi` が描く World-entity UI）の「連続して押している
/// 経過時間」と「前フレームの押下」をまとめて持つ。見た目（ログ帯の上に重ねる充填リング + テキスト）は
/// `UiRender` が UiWorldState から毎フレーム描き、この resource は経過時間と押下エッジ判定だけを持つ。
/// `LogState` / `TitleMenuState` と同じ Ref-based handler 注入パターンに揃える。
mod TurnEndHoldState {

    /// ゲージ固有の状態。
    /// `elapsed`  — 連続して arm 中の経過時間（離す / 未 arm の間は 0）。`> 0` が「充填中(armed)」を表す。
    /// `prevHeld` — 前フレームの held。`held` が false→true に変わったフレーム（新規押下エッジ）だけ
    ///              arm を許す判定に使う。固着した Shift は held=true が続いても prevHeld も true に
    ///              収束するためエッジが立たず、arm されない（暴発防止の要）。
    pub type alias GaugeData = {
        elapsed  = Duration.Duration,
        prevHeld = Bool
    }

    /// 起動直後の状態（経過 0・前フレーム未押下）。
    pub def initial(): GaugeData =
        {elapsed = Duration.zero(), prevHeld = false}

    /// `withState` が提供する handler 1 つでゲージ状態を読み書きする。
    pub eff State {
        def get(): GaugeData
        def put(data: GaugeData): Unit
    }

    /// 内部 `ref` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let ref: Ref[GaugeData, r] = Ref.fresh(rc, initial());
            run {
                thunk()
            } with handler State {
                def get(k)       = k(Ref.get(ref))
                def put(data, k) = { Ref.put(data, ref); k() }
            }
        }
}
