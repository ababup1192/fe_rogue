/// LevelUpPanelState — レベルアップ演出パネルの進行状態を持つ effect resource
///
/// レベルアップパネル（`LevelUpPanelUi` が描く World-entity UI）の「bonus 音を鳴らして演出を
/// 開始済みか」「右側『-> 新値 +1』を出し終えた上昇ステータスの数」「次のアクションまでの残り待ち時間」を
/// まとめて持つ。見た目（中央パネル + ステータス増分）は `UiRender` が `UiWorldState` から毎フレーム描き、
/// この resource は演出の進行状態だけを持つ。
/// `LogState` / `ItemPickupPopupState` と同じ Ref-based handler 注入パターンに揃える。
mod LevelUpPanelState {

    /// パネル表示中の演出の進行状態。
    ///   - `started`  : bonus.ogg を鳴らして演出を開始済みか（LevelUpView 突入の最初のフレームで true）。
    ///   - `revealed` : 右側「-> 新値 +1」を出し終えた「上昇ステータス」を含む行数。
    ///   - `timer`    : 次のアクション（最初の reveal / 次の reveal）までの残り待ち時間。
    ///                  フレームごとに delta だけ減算し 0 になったら次の演出へ進む。
    pub type alias PanelState = {
        started  = Bool,
        revealed = Int32,
        timer    = Duration.Duration
    }

    /// 演出開始前の初期状態。LevelUpView の外では常にこれに戻し、次のレベルアップで鳴らし直す。
    pub def initialState(): PanelState =
        {started = false, revealed = 0, timer = Duration.zero()}

    /// `withState` が提供する handler 1 つで演出の進行状態を読み書きする。
    pub eff State {
        def get(): PanelState
        def put(st: PanelState): Unit
    }

    /// 内部 `ref` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let ref: Ref[PanelState, r] = Ref.fresh(rc, initialState());
            run {
                thunk()
            } with handler State {
                def get(k)     = k(Ref.get(ref))
                def put(st, k) = { Ref.put(st, ref); k() }
            }
        }
}
