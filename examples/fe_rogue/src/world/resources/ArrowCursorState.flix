/// ArrowCursorState — 杖・投擲の照準矢印の論理状態を保持する effect
///
/// `StaffAim` / `ThrowAim` フェーズで出る方向照準矢印が指す論理状態をまとめて持つ。
/// 見た目（矢印の位置・回転）は
/// `ArrowCursorDriver` の view が描き、この resource は「どこを起点にどの方向を指しているか」
/// の状態だけを持つ。
///
/// `ArrowCursorDriver.showFor` / `aim` が書き、`getDirection`（発射確定時の方向読み）が読む。
/// TurnPhase / SelectedPlayer / CursorState と同じ Ref-based handler 注入パターンに揃える。
mod ArrowCursorState {

    /// 照準矢印固有の状態。
    /// `anchor`: プレイヤーのグリッドセル座標（隣接セル算出の起点）。
    /// `direction`: 現在の発射方向。
    /// `gridPos`: anchor から direction だけ進めた隣接セル（= 矢印の論理位置）。
    pub type alias Data = {
        anchor    = {x = Int32, y = Int32},
        direction = Dir4.Dir4,
        gridPos   = {x = Int32, y = Int32}
    }

    /// 初期状態（原点・Up・原点）。`showFor` が StaffAim 開始時に put で上書きする。
    pub def initial(): Data =
        {anchor = {x = 0, y = 0}, direction = Dir4.Up, gridPos = {x = 0, y = 0}}

    /// `withState` が提供する handler 1 つで処理する。
    pub eff State {
        def get(): Data
        def put(target: Data): Unit
    }

    /// 内部 `arrowRef` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let arrowRef: Ref[Data, r] = Ref.fresh(rc, initial());
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(arrowRef))
                def put(target, k) = {
                    Ref.put(target, arrowRef);
                    k()
                }
            }
        }
}
