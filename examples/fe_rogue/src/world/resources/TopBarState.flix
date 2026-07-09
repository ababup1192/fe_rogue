/// TopBarState — 上部フェイズバーの論理状態を保持する effect
///
/// 上部バー（`TopBarUi` が描く World-entity UI）の陣営ワイプ演出・敵ターンの「間」・現在フロア
/// 表示をまとめて持つ。見た目（帯 / 下線 / ドット / 文字）は `UiRender` が UiWorldState から
/// 毎フレーム描き、この resource は「どのフェイズを確定表示しているか」「ワイプの残り」等の
/// 状態だけを持つ。`CursorState` / `SelectedPlayer` と同じ Ref-based handler 注入パターンに揃える。
mod TopBarState {

    /// 上部バー固有の状態。
    /// `shown`     — 現在 base に確定表示しているフェイズ（None=起動直後・未確定。true=敵軍）。
    /// `animTarget`— ワイプ中の目標フェイズ（None=ワイプしていない）。
    /// `anim`      — ワイプの残り時間（0=非ワイプ）。
    /// `hold`      — 敵ターン開始の「間」の残り（>0 の間 isBusy=true）。
    /// `floorLabel`— 左に出すフロア番号（"1F" 等。バインディング resolver が読む）。
    /// `floorName` — 左に出すフロア名（"始まりの洞窟" 等。空可）。
    pub type alias Data = {
        shown      = Option[Bool],
        animTarget = Option[Bool],
        anim       = Duration.Duration,
        hold       = Duration.Duration,
        floorLabel = String,
        floorName  = String
    }

    /// 初期状態（未確定・ワイプなし・「間」なし・フロア表示なし）。
    /// フロア表示は `TopBarUi.enter` が floorLabel / floorName を入れて上書きする。
    pub def initial(): Data =
        {shown = None, animTarget = None, anim = Duration.zero(), hold = Duration.zero(),
         floorLabel = "", floorName = ""}

    /// `withState` が提供する handler 1 つで上部バー状態を読み書きする。
    pub eff State {
        def get(): Data
        def put(target: Data): Unit
    }

    /// 内部 `barRef` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let barRef: Ref[Data, r] = Ref.fresh(rc, initial());
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(barRef))
                def put(target, k) = {
                    Ref.put(target, barRef);
                    k()
                }
            }
        }
}
