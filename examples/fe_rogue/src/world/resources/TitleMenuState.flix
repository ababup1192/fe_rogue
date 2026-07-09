/// TitleMenuState — タイトル画面の論理状態を保持する effect
///
/// タイトル画面（`TitleMenuUi` が描く World-entity UI）の「2 択カーソル」と「中断から再開が
/// 選べるか」をまとめて持つ。見た目（背景 / タイトル文字 / 選択肢 / 塗り箱ハイライト）は
/// `UiRender` が UiWorldState から毎フレーム描き、この resource は選択位置と再開可否だけを持つ。
/// `TopBarState` / `CursorState` と同じ Ref-based handler 注入パターンに揃える。
mod TitleMenuState {

    /// タイトル画面固有の状態。
    /// `cursor`    — 0 = はじめから / 1 = 中断から再開。
    /// `resumable` — 中断データが再開可能か（画面進入時に `SaveManager.read` を 1 回見て確定）。
    pub type alias Data = {
        cursor    = Int32,
        resumable = Bool
    }

    /// 初期状態（先頭選択・再開不可）。画面進入時に `TitleMenuUi.enter` が再判定して上書きする。
    pub def initial(): Data = {cursor = 0, resumable = false}

    /// `withState` が提供する handler 1 つでタイトル画面状態を読み書きする。
    pub eff State {
        def get(): Data
        def put(data: Data): Unit
    }

    /// 内部 `ref` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let ref: Ref[Data, r] = Ref.fresh(rc, initial());
            run {
                thunk()
            } with handler State {
                def get(k)       = k(Ref.get(ref))
                def put(data, k) = { Ref.put(data, ref); k() }
            }
        }
}
