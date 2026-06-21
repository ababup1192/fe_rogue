/// ItemPickupPopupScene — アイテム取得を知らせる中央ポップアップ
///
/// 床のアイテムを拾った瞬間に、画面中央のウィンドウへ「○○を手に入れた」を出し、
/// フェードイン → 少し表示 → フェードアウトで消す。あわせて取得音を鳴らす。
///
/// 自走モデル（PhaseBannerScene と同型）:
///   - 起動時に CanvasLayer のウィンドウを1つ常駐させる（`add`、初期は非表示）。
///   - 拾った瞬間に `show(itemName, scene)`（純粋・effect なし）で文言をセットし、フェードを
///     先頭から開始し、「取得音を鳴らす予約」を立てる。
///   - 毎フレームの `process`（`dispatchTickables` 経由で `GameEngine.Audio` が使える）が、
///     予約があれば1回だけ取得音を鳴らし、フェード（窓 alpha・文字色・可視）を進める。
/// この分担により、取得処理（ActionMenuScene.addPickedItem）の effect 行を増やさずに済む。
///
/// 文字のフェードについて:
///   エンジンは Label2D の alpha を持たない（glyph は常に不透明。`DamagePopupScene` 参照）。
///   そこで窓（Panel）は背景/枠の alpha で本当にフェードし、文字は modulate を
///   「窓の背景色 → 白」に補間し、薄い区間では非表示にして“フェードしているように”見せる。
///
/// ノード構造（drawLayer=6。PhaseBanner=5 より前面）:
///   ItemPickupPopup (CanvasLayer, NodeTag.ItemPickupPopup(PopupData))
///     ├─ window (Panel, 画面中央の約40%サイズ, NoTag)   ← 背景/枠の alpha でフェード
///     └─ text   (Label2D, 中央寄せ, NoTag)               ← modulate 補間 + 可視ゲートで擬似フェード
mod ItemPickupPopupScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// 演出段階。
    ///   Idle    — フェード終了後に戻る終端状態。ratio=0 で窓も非表示。`show` で FadeIn へ抜け出す。
    ///   FadeIn  — ratio が 0→1 に上がる過渡状態。完了即 Hold へ。
    ///   Hold    — ratio=1.0 固定のまま holdDuration だけ待つ（補間は不要なので elapsed だけ加算）。
    ///   FadeOut — ratio が 1→0 に下がる過渡状態。完了即 Idle へ戻り窓を消す。
    pub enum Stage with Eq, ToString {
        case Idle
        case FadeIn
        case Hold
        case FadeOut
    }

    /// CanvasLayer に紐づくポップアップの状態。
    /// `stage`        — 今の演出段階。
    /// `elapsed`      — 今の段階に入ってからの経過時間（段階ごとに 0 から数え直す）。
    /// `soundPending` — `show` で true。`process` が取得音を1回鳴らしたら false にする。
    pub type alias PopupData = {
        stage        = Stage,
        elapsed      = Duration.Duration,
        soundPending = Bool
    }

    /// `step` の結果。
    /// `data`      — 次フレームへ持ち越す新しい状態。
    /// `ratio`     — 表示の濃さ 0.0（非表示）〜1.0（はっきり）。窓 alpha と文字の見え方に使う。
    /// `playSound` — このフレームで取得音を鳴らすなら true（予約を消費したフレームだけ true）。
    pub type alias StepResult = {
        data      = PopupData,
        ratio     = Float64,
        playSound = Bool
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def rootName(): String = "ItemPickupPopup"
    def windowName(): String = "window"
    def textName(): String = "text"

    def rootPath(): NodePath = rootName() :: Nil
    def windowPath(): NodePath = rootName() :: windowName() :: Nil
    def textPath(): NodePath = rootName() :: textName() :: Nil

    /// fontManifest で登録した name と一致させる（他 HUD と同じ "ui"）。
    def fontName(): String = "ui"

    /// 取得音（project.json の "sounds" に登録した name と一致させる）。
    def getItemSound(): String = "get_item"

    /// 描画レイヤー。ターン切替バナー(5)より前面に出す。
    def drawLayer(): Int32 = 6

    /// 文字の描画順（窓より前）。
    def textZIndex(): Int32 = 1

    /// 文字の表示フォントサイズ（論理 px）。メニューのフォント(4)の約1.3倍。
    def fontSize(): Float64 = 5.2

    /// ウィンドウの大きさ。中央に置く。縦の余白は最小限にして、
    /// 高さ = フォント + 上下 5px ずつ（= fontSize + 10）。
    def windowWidth(): Float64 = 100.0
    def windowHeight(): Float64 = fontSize() + 10.0

    /// 窓の背景色（濃紺）／枠色（白）／枠幅。
    def windowBgColor(): Color = {r = 0.05f32, g = 0.07f32, b = 0.12f32}
    def borderColor(): Color = UITheme.white()
    def borderWidth(): Float64 = 1.0

    /// 文字色（はっきり表示時 = 白）。
    def textColor(): Color = UITheme.white()

    /// フェードのピーク不透明度（背景／枠）。
    def maxBgAlpha(): Float64 = 0.85
    def maxBorderAlpha(): Float64 = 0.95

    /// 文字を表示し始める濃さのしきい値。これ未満では文字を出さない
    /// （窓がほぼ透明な区間で不透明な文字だけが浮くのを防ぐ）。
    def textShowThreshold(): Float64 = 0.35

    /// 浮かび上がり / 表示保持 / 消える の各時間。
    def fadeInDuration(): Duration.Duration = Duration.millis(300)
    def holdDuration(): Duration.Duration = Duration.millis(1100)
    def fadeOutDuration(): Duration.Duration = Duration.millis(400)

    /// 起動直後の状態（非表示・音予約なし）。
    def initialData(): PopupData =
        {stage = Stage.Idle, elapsed = Duration.zero(), soundPending = false}

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// 画面 HUD の最前面にポップアップ一式を追加する。`GameLifecycle.buildPlayingScene` の
    /// UI 群で1回だけ呼ぶ。初期は非表示（alpha 0・visible false）。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        let screenWidth = Int32.toFloat64(Game.designWi());
        let screenHeight = Int32.toFloat64(Game.designHi());
        let layer = CanvasLayer.make(drawLayer());
        let window = Panel.make({x = windowWidth(), y = windowHeight()}, windowBgColor())
            |> Panel.setBorderColor(borderColor())
            |> Panel.setBorderWidth(borderWidth())
            |> Panel.setBackgroundAlpha(0.0f32)
            |> Panel.setBorderAlpha(0.0f32)
            |> Node2D.setPosition({x = (screenWidth - windowWidth()) / 2.0,
                                    y = (screenHeight - windowHeight()) / 2.0})
            |> CanvasItem.setVisible(false);
        let text = Label2D.make("", atlas, fontSize())
            |> Node2D.setPosition({x = screenWidth / 2.0, y = screenHeight / 2.0})
            |> Label2D.setHorizontalAlignment(HorizontalAlignment.Center)
            |> Label2D.setVerticalAlignment(VerticalAlignment.Center)
            |> CanvasItem.setModulate(textColor())
            |> CanvasItem.setZIndex(textZIndex())
            |> CanvasItem.setVisible(false);
        scene
            |> Scene.addNode(rootName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.ItemPickupPopup(initialData())))
            |> Scene.addChild(rootName(), windowName(),
                EngineNode.PanelWithState(window, NodeTag.NoTag))
            |> Scene.addChild(rootName(), textName(),
                EngineNode.Label2DWithState(text, NodeTag.NoTag))

    // ────────────────────────────────────────────────────────
    // (D) 公開トリガー（純粋）
    // ────────────────────────────────────────────────────────

    /// アイテムを拾ったときに呼ぶ。文言を「${itemName}を手に入れた」にして、フェードを
    /// 先頭から開始し、取得音の予約を立てる。副作用は無く（音は `process` が鳴らす）、
    /// 既に表示中でも先頭からやり直す（拾い直しでも必ず最初から演出する）。
    pub def show(itemName: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        showWith("${itemName}を手に入れた", true, scene)

    /// 取得以外の通知（例: 「持ち物がいっぱいです」）を中央ポップアップに出す。
    /// 取得音は鳴らさず、フェードイン → 表示保持 → フェードアウトの演出だけ流す。
    pub def showMessage(text: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        showWith(text, false, scene)

    /// 「持ち物がいっぱいです」を中央ポップアップで知らせる薄いラッパ。
    pub def showFull(scene: Scene[NodeTag]): Scene[NodeTag] =
        showMessage("持ち物がいっぱいです", scene)

    /// 取得音だけを次フレームに予約する（中央ポップアップは出さない）。`show` と違い
    /// stage / text を触らないので、`process` が `get_item` を 1 回鳴らすだけ
    /// （`step` は stage に関わらず先頭で `soundPending` を消費して playSound を返す）。
    /// 移動着地の自動取得など「大きな通知は不要だが取得音は鳴らしたい」経路で使う。
    /// 純粋（音は process が鳴らす）。ポップアップ未登録の scene では no-op。
    pub def reserveGetItemSound(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(rootPath(), node -> match node {
            case EngineNode.CanvasLayerWithState(layer, NodeTag.ItemPickupPopup(d)) =>
                EngineNode.CanvasLayerWithState(layer,
                    NodeTag.ItemPickupPopup({soundPending = true | d}))
            case other => other
        }, scene)

    /// 文言と「取得音を鳴らすか」を受け取り、フェードを先頭から開始する共通処理。
    /// `playSound = true` のときだけ `process` が取得音を 1 回鳴らす。
    def showWith(text: String, playSound: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        let started: PopupData =
            {stage = Stage.FadeIn, elapsed = Duration.zero(), soundPending = playSound};
        scene
            |> Label2D.mapAt(textPath(), Label2D.setText(text))
            |> setState(started)

    // ────────────────────────────────────────────────────────
    // (E) ロジック（純粋）
    // ────────────────────────────────────────────────────────

    /// 1 フレーム分の状態更新（副作用なし。テスト対象）。
    /// 取得音の予約を消費し（`playSound`）、今の段階を経過時間で進めて、表示の濃さ `ratio` を返す。
    pub def step(data: PopupData, dt: Duration.Duration): StepResult =
        let playSound = data#soundPending;
        let cleared = {soundPending = false | data};
        match cleared#stage {
            case Stage.Idle =>
                {data = cleared, ratio = 0.0, playSound = playSound}
            case Stage.FadeIn =>
                let elapsed = Duration.add(cleared#elapsed, dt);
                if (isOver(elapsed, fadeInDuration()))
                    {data = {stage = Stage.Hold, elapsed = Duration.zero() | cleared},
                     ratio = 1.0, playSound = playSound}
                else
                    {data = {elapsed = elapsed | cleared},
                     ratio = easeOut(Duration.ratio(elapsed, fadeInDuration())),
                     playSound = playSound}
            case Stage.Hold =>
                let elapsed = Duration.add(cleared#elapsed, dt);
                if (isOver(elapsed, holdDuration()))
                    {data = {stage = Stage.FadeOut, elapsed = Duration.zero() | cleared},
                     ratio = 1.0, playSound = playSound}
                else
                    {data = {elapsed = elapsed | cleared}, ratio = 1.0, playSound = playSound}
            case Stage.FadeOut =>
                let elapsed = Duration.add(cleared#elapsed, dt);
                if (isOver(elapsed, fadeOutDuration()))
                    {data = {stage = Stage.Idle, elapsed = Duration.zero() | cleared},
                     ratio = 0.0, playSound = playSound}
                else
                    {data = {elapsed = elapsed | cleared},
                     ratio = 1.0 - easeIn(Duration.ratio(elapsed, fadeOutDuration())),
                     playSound = playSound}
        }

    /// `>=` なので、ちょうど total に達したフレームも「段階終了」とみなす（境界フレームを次段階に送らない）。
    def isOver(elapsed: Duration.Duration, total: Duration.Duration): Bool =
        Duration.toSeconds(elapsed) >= Duration.toSeconds(total)

    /// 出はゆっくり減速、消えはゆっくり加速（ふんわりしたフェード）。
    def easeOut(ratio: Float64): Float64 =
        1.0 - (1.0 - ratio) * (1.0 - ratio)
    def easeIn(ratio: Float64): Float64 =
        ratio * ratio

    // ────────────────────────────────────────────────────────
    // (F) ロジック（毎フレーム・副作用あり）
    // ────────────────────────────────────────────────────────

    /// Game.flix の `process` redef から `NodeTag.ItemPickupPopup` ノードに dispatch される
    /// (ポップアップは1個のみ)。`step` で状態を進め、予約があれば取得音を1回鳴らし、
    /// 表示の濃さ ratio を窓 alpha・文字色・可視へ反映する。
    /// 末尾で scene から self の最新ノードを取り直して返す（更新が打ち消されないように）。
    pub def process(delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag]) \ GameEngine.Audio =
        match node {
            case EngineNode.CanvasLayerWithState(_, NodeTag.ItemPickupPopup(data)) =>
                let result = step(data, delta);
                if (result#playSound) AudioStreamPlayer.play(getItemSound()) else ();
                let next = scene
                    |> applyAppearance(result#ratio)
                    |> setState(result#data);
                match Scene.getEngineNode(path, next) {
                    case Some(latest) => (latest, next)
                    case None         => (node, next)
                }
            case _ => (node, scene)
        }

    /// Label2D の glyph は CanvasItem の alpha に従わず常に不透明（モジュール doc L15-17 参照）。
    /// そのため窓と文字で別戦略を取る:
    ///   窓: 背景/枠の alpha = ratio × ピーク不透明度。ratio が 0 なら窓ごと非表示。
    ///   文字: しきい値以上で表示し、modulate を「窓の背景色 → 白」に補間（濃いほど白く＝読める）。
    def applyAppearance(ratio: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        let windowVisible = ratio > 0.0;
        let bgAlpha = toAlpha(ratio * maxBgAlpha());
        let borderAlpha = toAlpha(ratio * maxBorderAlpha());
        let textVisible = ratio >= textShowThreshold();
        let textTone = toAlpha(textColorRamp(ratio));
        let textModulate = lerpColor(windowBgColor(), textColor(), textTone);
        scene
            |> Panel.mapAt(windowPath(), window -> window
                |> CanvasItem.setVisible(windowVisible)
                |> Panel.setBackgroundAlpha(bgAlpha)
                |> Panel.setBorderAlpha(borderAlpha))
            |> Label2D.mapAt(textPath(), label -> label
                |> CanvasItem.setVisible(textVisible)
                |> CanvasItem.setModulate(textModulate))

    /// 文字の色補間量。表示しきい値で 0、ピークで 1 になるように 0..1 へ伸ばす
    /// （しきい値未満は toAlpha のクランプで 0 に丸められる）。
    def textColorRamp(ratio: Float64): Float64 =
        (ratio - textShowThreshold()) / (1.0 - textShowThreshold())

    /// 0.0〜1.0 の Float64 を Float32 の alpha 値へ（範囲外はクランプ）。
    def toAlpha(value: Float64): Float32 =
        Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, value)

    /// alpha チャネルは変更しない（Color 型は r/g/b のみ。RGB のみ補間）。
    def lerpColor(startColor: Color, endColor: Color, t: Float32): Color =
        {r = startColor#r + (endColor#r - startColor#r) * t,
         g = startColor#g + (endColor#g - startColor#g) * t,
         b = startColor#b + (endColor#b - startColor#b) * t}

    /// `case other => other` により、ItemPickupPopup 以外の NodeTag を持つ CanvasLayer があっても
    /// 状態を壊さない（将来ノードが増えた際の防御）。
    def setState(data: PopupData, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(rootPath(), node -> match node {
            case EngineNode.CanvasLayerWithState(layer, NodeTag.ItemPickupPopup(_)) =>
                EngineNode.CanvasLayerWithState(layer, NodeTag.ItemPickupPopup(data))
            case other => other
        }, scene)
}
