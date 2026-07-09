/// ItemPickupPopupState — 中央アイテム取得ポップアップの論理状態を保持する effect
///
/// 中央ポップアップ（`ItemPickupPopupUi` が描く World-entity UI）の「演出段階」「段階内の経過時間」
/// 「取得音の予約」「表示中の文言」をまとめて持つ。見た目（中央の窓 + 文字のフェード）は `UiRender` が
/// UiWorldState から毎フレーム描き、この resource は演出の進行状態だけを持つ。
/// `LogState` / `TitleMenuState` と同じ Ref-based handler 注入パターンに揃える。
mod ItemPickupPopupState {

    /// 演出段階。
    ///   Idle    — フェード終了後に戻る終端状態。ratio=0 で窓も非表示。`show` で FadeIn へ抜け出す。
    ///   FadeIn  — ratio が 0→1 に上がる過渡状態。完了即 Hold へ。
    ///   Hold    — ratio=1.0 固定のまま holdDuration だけ待つ（補間は不要なので elapsed だけ加算）。
    ///   FadeOut — ratio が 1→0 に下がる過渡状態。完了即 Idle へ戻り窓を消す。
    pub enum Stage with Eq, ToString {
        case Idle
        case FadeIn
        case Hold
        case FadeOut
    }

    /// ポップアップ固有の状態。
    /// `stage`        — 今の演出段階。
    /// `elapsed`      — 今の段階に入ってからの経過時間（段階ごとに 0 から数え直す）。
    /// `soundPending` — `show` で true。`frameStep` が取得音を1回鳴らしたら false にする。
    /// `text`         — 表示中の文言（`show` 系がセットし、`frameStep` が毎フレーム UI へ流し込む）。
    pub type alias PopupData = {
        stage        = Stage,
        elapsed      = Duration.Duration,
        soundPending = Bool,
        text         = String
    }

    /// 起動直後の状態（非表示・音予約なし・文言空）。
    pub def initial(): PopupData =
        {stage = Stage.Idle, elapsed = Duration.zero(), soundPending = false, text = ""}

    /// `withState` が提供する handler 1 つでポップアップ状態を読み書きする。
    pub eff State {
        def get(): PopupData
        def put(data: PopupData): Unit
    }

    /// 内部 `ref` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let ref: Ref[PopupData, r] = Ref.fresh(rc, initial());
            run {
                thunk()
            } with handler State {
                def get(k)       = k(Ref.get(ref))
                def put(data, k) = { Ref.put(data, ref); k() }
            }
        }
}
