/// LogState — 右下ログ HUD の論理状態を保持する effect
///
/// ログ HUD（`LogUi` が描く World-entity UI）の「表示中の 5 行キュー」と「最後の新着からの
/// 経過時間」を持つ。見た目（半透明の黒帯 + 5 行のテキスト）は `UiRender` が UiWorldState から
/// 毎フレーム描き、この resource は行の中身と寿命タイマーだけを持つ。`TopBarState` /
/// `CursorState` と同じ Ref-based handler 注入パターンに揃える。
mod LogState {

    /// 1 行分の表示エントリ。`GameLogger.Entry` と同形だが、表示側の型として独立させる。
    /// color は engine の Color(`{r,g,b}` Float32)を構造的レコードで展開(cross-package alias 回避)。
    pub type alias LogEntry = { text = String, color = {r = Float32, g = Float32, b = Float32} }

    /// ログ HUD 固有の状態。
    /// `queue`     — 先頭=最新・末尾=最古で最大 `LogUi.maxQueue()` 件。
    /// `idleSince` — 最後に新着があってからの経過時間（`LogUi.holdSeconds()` を超えると消える）。
    pub type alias Data = {
        queue     = List[LogEntry],
        idleSince = Duration.Duration
    }

    /// 初期状態（空キュー・タイマー 0）。`add` 直後は帯を隠す（queue 空 = 非表示）。
    pub def initial(): Data = {queue = Nil, idleSince = Duration.zero()}

    /// `withState` が提供する handler 1 つでログ HUD 状態を読み書きする。
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
