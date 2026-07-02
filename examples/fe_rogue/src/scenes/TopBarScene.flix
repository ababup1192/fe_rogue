/// TopBarScene — 画面上部の常設フェイズバー（旧 FloorLabelScene + PhaseBannerScene を統合）
///
/// 画面最上部に全幅の帯を出し、左にフロア（番号＋名前、例「1F 始まりの洞窟」）、右に現在
/// フェイズ（● 自軍フェイズ / PLAYER PHASE、敵は 敵軍フェイズ / ENEMY PHASE）を表示する。
/// 帯背景・下線・ドット・フェイズ和文を **自軍=青ベース / 敵軍=赤ベース** で着色する。
///
/// ターン切替時は **左から右へ色をワイプ** して切り替える（パッと切り替えない）:
///   base（band/underline/dot/text）は切替前フェイズの色のまま、sweep（bandSweep/underlineSweep）を
///   新フェイズ色で幅 0→全幅に伸ばす。伸び切ったら base を新フェイズに確定して sweep を畳む。
///
/// 敵ターン開始時は短い「間」（holdDuration）を置いてから敵が動き出す。`isBusy` が hold 中
/// true を返し、`EnemyTurnDriverScene` がそれを見て敵の行動開始を待つ（旧 PhaseBanner.isBusy 置換）。
///
/// 全幅・右側配置は固定 240px でなく `getViewportRect` の実幅で毎フレーム調整する。
///
/// ノード構造（layer=4）:
///   TopBar (CanvasLayer, NodeTag.TopBar(Data))
///     ├─ band / bandSweep            (Panel) 帯背景（base / ワイプ用オーバーレイ）
///     ├─ underline / underlineSweep  (Panel) 下線（base / ワイプ用オーバーレイ）
///     ├─ floorNum / floorName        (Label2D) フロア番号・名前（add 時設定）
///     ├─ phaseDot                    (Panel) フェイズ色のドット
///     └─ phaseJp / phaseEn           (Label2D) 「自軍/敵軍フェイズ」「PLAYER/ENEMY PHASE」
mod TopBarScene {

    /// CanvasLayer に紐づく状態。
    /// `shown`     — 現在 base に確定表示しているフェイズ（None=起動直後・未確定）。
    /// `animTarget`— ワイプ中の目標フェイズ（None=ワイプしていない）。
    /// `anim`      — ワイプの残り時間（0=非ワイプ）。
    /// `hold`      — 敵ターン開始の「間」の残り（>0 の間 isBusy=true）。
    pub type alias Data = {
        shown      = Option[Bool],
        animTarget = Option[Bool],
        anim       = Duration.Duration,
        hold       = Duration.Duration
    }

    def rootName(): String = "TopBar"
    def bandName(): String = "band"
    def bandSweepName(): String = "bandSweep"
    def underlineName(): String = "underline"
    def underlineSweepName(): String = "underlineSweep"
    def floorNumName(): String = "floorNum"
    def floorNameName(): String = "floorName"
    def phaseDotName(): String = "phaseDot"
    def phaseJpName(): String = "phaseJp"
    def phaseEnName(): String = "phaseEn"
    def gatherLabelName(): String = "gatherLabel"
    def gatherIconName(): String = "gatherIcon"

    /// B: render-from-World が HUD サブツリーを描く/隠す際の root（`RenderWorld.renderSubtree`/`hideNode` 用）。
    pub def rootPath(): NodePath = rootName() :: Nil
    def bandPath(): NodePath = rootName() :: bandName() :: Nil
    def bandSweepPath(): NodePath = rootName() :: bandSweepName() :: Nil
    def underlinePath(): NodePath = rootName() :: underlineName() :: Nil
    def underlineSweepPath(): NodePath = rootName() :: underlineSweepName() :: Nil
    def floorNumPath(): NodePath = rootName() :: floorNumName() :: Nil
    def floorNamePath(): NodePath = rootName() :: floorNameName() :: Nil
    def phaseDotPath(): NodePath = rootName() :: phaseDotName() :: Nil
    def phaseJpPath(): NodePath = rootName() :: phaseJpName() :: Nil
    def phaseEnPath(): NodePath = rootName() :: phaseEnName() :: Nil
    def gatherLabelPath(): NodePath = rootName() :: gatherLabelName() :: Nil
    def gatherIconPath(): NodePath = rootName() :: gatherIconName() :: Nil

    def fontName(): String = "ui"
    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/TopBarScene.scene.json")

    // ── レイアウト定数（design px。scene.json と一致させる）──
    def bandHeight(): Float64 = 7.5
    def underlineHeight(): Float64 = 0.6
    def rowCenterY(): Float64 = 3.75    // 右側ラベル/ドットの縦中心
    def rightMargin(): Float64 = 4.0
    def groupGap(): Float64 = 2.0
    def dotGap(): Float64 = 1.5
    def dotSize(): Float64 = 1.5
    /// 「集合中」左の再生(▶)マークの幅と、マーク先端と文字の間隔（scene.json の points と一致させる）。
    def gatherIconW(): Float64 = 2.3
    def gatherIconGap(): Float64 = 1.5

    /// 左→右ワイプの所要時間。
    def animDuration(): Duration.Duration = Duration.millis(500)
    /// 敵ターン開始に置く「間」。この間 isBusy=true で敵の行動開始を待たせる（ワイプ完了より少し長め）。
    def holdDuration(): Duration.Duration = Duration.millis(700)
    /// フェイズ切替時に鳴らす効果音（project.json "sounds" 登録名）。
    def phaseChangeSound(): String = "phase_change"

    // ── 配色（自軍=青 / 敵軍=赤）──
    def accentColor(isEnemy: Bool): Color =
        if (isEnemy) {r = 0.878f32, g = 0.275f32, b = 0.247f32}   // #e0463f
        else         {r = 0.184f32, g = 0.427f32, b = 0.941f32}   // #2f6df0
    def bandColor(isEnemy: Bool): Color =
        if (isEnemy) {r = 0.14f32, g = 0.055f32, b = 0.06f32}
        else         {r = 0.05f32, g = 0.08f32, b = 0.16f32}
    def phaseJpColor(isEnemy: Bool): Color =
        if (isEnemy) {r = 1.0f32, g = 0.78f32, b = 0.74f32}
        else         {r = 0.86f32, g = 0.92f32, b = 1.0f32}
    def phaseJpText(isEnemy: Bool): String = if (isEnemy) "敵軍フェイズ" else "自軍フェイズ"
    def phaseEnText(isEnemy: Bool): String = if (isEnemy) "ENEMY PHASE" else "PLAYER PHASE"

    /// scene.json を読み、フロア番号 (`floorLabel`) と名前 (`floorName`) を左に設定する。
    pub def add(floorLabel: String, floorName: String, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas,
                                       SceneLoader.constTagParser(NodeTag.NoTag), scene)
            |> Label2D.mapAt(floorNumPath(), Label2D.setText(floorLabel))
            |> Label2D.mapAt(floorNamePath(), Label2D.setText(floorName))
            // gatherLabel は scene.json で visible:false。集合(GatherMove)中のみ process で表示する。
            |> Scene.setState(rootPath(),
                NodeTag.TopBar(({shown = None, animTarget = None,
                                 anim = Duration.zero(), hold = Duration.zero()}: Data)))

    /// 敵ターンの「間」中か（hold>0）。`EnemyTurnDriverScene` が敵の行動開始待ちに参照する。
    pub def isBusy(scene: Scene[NodeTag]): Bool =
        match Scene.getState(rootPath(), scene) {
            case Some(NodeTag.TopBar(data)) => Duration.toSeconds(data#hold) > 0.0
            case _                          => false
        }

    /// バーが「敵ターン」を認識済みか（確定 or ワイプ目標が enemy）。0 体敵ターンの取りこぼし防止用。
    pub def hasObservedEnemy(scene: Scene[NodeTag]): Bool =
        match Scene.getState(rootPath(), scene) {
            case Some(NodeTag.TopBar(data)) =>
                data#shown == Some(true) or data#animTarget == Some(true)
            case _ => false
        }

    /// 現フェイズが敵軍か（純粋・テスト用）。EnemyTurn のみ敵。それ以外は自軍。
    pub def isEnemyPhase(phase: TurnPhase.Phase): Bool =
        phase == TurnPhase.Phase.EnemyTurn

    /// 帯が観測する「敵ターンか」。LevelUpView はターンを止めるモーダル割り込みなので、その間は
    /// 直前確定(shown)を維持してバーがチラつかないようにする。
    def perceivedIsEnemy(phase: TurnPhase.Phase, shown: Option[Bool]): Bool =
        if (phase == TurnPhase.Phase.LevelUpView)
            Option.getWithDefault(false, shown)
        else
            phase == TurnPhase.Phase.EnemyTurn

    def baseOf(shown: Option[Bool]): Bool = Option.getWithDefault(false, shown)

    /// P5-c(F8): per-node dispatch から外し gameLoop が 1 回呼ぶ frame-paced System。
    /// EnemyTurnDriver が World 経由で読む 2 bool（enemyTurnBusy/phaseObservedEnemy）を
    /// dual-write するため、パイプラインでは **EnemyTurnDriverScene.step より前**に置く
    /// （旧 per-node と同じ「driver は当フレームの TopBar 確定値を読む」を維持）。
    /// TopBar ノード不在（タイトル/選択画面）は getState gate で no-op。
    pub def step(delta: Duration.Duration, scene: Scene[NodeTag]):
                    Scene[NodeTag]
                    \ {GameEngine.Game, TurnPhase.State, GameEngine.Audio, World.Command} =
        match Scene.getState(rootPath(), scene) {
            case Some(NodeTag.TopBar(data)) =>
                let phase  = TurnPhase.State.get();
                let actual = perceivedIsEnemy(phase, data#shown);
                let w = GameEngine.Game.getViewportRect()#size#x;
                let next = match data#shown {
                    case None =>
                        // 起動直後はワイプ無しで即確定（最初のフレームから色を出す）。
                        let d = ({shown = Some(actual), animTarget = None,
                                  anim = Duration.zero(), hold = Duration.zero()}: Data);
                        scene |> applyAll(w, actual, None, 0.0) |> setState(d)
                    case Some(_) =>
                        let needStart =
                            Some(actual) != data#shown and data#animTarget != Some(actual);
                        if (needStart) {
                            AudioStreamPlayer.play(phaseChangeSound());
                            let d = ({shown = data#shown, animTarget = Some(actual),
                                      anim = animDuration(), hold = holdDuration()}: Data);
                            scene |> applyAll(w, baseOf(data#shown), Some(actual), 0.0) |> setState(d)
                        } else {
                            let anim1 = subClamp(data#anim, delta);
                            let hold1 = subClamp(data#hold, delta);
                            if (Duration.toSeconds(anim1) <= 0.0) {
                                // ワイプ完了 → 新フェイズを base に確定し sweep を畳む。
                                let shown1 = match data#animTarget {
                                    case Some(t) => Some(t)
                                    case None    => data#shown
                                };
                                let d = ({shown = shown1, animTarget = None,
                                          anim = Duration.zero(), hold = hold1}: Data);
                                scene |> applyAll(w, baseOf(shown1), None, 0.0) |> setState(d)
                            } else {
                                let progress =
                                    1.0 - Duration.toSeconds(anim1) / Duration.toSeconds(animDuration());
                                let d = ({shown = data#shown, animTarget = data#animTarget,
                                          anim = anim1, hold = hold1}: Data);
                                scene |> applyAll(w, baseOf(data#shown), data#animTarget, progress)
                                      |> setState(d)
                            }
                        }
                };
                // 集合(GatherMove)中だけ中央に「集合中」を表示。viewport 実幅の中央へ毎フレーム再配置。
                let next2 = next |> applyGatherLabel(phase == TurnPhase.Phase.GatherMove, w);
                // F8-slice2: 敵ターン driver が読む 2 bool を World に dual-write（next2 の確定状態から）。
                // driver はこれを World 経由で読む＝per-node 順序非依存（pipeline 移設の前提）。
                World.Command.emit(World.Cmd.SetEnemyTurnBusy(isBusy(next2)));
                World.Command.emit(World.Cmd.SetPhaseObservedEnemy(hasObservedEnemy(next2)));
                next2
            case _ => scene
        }

    /// 中央「集合中」ラベルを viewport 実幅の中央へ置き、集合中のみ可視にする。
    /// ラベル左には再生(▶)マークを置く。テキスト幅を実測し、左端から少し離して配置する。
    def applyGatherLabel(visible: Bool, w: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        let labeled = scene
            |> Label2D.mapAt(gatherLabelPath(), l ->
                l |> Node2D.setPosition({x = w / 2.0, y = rowCenterY()})
                  |> CanvasItem.setVisible(visible));
        let textW = measureLabelW(gatherLabelPath(), labeled);
        let iconX = w / 2.0 - textW / 2.0 - gatherIconGap() - gatherIconW();
        labeled
            |> Scene.mapEngineNode(gatherIconPath(), n ->
                EngineNode.mapPolygon2D(p ->
                    p |> Node2D.setPosition({x = iconX, y = rowCenterY()})
                      |> CanvasItem.setVisible(visible), n))

    /// 帯/下線/ドット/文字を `baseEnemy` 色に、sweep を `sweepTarget`（あれば）色で幅 w*progress に。
    def applyAll(w: Float64, baseEnemy: Bool, sweepTarget: Option[Bool], progress: Float64,
                 scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> resizeToWidth(w)
            |> applyBaseVisuals(baseEnemy, w)
            |> applySweep(sweepTarget, w, progress)

    /// base の帯と下線を viewport 実幅に伸ばす。
    def resizeToWidth(w: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> Panel.mapAt(bandPath(), Panel.setSize({x = w, y = bandHeight()}))
            |> Panel.mapAt(underlinePath(), Panel.setSize({x = w, y = underlineHeight()}))

    /// 切替前/確定フェイズの色・文字を base に反映し、右側グループを右端から並べる。
    def applyBaseVisuals(isEnemy: Bool, w: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        let colored = scene
            |> Panel.mapAt(bandPath(), Panel.setBackgroundColor(bandColor(isEnemy)))
            |> Panel.mapAt(underlinePath(), Panel.setBackgroundColor(accentColor(isEnemy)))
            |> Panel.mapAt(phaseDotPath(), Panel.setBackgroundColor(accentColor(isEnemy)))
            |> Label2D.mapAt(phaseJpPath(), l ->
                l |> Label2D.setText(phaseJpText(isEnemy))
                  |> CanvasItem.setModulate(phaseJpColor(isEnemy)))
            |> Label2D.mapAt(phaseEnPath(), Label2D.setText(phaseEnText(isEnemy)));
        let enW = measureLabelW(phaseEnPath(), colored);
        let jpW = measureLabelW(phaseJpPath(), colored);
        let enRight = w - rightMargin();
        let jpRight = enRight - enW - groupGap();
        let dotRight = jpRight - jpW - dotGap();
        colored
            |> Label2D.mapAt(phaseEnPath(), Node2D.setPosition({x = enRight, y = rowCenterY()}))
            |> Label2D.mapAt(phaseJpPath(), Node2D.setPosition({x = jpRight, y = rowCenterY()}))
            |> Panel.mapAt(phaseDotPath(),
                Node2D.setPosition({x = dotRight - dotSize(), y = rowCenterY() - dotSize() / 2.0}))

    /// ワイプ用オーバーレイ。`sweepTarget` が Some なら新フェイズ色で幅 w*progress、None なら畳む。
    def applySweep(sweepTarget: Option[Bool], w: Float64, progress: Float64,
                   scene: Scene[NodeTag]): Scene[NodeTag] =
        match sweepTarget {
            case None =>
                scene
                    |> Panel.mapAt(bandSweepPath(), Panel.setSize({x = 0.0, y = bandHeight()}))
                    |> Panel.mapAt(underlineSweepPath(), Panel.setSize({x = 0.0, y = underlineHeight()}))
            case Some(t) =>
                let sw = Float64.max(0.0, w * progress);
                scene
                    // 帯の sweep は鮮やかなアクセント色（青/赤）で塗って流す。確定後の base は
                    // 通常の暗い背景に戻るので、切替の瞬間だけ色が左→右に走って見える。
                    |> Panel.mapAt(bandSweepPath(), p -> p
                        |> Panel.setBackgroundColor(accentColor(t))
                        |> Panel.setSize({x = sw, y = bandHeight()}))
                    |> Panel.mapAt(underlineSweepPath(), p -> p
                        |> Panel.setBackgroundColor(accentColor(t))
                        |> Panel.setSize({x = sw, y = underlineHeight()}))
        }

    /// 指定 Label2D の描画幅（design px）。未登録なら 0。
    def measureLabelW(path: NodePath, scene: Scene[NodeTag]): Float64 =
        match Scene.getEngineNode(path, scene) {
            case Some(EngineNode.Label2DWithState(l, _)) => Label2D.measure(l)#x
            case _                                       => 0.0
        }

    /// hold/anim を delta ぶん減算し 0 で止める。
    def subClamp(t: Duration.Duration, delta: Duration.Duration): Duration.Duration =
        Duration.seconds(Float64.max(0.0, Duration.toSeconds(t) - Duration.toSeconds(delta)))

    /// CanvasLayer に紐づく状態を書き戻す。
    def setState(data: Data, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(rootPath(), node -> match node {
            case EngineNode.CanvasLayerWithState(layer, NodeTag.TopBar(_)) =>
                EngineNode.CanvasLayerWithState(layer, NodeTag.TopBar(data))
            case other => other
        }, scene)
}
