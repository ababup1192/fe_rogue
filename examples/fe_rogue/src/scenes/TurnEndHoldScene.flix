/// TurnEndHoldScene — Shift（キーボード）/ ゲームパッド LB の長押しでターンエンドする中央ゲージ
///
/// プレイヤーターン中（PlayerCursor / GatherMove）に Shift を押し続けると、画面中央に
/// ゲージ＋「ターンエンド」テキストが出て 2 秒で満タンになり、満タン到達で「全員待機」
/// (= ActionMenuScene.turnEndShortcut → applyTurnEnd) を実行して敵ターンへ移る。
/// 途中で離すとゲージは消えてターン継続。短いタップではゲージを出さない
/// （`showDelaySeconds` 未満は非表示）ので、同じ Shift の既存「危険域トグル（タップ）」と併存する。
///
/// 自走モデル（PhaseBannerScene / ItemPickupPopupScene と同型）:
///   - 起動時に CanvasLayer を 1 つ常駐させる（`add`、初期は非表示）。
///   - 毎フレームの `process`（`dispatchTickables` 経由で ProcessT の effect が使える）が
///     Shift 押下を `isKeyPressed` でポーリングし、純粋 `step` で経過時間を進め、表示へ反映、
///     満タン到達フレームで 1 回だけターンエンドを発火する。
/// `LeftShift` はキーボード Shift とゲームパッド LB に統一マップ済み（engine 側）なので両対応。
///
/// ノード構造（drawLayer=7。ItemPickup=6 / PhaseBanner=5 より前面）:
///   TurnEndHoldGauge (CanvasLayer, NodeTag.HoldGauge(GaugeData))
///     ├─ window (Panel, 画面中央, NoTag)
///     ├─ text   (Label2D "ターンエンド", 中央寄せ, NoTag)
///     └─ bar    (ProgressBar, 中央, NoTag)   ← value = 0..1 の充填率
mod TurnEndHoldScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// CanvasLayer に紐づくゲージの状態。
    /// `elapsed`  — 連続して押している経過時間（離すと 0 に戻す）。
    /// `consumed` — 満タンで一度発火したら true。離すまで再発火させない（押しっぱなしの連発防止）。
    pub type alias GaugeData = {
        elapsed  = Duration.Duration,
        consumed = Bool
    }

    /// `step` の結果。
    /// `data`    — 次フレームへ持ち越す新しい状態。
    /// `ratio`   — ゲージ充填率 0.0〜1.0。
    /// `visible` — ゲージ一式を表示するか。
    /// `fire`    — このフレームでターンエンドを発火するなら true（満タン到達フレームのみ）。
    pub type alias StepResult = {
        data    = GaugeData,
        ratio   = Float64,
        visible = Bool,
        fire    = Bool
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def rootName(): String = "TurnEndHoldGauge"
    def windowName(): String = "window"
    def textName(): String = "text"
    def barName(): String = "bar"

    def rootPath(): NodePath = rootName() :: Nil
    def windowPath(): NodePath = rootName() :: windowName() :: Nil
    def textPath(): NodePath = rootName() :: textName() :: Nil
    def barPath(): NodePath = rootName() :: barName() :: Nil

    /// 他 HUD と同じフォント。
    def fontName(): String = "ui"

    /// ターンエンド発火時の効果音（gatherShortcut と同じ "confirm"）。
    def fireSound(): String = "confirm"

    /// 描画レイヤー。アイテム取得ポップアップ(6)より前面。
    def drawLayer(): Int32 = 7

    /// 満タンまでの長押し秒数。
    def fillSeconds(): Float64 = 2.0
    /// この秒数を超えてからゲージを表示する（短いタップでチラ見えさせない）。
    def showDelaySeconds(): Float64 = 0.3

    /// 中央テキスト。
    def labelText(): String = "ターンエンド"
    def fontSize(): Float64 = 5.2

    /// レイアウト（設計解像度 170×128、中央 = 85×64）。
    def windowWidth(): Float64 = 86.0
    def windowHeight(): Float64 = 30.0
    def barSize(): Vec2.Vec2 = {x = 70.0, y = 7.0}
    def textCenterY(): Float64 = 58.0
    def barTopY(): Float64 = 64.0

    /// 色・不透明度。窓は固定の不透明度で出し、表示/非表示は visible で切り替える。
    def windowBgColor(): Color = {r = 0.05f32, g = 0.07f32, b = 0.12f32}
    def windowBgAlpha(): Float32 = 0.85f32
    def windowBorderAlpha(): Float32 = 0.95f32
    def borderColor(): Color = UITheme.white()
    def borderWidth(): Int32 = 1
    def textColor(): Color = UITheme.white()
    def barFillColor(): Color = {r = 0.95f32, g = 0.7f32, b = 0.2f32}
    def barBgColor(): Color = {r = 0.0f32, g = 0.0f32, b = 0.0f32}

    /// 起動直後の状態（経過 0・未発火）。
    def initialData(): GaugeData =
        {elapsed = Duration.zero(), consumed = false}

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// 画面 HUD の最前面にゲージ一式を追加する。`GameLifecycle.buildPlayingScene` で 1 回だけ呼ぶ。
    /// 初期は非表示。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        let sw = Int32.toFloat64(Game.designWi());
        let sh = Int32.toFloat64(Game.designHi());
        let layer = CanvasLayer.make(drawLayer());
        let window = Panel.make({x = windowWidth(), y = windowHeight()}, windowBgColor())
            |> Panel.setBorderColor(borderColor())
            |> Panel.setBorderWidth(borderWidth())
            |> Panel.setBackgroundAlpha(windowBgAlpha())
            |> Panel.setBorderAlpha(windowBorderAlpha())
            |> Node2D.setPosition({x = (sw - windowWidth()) / 2.0,
                                    y = (sh - windowHeight()) / 2.0})
            |> CanvasItem.setVisible(false);
        let text = Label2D.make(labelText(), atlas, fontSize())
            |> Node2D.setPosition({x = sw / 2.0, y = textCenterY()})
            |> Label2D.setHorizontalAlignment(HorizontalAlignment.Center)
            |> Label2D.setVerticalAlignment(VerticalAlignment.Center)
            |> CanvasItem.setModulate(textColor())
            |> CanvasItem.setZIndex(1)
            |> CanvasItem.setVisible(false);
        let bar = ProgressBar.make(barSize(), 1.0, barFillColor())
            |> ProgressBar.setBackgroundColor(barBgColor())
            |> ProgressBar.setBorderColor(borderColor())
            |> ProgressBar.setBorderWidth(borderWidth())
            |> ProgressBar.setValue(0.0)
            |> Node2D.setPosition({x = (sw - barSize()#x) / 2.0, y = barTopY()})
            |> CanvasItem.setVisible(false);
        scene
            |> Scene.addNode(rootName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.HoldGauge(initialData())))
            |> Scene.addChild(rootName(), windowName(),
                EngineNode.PanelWithState(window, NodeTag.NoTag))
            |> Scene.addChild(rootName(), textName(),
                EngineNode.Label2DWithState(text, NodeTag.NoTag))
            |> Scene.addChild(rootName(), barName(),
                EngineNode.ProgressBarWithState(bar, NodeTag.NoTag))

    // ────────────────────────────────────────────────────────
    // (D) ロジック（純粋・テスト対象）
    // ────────────────────────────────────────────────────────

    /// 1 フレーム分の状態更新（副作用なし）。
    ///   - `active`（対象フェーズ）かつ `held`（Shift 押下）でなければ即リセット（経過 0・非表示）。
    ///   - 発火済み(`consumed`)なら満タン表示のまま再発火しない。
    ///   - 経過が `fillSeconds` に達したフレームだけ `fire=true`・`consumed=true`。
    ///   - 途中は充填率を返し、`showDelaySeconds` を超えてから表示する。
    pub def step(data: GaugeData, active: Bool, held: Bool, dt: Duration.Duration): StepResult =
        if (not (active and held))
            {data = initialData(), ratio = 0.0, visible = false, fire = false}
        else {
            let e = Duration.add(data#elapsed, dt);
            let secs = Duration.toSeconds(e);
            if (data#consumed)
                {data = {elapsed = e, consumed = true}, ratio = 1.0, visible = true, fire = false}
            else if (secs >= fillSeconds())
                {data = {elapsed = e, consumed = true}, ratio = 1.0, visible = true, fire = true}
            else
                {data = {elapsed = e, consumed = false},
                 ratio = secs / fillSeconds(),
                 visible = secs >= showDelaySeconds(),
                 fire = false}
        }

    // ────────────────────────────────────────────────────────
    // (E) ロジック（毎フレーム・副作用あり）
    // ────────────────────────────────────────────────────────

    /// Game.flix の `process` redef から `NodeTag.HoldGauge` ノードに dispatch される（1 個のみ）。
    /// Shift 押下を読み、`step` で進め、表示へ反映し、満タン到達フレームでターンエンドを発火する。
    /// 末尾で scene から self の最新ノードを取り直して返す（更新が打ち消されないように）。
    pub def process(delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {GameEngine.Game, GameEngine.Audio, GameLogger.GameLogger,
                       EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State} =
        match node {
            case EngineNode.CanvasLayerWithState(_, NodeTag.HoldGauge(data)) =>
                let phase = TurnPhase.State.get();
                // 対象は素のカーソル中と集合移動中のみ。ターン切替バナー表示中は無効。
                let inPhase = phase == TurnPhase.Phase.PlayerCursor
                                or phase == TurnPhase.Phase.GatherMove;
                let active = inPhase and not PhaseBannerScene.isBusy(scene);
                let held = GameEngine.Game.isKeyPressed(GameEngine.Key.LeftShift);
                let result = step(data, active, held, delta);
                let shown = scene
                    |> applyAppearance(result#ratio, result#visible)
                    |> setState(result#data);
                let next =
                    if (result#fire) {
                        AudioStreamPlayer.play(fireSound());
                        ActionMenuScene.turnEndShortcut(shown)
                    } else shown;
                match Scene.getEngineNode(path, next) {
                    case Some(latest) => (latest, next)
                    case None         => (node, next)
                }
            case _ => (node, scene)
        }

    /// 充填率と可視状態を窓・テキスト・バーへ反映する。
    def applyAppearance(ratio: Float64, visible: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> Panel.mapAt(windowPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(textPath(), CanvasItem.setVisible(visible))
            |> Scene.mapEngineNode(barPath(), n -> match n {
                case EngineNode.ProgressBarWithState(bar, tag) =>
                    EngineNode.ProgressBarWithState(
                        bar |> ProgressBar.setValue(ratio) |> CanvasItem.setVisible(visible), tag)
                case other => other
            })

    /// `case other => other` により、HoldGauge 以外の CanvasLayer の状態を壊さない。
    def setState(data: GaugeData, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(rootPath(), node -> match node {
            case EngineNode.CanvasLayerWithState(layer, NodeTag.HoldGauge(_)) =>
                EngineNode.CanvasLayerWithState(layer, NodeTag.HoldGauge(data))
            case other => other
        }, scene)
}
