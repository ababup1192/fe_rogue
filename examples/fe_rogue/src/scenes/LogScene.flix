/// LogScene — 右下に出る「5行の一時ログ」HUD
///
/// `GameLogger`(engine effect) に溜まったメッセージを毎フレーム drain し、最新 5 行だけを
/// 右下に出す。上(Line0)=最新・下(Line4)=最古のキューで、6 件目が来たら最古が落ちる。
/// 新しいログが来た瞬間に表示し、最後のログから約 5 秒で消える。
///
/// 表示内容の発生(戦闘ログ・アイテム踏みログ)は CombatScene / PlayerMovementScene が
/// `GameLogger.playerLog`/`enemyLog` で行い、ここは「drain して 5 行に並べる」表示だけを担う。
///
/// ノード構造（design 240x128 の右下に座標で配置）:
///   Log (CanvasLayer, NodeTag.Log({queue, idleSince}))   ← offset(x) を動かして帯ごと出し入れ
///     ├─ Bg    (ColorRect, 半透明の黒帯)
///     └─ Line0..4 (Label2D, 右寄せ。Line0=最新)
///
/// CanvasLayer は可視切替で隠せない(PhaseBannerScene 参照)ため、空のときは offset を画面外へ動かす。
mod LogScene {

    /// 1 行分の表示エントリ。`GameLogger.Entry` と同形だが、表示側の型として独立させる。
    /// color は engine の Color(`{r,g,b}` Float32)を構造的レコードで展開(cross-package alias 回避)。
    pub type alias LogEntry = { text = String, color = {r = Float32, g = Float32, b = Float32} }

    /// ログ HUD の状態（P4: NodeTag ペイロードから resource へ移設）。
    /// `queue` は先頭=最新・末尾=最古で最大 `maxQueue()` 件。`idleSince` は最後に新着があってからの経過時間。
    pub type alias Data = {
        queue     = List[LogEntry],
        idleSince = Duration.Duration
    }

    /// P4-a: ログ HUD の状態を持つ resource（Pacing.State / SelectedPlayer.State と同じ Ref-backed handler）。
    /// 旧: `NodeTag.Log(Data)` に埋め込んでいた queue/idleSince を effect へ移し、`NodeTag.Log` をペイロードレス化。
    /// `Game.start` で `with LogScene.withState(rc)` を 1 行注入し、`FrameAef.ProcessT` に `LogScene.State` を足す。
    pub eff State {
        /// 現在の状態（queue + idleSince）を読む。
        def get(): Data
        /// 状態を全置換する（process が drain→enqueue→tickIdle 後に 1 回書く）。
        def put(data: Data): Unit
    }

    /// Ref を closure に閉じ込めた状態 handler。初期は空キュー（`add` 直後は画面外に隠す）。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let ref: Ref[Data, r] = Ref.fresh(rc, {queue = Nil, idleSince = Duration.zero()});
            run {
                thunk()
            } with handler State {
                def get(k)       = k(Ref.get(ref))
                def put(data, k) = { Ref.put(data, ref); k() }
            }
        }

    // ─── 定数・パス ───────────────────────────────────────────
    def name(): String = "Log"
    pub def logPath(): NodePath = name() :: Nil
    /// i = 0..4。CanvasLayer 直下の Label2D "Line<i>"（右下に右寄せ配置）。
    pub def linePath(i: Int32): NodePath = name() :: "Line${i}" :: Nil

    /// 同時に出す最大行数(= scene.json の Line0..4 と一致させる)
    def maxQueue(): Int32 = 5
    /// 最後のログからこの秒数が経つと消える
    def holdSeconds(): Float64 = 5.0
    /// 空のとき CanvasLayer をこの x に飛ばして画面外へ隠す
    def hiddenOffsetX(): Float64 = -300.0
    /// 表示中の CanvasLayer の x(scene.json の絶対座標どおりに見せる)
    def homeOffsetX(): Float64 = 0.0
    /// fontManifest で登録した name と一致させる
    def fontName(): String = "ui"
    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/LogScene.scene.json")
    /// 空行の modulate(表示しないので色は便宜上の白)
    def blankColor(): {r = Float32, g = Float32, b = Float32} = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    // ─── 純粋コア(キュー・タイマー) ───────────────────────────

    /// drain 順(古→新)の新着を先頭に積み、最大 `maxQueue()` 件に切り詰めたキューを返す。
    /// 既存キューの先頭=最新を保つため、新着は reverse して prepend する。
    pub def enqueue(drainedOldToNew: List[LogEntry], queue: List[LogEntry]): List[LogEntry] =
        List.append(List.reverse(drainedOldToNew), queue) |> List.take(maxQueue())

    /// 経過タイマーを 1 フレーム進める。キューが空なら何もしない。
    /// `idleSince + delta` が `holdSeconds()` 以上になったらキューを空にして消す((Nil, 0))。
    pub def tickIdle(queue: List[LogEntry], idleSince: Duration.Duration,
                      delta: Duration.Duration): (List[LogEntry], Duration.Duration) =
        match queue {
            case Nil => (Nil, idleSince)
            case _   =>
                let next = Duration.add(idleSince, delta);
                if (Duration.toSeconds(next) >= holdSeconds()) (Nil, Duration.zero())
                else (queue, next)
        }

    // ─── 構築 ─────────────────────────────────────────────────

    /// Scene に Log ノード(CanvasLayer + Bg + Line0..4)を追加する。
    /// レイアウトは scene.json、ここでは初期 Data 注入・5 行の右寄せ・初期非表示(画面外)を行う。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        // P4-a: 状態は `LogScene.State`（resource）が持つ。ノードは識別用の純タグ `NodeTag.Log`。
        let loaded = SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas,
                         SceneLoader.constTagParser(NodeTag.NoTag), scene)
            |> Scene.setState(logPath(), NodeTag.Log)
            |> setOffsetX(hiddenOffsetX());   // 初期は空なので画面外へ
        // 5 行とも右寄せ(右下に寄せて出すため)。scene.json は alignment 非対応なのでここで適用。
        List.foldLeft((s, i) ->
            Label2D.mapAt(linePath(i),
                Label2D.setHorizontalAlignment(HorizontalAlignment.Right), s),
            loaded, List.range(0, maxQueue()))

    // ─── 毎フレーム更新 ───────────────────────────────────────

    /// Game.flix の `process` redef から `NodeTag.Log` ノードに dispatch される(log は 1 個のみ)。
    /// drain → キューに積む → 新着があればタイマーを 0 に戻す → 5 秒判定 → 5 行へ反映 → 表示/非表示。
    /// scene 経由で自分(logPath/linePath)を書き換えるため、最後に最新ノードを取り直して返す。
    pub def process(delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {GameLogger.GameLogger, LogScene.State} =
        let drained = GameLogger.drainEntries();
        // P4-a: 状態は resource から読む（旧: NodeTag.Log ペイロード）。ノードは描画 view（Label/CanvasLayer）。
        let data = LogScene.State.get();
        let newQueue = enqueue(toLogEntries(drained), data#queue);
        // 新着があったフレームはタイマーを 0 に戻す(その後 tickIdle で進めるので当フレームでは消えない)。
        let idleReset = if (List.isEmpty(drained)) data#idleSince else Duration.zero();
        let (finalQueue, finalIdle) = tickIdle(newQueue, idleReset, delta);
        LogScene.State.put({queue = finalQueue, idleSince = finalIdle});
        let updated = scene
            |> renderLines(finalQueue)
            |> setOffsetX(if (List.isEmpty(finalQueue)) hiddenOffsetX() else homeOffsetX());
        match Scene.getEngineNode(path, updated) {
            case Some(latest) => (latest, updated)
            case None         => (node, updated)
        }

    /// `GameLogger.Entry`(古→新)を表示用 `LogEntry` へ写す。
    def toLogEntries(entries: List[GameLogger.Entry]): List[LogEntry] =
        List.map(e -> ({text = e#text, color = e#color}: LogEntry), entries)

    /// 各行 Label2D に queue の i 番目を反映する(無い行は空文字にして見えなくする)。
    def renderLines(queue: List[LogEntry], scene: Scene[NodeTag]): Scene[NodeTag] =
        List.foldLeft((s, i) -> {
            let (txt, color) = match List.nth(i, queue) {
                case Some(e) => (e#text, e#color)
                case None    => ("", blankColor())
            };
            Label2D.mapAt(linePath(i),
                label -> label |> Label2D.setText(txt) |> CanvasItem.setModulate(color), s)
        }, scene, List.range(0, maxQueue()))

    /// CanvasLayer の offset(x) を書き換えて帯ごと出し入れする(PhaseBannerScene と同じ手法)。
    def setOffsetX(offsetX: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        CanvasLayer.mapAt(logPath(), CanvasLayer.setOffset({x = offsetX, y = 0.0}), scene)

    /// 別 HUD(ターンスキップ等)がログ帯を背景として再利用するための一時オーバーライド。
    /// ログ帯を定位置に出しつつ本文 5 行を空にする(queue は保持)。毎フレーム呼ぶ前提で、
    /// 呼ばれなくなれば次フレームの `process`(本シーンは先に走る)が queue から復帰させる。
    /// 同フレーム内で LogScene.process の後に適用される呼び出し元から使うこと(上書きが効くように)。
    pub def holdForOverlay(scene: Scene[NodeTag]): Scene[NodeTag] =
        let shown = setOffsetX(homeOffsetX(), scene);
        List.foldLeft((s, i) -> Label2D.mapAt(linePath(i), Label2D.setText(""), s),
                      shown, List.range(0, maxQueue()))
}
