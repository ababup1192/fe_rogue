/// PhaseBannerScene — ターン切替を知らせる中央バナー
///
/// ターンが「味方 ⇄ 敵」で切り替わった瞬間だけ、画面中央に半透明の帯と大きめの文字で
/// 「プレイヤーフェーズ」「エネミーフェーズ」を一瞬だけ出す（ファイアーエムブレム流）。
/// 帯は左から横に滑り込み、少し止まってから右へ滑り抜けて消える。
///
/// 自走モデル: 専用ノードの `process` が毎フレーム今のフェーズを見て、前フレームと
/// 「味方か敵か」が変わったらバナーを出す。`PhaseTransitions` 等の遷移関数には手を入れない
/// （味方ターン中のサブフェーズ移動でも `PlayerCursor` には何度も入るため、遷移関数にフックを
/// 足すと味方ターン中に何度も再表示されてしまう。トップレベルの「敵ターンか否か」の変化だけを
/// 見るのが正しい単一の判定点）。
///
/// 演出中にターンが変わっても帯は上書きしない。「次に見せたいターン」を控えておき、今の帯が
/// 出終わってから控えを再生する。これにより、敵が一瞬で行動を終える（敵がいない・その場待機）
/// 短い敵ターンでも「エネミーフェーズ」→「プレイヤーフェーズ」が必ず順番に最後まで見える。
///
/// 文字は alpha を持たず（`DamagePopupScene` 参照）、描画パス上で親 CanvasLayer の可視性も
/// 見ない（`BattlePanelScene` 参照）ため、フェードや visible 切替には頼らない。代わりに
/// CanvasLayer の offset(x) を動かして帯ごと画面外へ出し入れする（スライド演出と兼用）。
///
/// ノード構造（drawLayer=5。戦闘予報=3 / ユニット情報=4 より前面）:
///   PhaseBanner (CanvasLayer, NodeTag.PhaseBanner(BannerData))   ← offset(x) を動かして出し入れ
///     ├─ band (ColorRect, 画面幅 × bandHeight の半透明帯, NoTag)
///     └─ text (Label2D, 中央寄せ・大きめフォント, NoTag)
mod PhaseBannerScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// バナーの演出段階。
    ///   Idle     — 非表示（帯は画面外で待機）
    ///   SlideIn  — 左から中央へ滑り込み中
    ///   Hold     — 中央で静止して見せている最中
    ///   SlideOut — 中央から右へ滑り抜け中
    pub enum Stage with Eq, ToString {
        case Idle
        case SlideIn
        case Hold
        case SlideOut
    }

    /// CanvasLayer に紐づくバナーの状態。
    /// `stage`    — 今の演出段階。
    /// `elapsed`  — 今の段階に入ってからの経過時間（段階ごとに 0 から数え直す）。
    /// `wasEnemy` — 前フレームに観測した「敵ターンだったか」。None は未観測（起動直後）で、
    ///              最初のフレームで必ず味方バナーを出すための初期値。
    /// `pending`  — 演出中に新しいターンへ切り替わったときに「次に見せたいターン」を覚えておく枠。
    ///              今の帯を最後まで再生したいので即座には出さず、Idle に戻ってから出す。
    ///              None は保留なし。Some(敵ターンか) が次に出すバナー。
    pub type alias BannerData = {
        stage    = Stage,
        elapsed  = Duration.Duration,
        wasEnemy = Option[Bool],
        pending  = Option[Bool]
    }

    /// `step` の結果。
    /// `data`      — 次フレームへ持ち越す新しい状態。
    /// `offsetX`   — このフレームで CanvasLayer に与える横オフセット（画面外〜中央〜画面外）。
    /// `triggered` — このフレームで新しいバナーが始まったら Some(敵ターンか)。始まらなければ None。
    ///               Some のときだけ呼び出し側が文字と帯の色を差し替える。
    pub type alias StepResult = {
        data      = BannerData,
        offsetX   = Float64,
        triggered = Option[Bool]
    }

    /// `advance` の結果（状態と横オフセットの組）。
    type alias AdvanceResult = { data = BannerData, offsetX = Float64 }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def rootName(): String = "PhaseBanner"
    def bandName(): String = "band"
    def textName(): String = "text"

    def rootPath(): NodePath = rootName() :: Nil
    def bandPath(): NodePath = rootName() :: bandName() :: Nil
    def textPath(): NodePath = rootName() :: textName() :: Nil

    /// fontManifest で登録した name と一致させる（他 HUD と同じ "ui"）。
    def fontName(): String = "ui"

    /// 描画レイヤー。戦闘予報(3) / ユニット情報(4) より前面に出す。
    def drawLayer(): Int32 = 5

    /// 同一レイヤー内の描画順。帯 < 文字。
    def bandZIndex(): Int32 = 0
    def textZIndex(): Int32 = 1

    /// 帯の高さ（論理 px）。
    def bandHeight(): Float64 = 22.0

    /// 文字の表示フォントサイズ（論理 px）。帯の中に収まる控えめな大きさ。
    def fontSize(): Float64 = 8.9

    /// 帯の半透明度。
    def bandAlpha(): Float32 = 0.6f32

    /// 味方ターンの帯色（濃紺。HP バーの味方=青に準拠）。
    def playerColor(): Color = {r = 0.10f32, g = 0.18f32, b = 0.45f32}
    /// 敵ターンの帯色（濃赤。HP バーの敵=赤に準拠）。
    def enemyColor(): Color = {r = 0.45f32, g = 0.12f32, b = 0.12f32}
    /// 文字色（白）。
    def textColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// 帯に出す文言。
    def playerText(): String = "プレイヤーフェーズ"
    def enemyText(): String = "エネミーフェーズ"

    /// 演出開始時に鳴らすフェーズ切替音（project.json の "sounds" に登録した name と一致させる）。
    def phaseChangeSound(): String = "phase_change"

    /// 滑り込み / 静止 / 滑り抜けの各時間（合計 ≈ 2.4 秒）。
    def slideInDuration(): Duration.Duration = Duration.millis(440)
    def holdDuration(): Duration.Duration = Duration.millis(1520)
    def slideOutDuration(): Duration.Duration = Duration.millis(440)

    /// 横オフセットの基準位置（論理 px）。
    ///   offStartX — 滑り込みの開始位置（画面左外）。Idle 中の待機位置でもある。
    ///   homeX     — 中央（帯が画面いっぱいに収まる位置）。
    ///   offEndX   — 滑り抜けの終了位置（画面右外）。
    /// 帯は画面幅（designWidth=170）ぶんの横幅なので、Idle/SlideOut で確実に画面外へ
    /// 消えるよう画面幅より大きく振る。ここが画面幅より小さいと、待機中の帯が左端に
    /// 数 px はみ出して「変な位置に半透明帯が残る」不具合になる（128→170 に合わせ ±200 へ）。
    def offStartX(): Float64 = -200.0
    def homeX(): Float64 = 0.0
    def offEndX(): Float64 = 200.0

    /// 起動直後の状態。`wasEnemy = None` なので最初のフレームで味方バナーが出る。
    def initialData(): BannerData =
        {stage = Stage.Idle, elapsed = Duration.zero(), wasEnemy = None, pending = None}

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// 画面 HUD の最前面にバナー一式を追加する。`GameLifecycle.buildPlayingScene` の UI 群で
    /// 1 回だけ呼ぶ。帯は初期状態では画面左外（offStartX）に置いて見えないようにする。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        let screenWidth = Int32.toFloat64(Game.designWi());
        let screenHeight = Int32.toFloat64(Game.designHi());
        let bandTopY = (screenHeight - bandHeight()) / 2.0;
        let layer = CanvasLayer.make(drawLayer())
            |> CanvasLayer.setOffset({x = offStartX(), y = 0.0});
        let band = ColorRect.make({x = screenWidth, y = bandHeight()}, playerColor())
            |> ColorRect.setAlpha(bandAlpha())
            |> Node2D.setPosition({x = 0.0, y = bandTopY})
            |> CanvasItem.setZIndex(bandZIndex());
        let text = Label2D.make(playerText(), atlas, fontSize())
            |> Node2D.setPosition({x = screenWidth / 2.0, y = screenHeight / 2.0})
            |> Label2D.setHorizontalAlignment(HorizontalAlignment.Center)
            |> Label2D.setVerticalAlignment(VerticalAlignment.Center)
            |> CanvasItem.setModulate(textColor())
            |> CanvasItem.setZIndex(textZIndex());
        scene
            |> Scene.addNode(rootName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.PhaseBanner(initialData())))
            |> Scene.addChild(rootName(), bandName(),
                EngineNode.ColorRectWithState(band, NodeTag.NoTag))
            |> Scene.addChild(rootName(), textName(),
                EngineNode.Label2DWithState(text, NodeTag.NoTag))

    // ────────────────────────────────────────────────────────
    // (D) 問い合わせ
    // ────────────────────────────────────────────────────────

    /// バナーが表示中（滑り込み・静止・滑り抜けのいずれか）か。Idle（非表示）なら false。
    /// 敵ターンの進行役（EnemyTurnDriverScene）が「エネミーフェーズの帯が出ている間は
    /// 敵を行動させない」ために参照する。
    pub def isBusy(scene: Scene[NodeTag]): Bool =
        match Scene.getState(rootPath(), scene) {
            case Some(NodeTag.PhaseBanner(data)) => data#stage != Stage.Idle
            case _                               => false
        }

    // ────────────────────────────────────────────────────────
    // (E) ロジック（純粋）
    // ────────────────────────────────────────────────────────

    /// 帯が観測する「今は敵ターンか」を返す。通常は phase == EnemyTurn だが、
    /// `LevelUpView` はターンを止めるモーダル割り込みなので、その間は実フェーズが
    /// EnemyTurn から外れても **直前の認識(wasEnemy)を維持** してターン変化を観測しない。
    /// こうしないと、敵ターン中の反撃でレベルアップした瞬間にフェーズが
    /// EnemyTurn → LevelUpView になり「プレイヤーフェーズ」帯がパネルに被って出てしまい、
    /// パネルを閉じて EnemyTurn に戻ると「エネミーフェーズ」帯が二重に出る。
    pub def perceivedIsEnemy(phase: TurnPhase.Phase, wasEnemy: Option[Bool]): Bool =
        if (phase == TurnPhase.Phase.LevelUpView)
            Option.getWithDefault(false, wasEnemy)
        else
            phase == TurnPhase.Phase.EnemyTurn

    /// 1 フレーム分の状態更新（副作用なし。テスト対象）。
    /// 今のフェーズが「敵ターンか(isEnemy)」を受け取り、前フレームと変わっていればそのターンを
    /// 「次に見せたいターン」として控える。演出していない（Idle）ときだけ控えを取り出して
    /// 滑り込みを開始する。演出中はそのまま最後まで進めて上書きしない（FE 流に必ず順番に見せる）。
    /// 続いて今の段階を経過時間で進め、帯に与える横オフセットを返す。
    pub def step(data: BannerData, isEnemy: Bool, dt: Duration.Duration): StepResult =
        let observedChange = data#wasEnemy != Some(isEnemy);
        // 新しい変化があればそれを最優先で控える。なければ前回の控えを維持する。
        let queued =
            if (observedChange) Some(isEnemy)
            else data#pending;
        // 観測したターンは常に記録して、同じ切り替わりを二重に拾わないようにする。
        let observed = {wasEnemy = Some(isEnemy) | data};
        if (data#stage == Stage.Idle)
            // 演出していない。控えがあれば今すぐ開始し、そのフレームだけ triggered を返す。
            match queued {
                case None         =>
                    let advanced = advance({pending = None | observed}, dt);
                    {data = advanced#data, offsetX = advanced#offsetX, triggered = None}
                case Some(target) =>
                    let started = {stage = Stage.SlideIn, elapsed = Duration.zero(),
                                   wasEnemy = Some(isEnemy), pending = None};
                    let advanced = advance(started, dt);
                    {data = advanced#data, offsetX = advanced#offsetX, triggered = Some(target)}
            }
        else
            // 演出中は上書きしない。今の帯を最後まで進め、見せたいターンは控えに残す。
            let advanced = advance({pending = queued | observed}, dt);
            {data = advanced#data, offsetX = advanced#offsetX, triggered = None}

    /// 今の段階を `dt` 分進めて、新しい状態とこのフレームの横オフセットを返す。
    /// 各段階は時間切れで次の段階へ移り、経過時間を 0 に戻す。
    def advance(data: BannerData, dt: Duration.Duration): AdvanceResult =
        match data#stage {
            case Stage.Idle =>
                // 非表示。画面左外に置いたまま待つ。
                {data = data, offsetX = offStartX()}
            case Stage.SlideIn =>
                let elapsed = Duration.add(data#elapsed, dt);
                if (isOver(elapsed, slideInDuration()))
                    {data = {stage = Stage.Hold, elapsed = Duration.zero() | data},
                     offsetX = homeX()}
                else
                    let ratio = Duration.ratio(elapsed, slideInDuration());
                    {data = {elapsed = elapsed | data},
                     offsetX = lerp(offStartX(), homeX(), easeOut(ratio))}
            case Stage.Hold =>
                let elapsed = Duration.add(data#elapsed, dt);
                if (isOver(elapsed, holdDuration()))
                    {data = {stage = Stage.SlideOut, elapsed = Duration.zero() | data},
                     offsetX = homeX()}
                else
                    {data = {elapsed = elapsed | data}, offsetX = homeX()}
            case Stage.SlideOut =>
                let elapsed = Duration.add(data#elapsed, dt);
                if (isOver(elapsed, slideOutDuration()))
                    {data = {stage = Stage.Idle, elapsed = Duration.zero() | data},
                     offsetX = offEndX()}
                else
                    let ratio = Duration.ratio(elapsed, slideOutDuration());
                    {data = {elapsed = elapsed | data},
                     offsetX = lerp(homeX(), offEndX(), easeIn(ratio))}
        }

    /// 経過時間が段階の長さに達したか。
    def isOver(elapsed: Duration.Duration, total: Duration.Duration): Bool =
        Duration.toSeconds(elapsed) >= Duration.toSeconds(total)

    /// 線形補間。`ratio` が 0.0 で `startValue`、1.0 で `endValue`。
    def lerp(startValue: Float64, endValue: Float64, ratio: Float64): Float64 =
        startValue + (endValue - startValue) * ratio

    /// 入りはゆっくり減速（滑り込みの最後がふわっと止まる）。
    def easeOut(ratio: Float64): Float64 =
        1.0 - (1.0 - ratio) * (1.0 - ratio)

    /// 抜けはゆっくり加速（滑り抜けの最初がふわっと動き出す）。
    def easeIn(ratio: Float64): Float64 =
        ratio * ratio

    // ────────────────────────────────────────────────────────
    // (F) ロジック（毎フレーム・副作用あり）
    // ────────────────────────────────────────────────────────

    /// Game.flix の `process` redef から `NodeTag.PhaseBanner` ノードに対して dispatch される
    /// (バナーは 1 個のみなので 1 フレーム 1 回)。今のフェーズを `step` に渡して状態を進め、
    /// バナーが始まったフレームでは文字と帯色を差し替え、フェーズ切替音を鳴らし、横オフセットを反映する。
    /// 末尾で scene から self の最新ノードを取り直して返す（offset/state 更新が打ち消されないように）。
    pub def process(delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag]) \ {TurnPhase.State, GameEngine.Audio} =
        match node {
            case EngineNode.CanvasLayerWithState(_, NodeTag.PhaseBanner(data)) =>
                let phase = TurnPhase.State.get();
                // レベルアップ表示 (LevelUpView) 中は帯を画面外へ退避して隠し、state(stage/elapsed/
                // wasEnemy) は据え置く（step を呼ばず時間も進めない）。これで、進行中の帯はパネルの
                // 間だけ一時停止し、ウィンドウが閉じてから続きを再生する。まだ出していない遷移は
                // wasEnemy 据え置きで保留され、閉じてから出る。→「フェーズ帯がレベルアップ
                // ウィンドウに被る」のを防ぐ。
                if (phase == TurnPhase.Phase.LevelUpView) {
                    let next = setOffsetX(offStartX(), scene);
                    match Scene.getEngineNode(path, next) {
                        case Some(latest) => (latest, next)
                        case None         => (node, next)
                    }
                } else {
                    let isEnemy = perceivedIsEnemy(phase, data#wasEnemy);
                    let result = step(data, isEnemy, delta);
                    // 演出（帯の滑り込み）が始まったフレームの冒頭でフェーズ切替音を鳴らす。
                    match result#triggered {
                        case Some(_) => AudioStreamPlayer.play(phaseChangeSound())
                        case None    => ()
                    };
                    let next = scene
                        |> applyTrigger(result#triggered)
                        |> setOffsetX(result#offsetX)
                        |> setState(result#data);
                    match Scene.getEngineNode(path, next) {
                        case Some(latest) => (latest, next)
                        case None         => (node, next)
                    }
                }
            case _ => (node, scene)
        }

    /// バナーが始まったフレームだけ、ターンに応じた文字と帯色を差し替える。
    def applyTrigger(triggered: Option[Bool], scene: Scene[NodeTag]): Scene[NodeTag] =
        match triggered {
            case None          => scene
            case Some(isEnemy) =>
                let (text, color) =
                    if (isEnemy) (enemyText(), enemyColor())
                    else         (playerText(), playerColor());
                scene
                    |> Label2D.mapAt(textPath(), Label2D.setText(text))
                    |> setBandColor(color)
        }

    /// 帯（ColorRect）の色を差し替える。ColorRect には mapAt が無いので
    /// `Scene.mapEngineNode` + `EngineNode.mapColorRect` を使う（BattlePanelScene と同じ作法）。
    def setBandColor(color: Color, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(bandPath(),
            node -> EngineNode.mapColorRect(rect -> CanvasItem.setModulate(color, rect), node),
            scene)

    /// CanvasLayer の横オフセットを与えて、帯と文字をまとめて動かす。
    def setOffsetX(offsetX: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(rootPath(), node -> match node {
            case EngineNode.CanvasLayerWithState(layer, tag) =>
                EngineNode.CanvasLayerWithState(
                    CanvasLayer.setOffset({x = offsetX, y = 0.0}, layer), tag)
            case other => other
        }, scene)

    /// CanvasLayer に紐づくバナーの状態を書き戻す。
    def setState(data: BannerData, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(rootPath(), node -> match node {
            case EngineNode.CanvasLayerWithState(layer, NodeTag.PhaseBanner(_)) =>
                EngineNode.CanvasLayerWithState(layer, NodeTag.PhaseBanner(data))
            case other => other
        }, scene)
}
