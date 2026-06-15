/// TurnEndHoldScene — Shift（キーボード）/ ゲームパッド LB の長押しでターンエンドする右下インジケータ
///
/// プレイヤーターン中（PlayerCursor / GatherMove）に Shift を押し続けると、右下のログ帯に
/// 「⭕ ターンスキップ」が出て 2 秒で満タンになり、満タン到達で「全員待機」
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
/// 見た目は右下のログ帯に重ねる 1 行「⭕ ターンスキップ」。専用の窓は作らず、表示中は
/// `LogScene.holdForOverlay` でログ帯を背景として再利用し（ログ本文は消す）、その上に左の小さな
/// 充填リング（長押しの進捗）とテキストを drawLayer=7（ログ layer=1 より前面）で重ねる。
///
/// ノード構造（drawLayer=7。ログ(1)/ItemPickup(6)/PhaseBanner(5) より前面）:
///   TurnEndHoldGauge (CanvasLayer, NodeTag.HoldGauge(GaugeData))
///     ├─ text   (Label2D "ターンスキップ", 左寄せ, NoTag)
///     ├─ ringBg (Arc2D, 全周リングの薄いトラック, NoTag)
///     └─ ringFg (Arc2D, 12 時起点に時計回りで伸びる充填弧, NoTag)  ← endAngle = 充填率を反映
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
    def textName(): String = "text"
    def ringBgName(): String = "ringBg"
    def ringFgName(): String = "ringFg"

    def rootPath(): NodePath = rootName() :: Nil
    def textPath(): NodePath = rootName() :: textName() :: Nil
    def ringBgPath(): NodePath = rootName() :: ringBgName() :: Nil
    def ringFgPath(): NodePath = rootName() :: ringFgName() :: Nil

    /// 他 HUD と同じフォント。
    def fontName(): String = "ui"

    /// ターンエンド発火時の効果音（gatherShortcut と同じ "confirm"）。
    def fireSound(): String = "confirm"

    /// 描画レイヤー。ログ(layer=1)より前面に敷いて、ログ帯の上に重ねて出す。
    def drawLayer(): Int32 = 7

    /// 満タンまでの長押し秒数。
    def fillSeconds(): Float64 = 2.0
    /// この秒数を超えてからゲージを表示する（短いタップでチラ見えさせない）。
    def showDelaySeconds(): Float64 = 0.3

    /// 行テキスト。ログ 1 行と同じフォントサイズで「⭕ ターンスキップ」風に出す。
    def labelText(): String = "ターンスキップ"
    def fontSize(): Float64 = 3.8

    /// レイアウト（設計解像度 170×128）。背景はログ帯（[64,110] サイズ [106,18]）を再利用し、
    /// その上に重ねる。行（リング + テキスト）の縦中心はログ帯 110..128 の中央付近。
    def lineCenterY(): Float64 = 119.0

    /// 左の「⭕」アイコン＝充填リング。ログ 1 行に収まる小径。
    def ringCenterX(): Float64 = 70.0
    def ringRadius(): Float64 = 3.0
    def ringWidth(): Float64 = 1.2
    /// 12 時方向（-π/2）を起点に、充填率に応じて時計回り（角度増加方向）へ伸ばす。
    def ringStartAngle(): Float64 = -1.5707963267948966
    /// テキストの左端 X（リングの右隣・左寄せ）。
    def textLeftX(): Float64 = 76.0

    def textColor(): Color = UITheme.white()
    /// リング背景トラック（薄いグレー）と前景の充填弧（黄橙）。
    def ringTrackColor(): Color = {r = 0.22f32, g = 0.24f32, b = 0.30f32}
    def ringTrackAlpha(): Float32 = 0.85f32
    def ringFillColor(): Color = {r = 0.95f32, g = 0.7f32, b = 0.2f32}

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
        let layer = CanvasLayer.make(drawLayer());
        let text = Label2D.make(labelText(), atlas, fontSize())
            |> Node2D.setPosition({x = textLeftX(), y = lineCenterY()})
            |> Label2D.setHorizontalAlignment(HorizontalAlignment.Left)
            |> Label2D.setVerticalAlignment(VerticalAlignment.Center)
            |> CanvasItem.setModulate(textColor())
            |> CanvasItem.setZIndex(1)
            |> CanvasItem.setVisible(false);
        let ringCenter = {x = ringCenterX(), y = lineCenterY()};
        // 背景トラックは全周リング。前景は初期 endAngle = startAngle（充填 0）で空。
        let ringBg = Arc2D.ring(ringRadius(), ringWidth(), ringTrackColor())
            |> Arc2D.setAlpha(ringTrackAlpha())
            |> Node2D.setPosition(ringCenter)
            |> CanvasItem.setZIndex(2)
            |> CanvasItem.setVisible(false);
        let ringFg = Arc2D.make(ringRadius(), ringWidth(),
                                ringStartAngle(), ringStartAngle(), ringFillColor())
            |> Node2D.setPosition(ringCenter)
            |> CanvasItem.setZIndex(3)
            |> CanvasItem.setVisible(false);
        scene
            |> Scene.addNode(rootName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.HoldGauge(initialData())))
            |> Scene.addChild(rootName(), textName(),
                EngineNode.Label2DWithState(text, NodeTag.NoTag))
            |> Scene.addChild(rootName(), ringBgName(),
                EngineNode.Arc2DWithState(ringBg, NodeTag.NoTag))
            |> Scene.addChild(rootName(), ringFgName(),
                EngineNode.Arc2DWithState(ringFg, NodeTag.NoTag))

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

    /// 充填率と可視状態をテキスト・リングへ反映する。表示中はログ帯を背景として再利用し
    /// （`LogScene.holdForOverlay` で帯を出してログ本文を消す）、その上にリング+テキストを重ねる。
    /// 前景弧は 12 時起点に充填率ぶんだけ時計回りで伸ばす（endAngle = startAngle + 2π·ratio）。
    /// 本シーンの process は LogScene.process より後に走る（root の追加順）ため上書きが効く。
    def applyAppearance(ratio: Float64, visible: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        let fillEnd = ringStartAngle() + Arc2D.tau() * ratio;
        let overlaid =
            scene
                |> Label2D.mapAt(textPath(), CanvasItem.setVisible(visible))
                |> Scene.mapEngineNode(ringBgPath(), CanvasItem.setVisible(visible))
                |> Scene.mapEngineNode(ringFgPath(), n ->
                    n |> EngineNode.mapArc2D(Arc2D.setEndAngle(fillEnd))
                      |> CanvasItem.setVisible(visible));
        if (visible) LogScene.holdForOverlay(overlaid) else overlaid

    /// `case other => other` により、HoldGauge 以外の CanvasLayer の状態を壊さない。
    def setState(data: GaugeData, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(rootPath(), node -> match node {
            case EngineNode.CanvasLayerWithState(layer, NodeTag.HoldGauge(_)) =>
                EngineNode.CanvasLayerWithState(layer, NodeTag.HoldGauge(data))
            case other => other
        }, scene)
}
