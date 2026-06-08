/// PhaseBannerScene — ターン切替を知らせる中央バナー
///
/// ターンが「味方 ⇄ 敵」で切り替わった瞬間だけ、画面中央に半透明の帯と大きめの文字で
/// 「プレイヤーフェーズ」「エネミーフェーズ」を一瞬だけ出す（ファイアーエムブレム流）。
/// 帯は左から横に滑り込み、少し止まってから右へ滑り抜けて消える。
///
/// 自走モデル: 専用ノードの `process` が毎フレーム今のフェーズを見て、前フレームと
/// 「味方か敵か」が変わったときにバナーを出し直す。`PhaseTransitions` 等の遷移関数には
/// 手を入れない（味方ターン中のサブフェーズ移動でも `PlayerCursor` には何度も入るため、
/// 遷移関数にフックを足すと味方ターン中に何度も再表示されてしまう。トップレベルの
/// 「敵ターンか否か」の変化だけを見るのが正しい単一の判定点）。
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
    pub type alias BannerData = {
        stage    = Stage,
        elapsed  = Duration.Duration,
        wasEnemy = Option[Bool]
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
    def fontSize(): Float64 = 10.5

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

    /// 滑り込み / 静止 / 滑り抜けの各時間（合計 ≈ 2.4 秒）。
    def slideInDuration(): Duration.Duration = Duration.millis(440)
    def holdDuration(): Duration.Duration = Duration.millis(1520)
    def slideOutDuration(): Duration.Duration = Duration.millis(440)

    /// 横オフセットの基準位置（論理 px）。
    ///   offStartX — 滑り込みの開始位置（画面左外）。Idle 中の待機位置でもある。
    ///   homeX     — 中央（帯が画面いっぱいに収まる位置）。
    ///   offEndX   — 滑り抜けの終了位置（画面右外）。
    /// 画面幅(128)より大きく振って、帯（画面幅ぶん）が確実に画面外へ消えるようにする。
    def offStartX(): Float64 = -140.0
    def homeX(): Float64 = 0.0
    def offEndX(): Float64 = 140.0

    /// 起動直後の状態。`wasEnemy = None` なので最初のフレームで味方バナーが出る。
    def initialData(): BannerData =
        {stage = Stage.Idle, elapsed = Duration.zero(), wasEnemy = None}

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
    // (D) ロジック（純粋）
    // ────────────────────────────────────────────────────────

    /// 1 フレーム分の状態更新（副作用なし。テスト対象）。
    /// 今のフェーズが「敵ターンか(isEnemy)」を受け取り、前フレームと変わっていれば
    /// 滑り込みをやり直す。続いて今の段階を経過時間で進め、帯に与える横オフセットを返す。
    pub def step(data: BannerData, isEnemy: Bool, dt: Duration.Duration): StepResult =
        let changed = data#wasEnemy != Some(isEnemy);
        // ターンが切り替わった（または起動直後）なら滑り込みを先頭からやり直す。
        let restarted =
            if (changed)
                {stage = Stage.SlideIn, elapsed = Duration.zero(), wasEnemy = Some(isEnemy)}
            else
                data;
        let advanced = advance(restarted, dt);
        {data = advanced#data,
         offsetX = advanced#offsetX,
         triggered = if (changed) Some(isEnemy) else None}

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
    // (D) ロジック（毎フレーム・副作用あり）
    // ────────────────────────────────────────────────────────

    /// Game.flix の `process` redef から `NodeTag.PhaseBanner` ノードに対して dispatch される
    /// (バナーは 1 個のみなので 1 フレーム 1 回)。今のフェーズを `step` に渡して状態を進め、
    /// バナーが始まったフレームでは文字と帯色を差し替え、横オフセットを反映する。
    /// 末尾で scene から self の最新ノードを取り直して返す（offset/state 更新が打ち消されないように）。
    pub def process(delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag]) \ TurnPhase.State =
        match node {
            case EngineNode.CanvasLayerWithState(_, NodeTag.PhaseBanner(data)) =>
                let isEnemy = TurnPhase.State.get() == TurnPhase.Phase.EnemyTurn;
                let result = step(data, isEnemy, delta);
                let next = scene
                    |> applyTrigger(result#triggered)
                    |> setOffsetX(result#offsetX)
                    |> setState(result#data);
                match Scene.getEngineNode(path, next) {
                    case Some(latest) => (latest, next)
                    case None         => (node, next)
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
