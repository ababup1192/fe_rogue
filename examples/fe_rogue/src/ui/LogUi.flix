// LogUi — 右下に出る「5 行の一時ログ」HUD（World-entity UI 版）。
//
// UI ツリーは Log.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。見た目は
// UiRender が毎フレーム描く。ここは GameLogger(engine effect) に溜まったメッセージを毎フレーム
// drain し、最新 5 行だけを右下に流し込む配線と、寿命タイマー（最後の新着から約 5 秒で消える）を持つ。
//
// 上(line0)=最新・下(line4)=最古のキューで、6 件目が来たら最古が落ちる。新しいログが来た瞬間に
// 表示し、最後のログから holdSeconds 秒で消える。表示状態（queue / idleSince）は LogState resource が
// 権威で、各行のテキスト・色は毎フレーム queue から流し込む（bind ではなく setText/setTextTint）。
//
// 表示内容の発生(戦闘ログ・アイテム踏みログ)は CombatDriver / PlayerMovementDriver が
// GameLogger.playerLog/enemyLog で行い、ここは「drain して 5 行に並べる」表示だけを担う。
//
// ノード構造（Log.ui.json / layer=1）:
//   Log (none, 画面固定 HUD)
//     ├─ Bg    (box, 半透明の黒帯)
//     └─ line0..4 (none 行コンテナ・右寄せ) → label (text)  line0=最新
//   空のときは root を不可視にして帯ごと隠す。

mod LogUi {

    // ========================================================================
    // spec 置き場 / 名前パス / 定数
    // ========================================================================

    /// ui.json の置き場。起動時の spawnAsset・F1 リロード台帳の登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/Log.ui.json")

    /// root（可視トグルの対象）の名前パス。
    pub def rootPath(): String = "Log"
    /// i = 0..4。行コンテナ配下の text ノード "Log/line<i>/label"（右下に右寄せ配置）。
    def linePath(i: Int32): String = "Log/line${i}/label"

    /// 同時に出す最大行数(= Log.ui.json の line0..4 と一致させる)。
    pub def maxQueue(): Int32 = 5
    /// 最後のログからこの秒数が経つと消える。
    pub def holdSeconds(): Float64 = 5.0
    /// 空行の tint(表示しないので色は便宜上の白)。
    def blankColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    // ========================================================================
    // 純粋コア(キュー・タイマー)
    // ========================================================================

    /// drain 順(古→新)の新着を先頭に積み、最大 `maxQueue()` 件に切り詰めたキューを返す。
    /// 既存キューの先頭=最新を保つため、新着は reverse して prepend する。
    pub def enqueue(drainedOldToNew: List[LogState.LogEntry], queue: List[LogState.LogEntry]): List[LogState.LogEntry] =
        List.append(List.reverse(drainedOldToNew), queue) |> List.take(maxQueue())

    /// 経過タイマーを 1 フレーム進める。キューが空なら何もしない。
    /// `idleSince + delta` が `holdSeconds()` 以上になったらキューを空にして消す((Nil, 0))。
    pub def tickIdle(queue: List[LogState.LogEntry], idleSince: Duration.Duration,
                      delta: Duration.Duration): (List[LogState.LogEntry], Duration.Duration) =
        match queue {
            case Nil => (Nil, idleSince)
            case _   =>
                let next = Duration.add(idleSince, delta);
                if (Duration.toSeconds(next) >= holdSeconds()) (Nil, Duration.zero())
                else (queue, next)
        }

    // ========================================================================
    // 毎フレーム更新
    // ========================================================================

    /// gameLoop が 1 回呼ぶ frame-paced System。
    /// drain → キューに積む → 新着があればタイマーを 0 に戻す → 寿命判定 → 5 行へ反映 → 表示/非表示。
    /// Log root は起動時に 1 回 spawn 済み。ダンジョン外（タイトル/選択画面）でも安全: drain はログ
    /// 未発行で空、renderLines/setVisible の対象不在は no-op。空キューのフレームは root を隠す。
    pub def step(delta: Duration.Duration, scene: Scene[NodeTag]):
                    Scene[NodeTag] \ {GameLogger.GameLogger, LogState.State, UiWorldState.State} =
        let drained = GameLogger.drainEntries();
        let data = LogState.State.get();
        let newQueue = enqueue(toLogEntries(drained), data#queue);
        // 新着があったフレームはタイマーを 0 に戻す(その後 tickIdle で進めるので当フレームでは消えない)。
        let idleReset = if (List.isEmpty(drained)) data#idleSince else Duration.zero();
        let (finalQueue, finalIdle) = tickIdle(newQueue, idleReset, delta);
        LogState.State.put({queue = finalQueue, idleSince = finalIdle});
        UiWorldState.State.put(UiWorldState.State.get()
            |> renderLines(finalQueue)
            |> UiStore.setVisible(rootPath(), not List.isEmpty(finalQueue)));
        scene

    /// `GameLogger.Entry`(古→新)を表示用 `LogState.LogEntry` へ写す。
    def toLogEntries(entries: List[GameLogger.Entry]): List[LogState.LogEntry] =
        List.map(e -> ({text = e#text, color = e#color}: LogState.LogEntry), entries)

    /// 各行 text に queue の i 番目を反映する(無い行は空文字にして見えなくする)。
    def renderLines(queue: List[LogState.LogEntry], ui: UiStore.UiWorld): UiStore.UiWorld =
        List.range(0, maxQueue())
            |> List.foldLeft((acc, i) -> {
                let (txt, color) = match List.nth(i, queue) {
                    case Some(e) => (e#text, e#color)
                    case None    => ("", blankColor())
                };
                acc
                    |> UiStore.setText(linePath(i), txt)
                    |> UiStore.setTextTint(linePath(i), color)
            }, ui)

    /// 別 HUD(ターンスキップ等)がログ帯を背景として再利用するための一時オーバーライド。
    /// ログ帯を定位置に出しつつ本文 5 行を空にする(queue は保持)。毎フレーム呼ぶ前提で、
    /// 呼ばれなくなれば次フレームの `step`(先に走る)が queue から復帰させる。
    pub def holdForOverlay(scene: Scene[NodeTag]): Scene[NodeTag] \ UiWorldState.State =
        let cleared = List.range(0, maxQueue())
            |> List.foldLeft((acc, i) -> UiStore.setText(linePath(i), "", acc), UiWorldState.State.get());
        UiWorldState.State.put(UiStore.setVisible(rootPath(), true, cleared));
        scene
}
