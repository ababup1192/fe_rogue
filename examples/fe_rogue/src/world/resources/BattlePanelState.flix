/// BattlePanelState — 戦闘予報ミニウィンドウの「減る分」点滅サイクルの累積時間を持つ effect resource
///
/// 戦闘予報パネル（`BattlePanelUi` が描く World-entity UI）は、足元 HP バーの「減る分」を
/// 暗⇄明で点滅させる。その点滅サイクルの累積時間だけをこの resource が持ち、`BattlePanelUi.frameStep`
/// が毎フレーム delta で進めて暗/明を判定する。見た目（予報のウィンドウ・数値・矢印）は `UiRender` が
/// `UiWorldState` から毎フレーム描き、この resource は点滅位相だけを持つ。
/// `LogState` / `TurnEndHoldState` と同じ Ref-based handler 注入パターンに揃える。
mod BattlePanelState {

    /// `withState` が提供する handler 1 つで点滅サイクルの累積時間を読み書きする。
    pub eff State {
        def get(): Duration.Duration
        def put(elapsed: Duration.Duration): Unit
    }

    /// 内部 `ref` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    /// 初期値は 0（点滅サイクル先頭）。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let ref: Ref[Duration.Duration, r] = Ref.fresh(rc, Duration.zero());
            run {
                thunk()
            } with handler State {
                def get(k)          = k(Ref.get(ref))
                def put(elapsed, k) = { Ref.put(elapsed, ref); k() }
            }
        }
}
