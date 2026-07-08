// TopBarUi — 画面上部の常設フェイズバー（World-entity UI 版）。
//
// UI ツリーは TopBar.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。
// 見た目は UiRender が毎フレーム描く。ここは「陣営ワイプ演出の状態機械 / 敵ターンの『間』/
// 集合中表示 / フロア・フェイズ文字のバインディング」を回すゲーム側の配線を持つ。
//
// 画面最上部に全幅の帯を出し、左にフロア（番号＋名前、例「1F 始まりの洞窟」）、右に現在
// フェイズ（● 自軍フェイズ / PLAYER PHASE、敵は 敵軍フェイズ / ENEMY PHASE）を表示する。
// 帯背景・下線・ドット・フェイズ和文を **自軍=青ベース / 敵軍=赤ベース** で着色する。
// ターン切替時は band/underline の base 色を切替前フェイズのまま保ち、bandSweep/underlineSweep を
// 新フェイズ色で幅 0→全幅（design 240px）に伸ばして左→右へワイプする。伸び切ったら base を
// 新フェイズに確定して sweep を畳む。敵ターン開始時は短い「間」（holdDuration）を置き、その間
// isBusy=true（World bool 経由で EnemyTurnDriver が読む）で敵の行動開始を待たせる。
//
// ノード構造（TopBar.ui.json / layer=4）:
//   TopBar (none, 画面固定 HUD)
//     ├─ band / bandSweep            (box) 帯背景（base / ワイプ用オーバーレイ）
//     ├─ underline / underlineSweep  (box) 下線（base / ワイプ用オーバーレイ）
//     ├─ floorRow                    (none) 左寄せ: floorNum / floorName (text・bind)
//     ├─ phaseRow                    (none) 右寄せ: phaseDot(box) + phaseJp / phaseEn (text・bind)
//     └─ gatherGroup                 (none) 中央: gatherIcon(box) + gatherLabel「集合中」(集合中のみ可視)

mod TopBarUi {

    // ========================================================================
    // ワイプ演出の純粋コア
    // ========================================================================

    /// 1 フレーム分の状態遷移結果。
    /// `data`: 次フレームへ持ち越す TopBarState。
    /// `baseEnemy`: 帯 base（band/underline/dot/文字）を塗る陣営（true=敵軍）。ワイプ中は切替前を保つ。
    /// `sweepTarget`: ワイプ用オーバーレイの陣営（None=ワイプなしで畳む）。
    /// `progress`: ワイプ進捗 0.0〜1.0（sweep 幅 = design 幅 × progress）。
    /// `startWipe`: このフレームでワイプが始まったか（切替効果音を鳴らすトリガ）。
    pub type alias Frame = {
        data        = TopBarState.Data,
        baseEnemy   = Bool,
        sweepTarget = Option[Bool],
        progress    = Float64,
        startWipe   = Bool
    }

    /// フェイズ観測から次フレームの状態と描画指示（Frame）を純粋に決める。
    ///   - 起動直後（shown=None）はワイプ無しで即確定（最初のフレームから色を出す）。
    ///   - 現フェイズが base と異なりワイプ目標でもなければワイプ開始（anim/hold をセット・効果音）。
    ///   - ワイプ中は anim/hold を delta ぶん減算。anim が 0 で新フェイズを base に確定して sweep を畳む。
    pub def advance(delta: Duration.Duration, phase: TurnPhase.Phase, data: TopBarState.Data): Frame =
        let actual = perceivedIsEnemy(phase, data#shown);
        match data#shown {
            case None =>
                {data = {shown = Some(actual), animTarget = None, anim = Duration.zero(), hold = Duration.zero() | data},
                 baseEnemy = actual, sweepTarget = None, progress = 0.0, startWipe = false}
            case Some(_) =>
                let needStart = Some(actual) != data#shown and data#animTarget != Some(actual);
                if (needStart)
                    {data = {shown = data#shown, animTarget = Some(actual), anim = animDuration(), hold = holdDuration() | data},
                     baseEnemy = baseOf(data#shown), sweepTarget = Some(actual), progress = 0.0, startWipe = true}
                else {
                    let anim1 = subClamp(data#anim, delta);
                    let hold1 = subClamp(data#hold, delta);
                    if (Duration.toSeconds(anim1) <= 0.0) {
                        let shown1 = match data#animTarget {
                            case Some(t) => Some(t)
                            case None    => data#shown
                        };
                        {data = {shown = shown1, animTarget = None, anim = Duration.zero(), hold = hold1 | data},
                         baseEnemy = baseOf(shown1), sweepTarget = None, progress = 0.0, startWipe = false}
                    } else {
                        let progress = 1.0 - Duration.toSeconds(anim1) / Duration.toSeconds(animDuration());
                        {data = {shown = data#shown, animTarget = data#animTarget, anim = anim1, hold = hold1 | data},
                         baseEnemy = baseOf(data#shown), sweepTarget = data#animTarget, progress = progress, startWipe = false}
                    }
                }
        }

    /// 現フェイズが敵軍か（純粋・テスト用）。EnemyTurn のみ敵。それ以外は自軍。
    pub def isEnemyPhase(phase: TurnPhase.Phase): Bool =
        phase == TurnPhase.Phase.EnemyTurn

    /// 敵ターンの「間」中か（hold>0）。EnemyTurnDriver は World bool（dual-write）経由で読む。
    pub def isBusyOf(data: TopBarState.Data): Bool =
        Duration.toSeconds(data#hold) > 0.0

    /// バーが「敵ターン」を認識済みか（確定 or ワイプ目標が enemy）。0 体敵ターンの取りこぼし防止用。
    pub def hasObservedEnemyOf(data: TopBarState.Data): Bool =
        data#shown == Some(true) or data#animTarget == Some(true)

    /// 帯が観測する「敵ターンか」。LevelUpView はターンを止めるモーダル割り込みなので、その間は
    /// 直前確定(shown)を維持してバーがチラつかないようにする。
    def perceivedIsEnemy(phase: TurnPhase.Phase, shown: Option[Bool]): Bool =
        if (phase == TurnPhase.Phase.LevelUpView)
            Option.getWithDefault(false, shown)
        else
            phase == TurnPhase.Phase.EnemyTurn

    /// 確定表示中の陣営（None=まだ未確定は自軍扱い）。
    def baseOf(shown: Option[Bool]): Bool = Option.getWithDefault(false, shown)

    /// hold/anim を delta ぶん減算し 0 で止める。
    def subClamp(t: Duration.Duration, delta: Duration.Duration): Duration.Duration =
        Duration.seconds(Float64.max(0.0, Duration.toSeconds(t) - Duration.toSeconds(delta)))

    // ── 演出定数 ──

    /// 左→右ワイプの所要時間。
    def animDuration(): Duration.Duration = Duration.millis(500)
    /// 敵ターン開始に置く「間」。この間 isBusy=true で敵の行動開始を待たせる（ワイプ完了より少し長め）。
    def holdDuration(): Duration.Duration = Duration.millis(700)
    /// フェイズ切替時に鳴らす効果音（project.json "sounds" 登録名）。
    def phaseChangeSound(): String = "phase_change"
    /// 帯・sweep の全幅（design 解像度空間。UiRender の rootRect が design 幅なので固定でよい）。
    def designWidth(): Float64 = Int32.toFloat64(Game.designWi())

    // ── 配色（自軍=青 / 敵軍=赤）──
    def accentColor(isEnemy: Bool): Color =
        if (isEnemy) {r = 0.878f32, g = 0.275f32, b = 0.247f32}
        else         {r = 0.184f32, g = 0.427f32, b = 0.941f32}
    def bandColor(isEnemy: Bool): Color =
        if (isEnemy) {r = 0.14f32, g = 0.055f32, b = 0.06f32}
        else         {r = 0.05f32, g = 0.08f32, b = 0.16f32}
    def phaseJpColor(isEnemy: Bool): Color =
        if (isEnemy) {r = 1.0f32, g = 0.78f32, b = 0.74f32}
        else         {r = 0.86f32, g = 0.92f32, b = 1.0f32}
    def phaseJpText(isEnemy: Bool): String = if (isEnemy) "敵軍フェイズ" else "自軍フェイズ"
    def phaseEnText(isEnemy: Bool): String = if (isEnemy) "ENEMY PHASE" else "PLAYER PHASE"

    // ========================================================================
    // 名前パス / spec 置き場
    // ========================================================================

    /// ui.json の置き場。起動時の spawnAsset・F1 リロード台帳の登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/TopBar.ui.json")

    def rootPath(): String = "TopBar"
    def bandPath(): String = "TopBar/band"
    def bandSweepPath(): String = "TopBar/bandSweep"
    def underlinePath(): String = "TopBar/underline"
    def underlineSweepPath(): String = "TopBar/underlineSweep"
    def phaseDotPath(): String = "TopBar/phaseRow/phaseDot"
    def phaseJpPath(): String = "TopBar/phaseRow/phaseLabels/phaseJp"
    def gatherIconPath(): String = "TopBar/gatherGroup/gatherIcon"
    def gatherLabelPath(): String = "TopBar/gatherGroup/gatherLabel"

    // ========================================================================
    // フロア進入 / 退出（可視トグル + フロア表示 + 状態リセット）
    // ========================================================================

    /// フロア（再）構築時に呼ぶ。フロア番号・名前をセットし、状態を初期化して（未確定に戻し）
    /// バーを可視化する。
    pub def enter(floorLabel: String, floorName: String):
            Unit \ {TopBarState.State, UiWorldState.State} =
        TopBarState.State.put({shown = None, animTarget = None, anim = Duration.zero(),
                               hold = Duration.zero(), floorLabel = floorLabel, floorName = floorName});
        UiWorldState.State.put(UiStore.setVisible(rootPath(), true, UiWorldState.State.get()))

    /// ダンジョン外（タイトル / 選択画面）へ出るときにバーを隠す。
    pub def leave(): Unit \ UiWorldState.State =
        UiWorldState.State.put(UiStore.setVisible(rootPath(), false, UiWorldState.State.get()))

    // ========================================================================
    // 毎フレーム System
    // ========================================================================

    /// gameLoop が 1 回呼ぶ frame-paced System。
    /// EnemyTurnDriver が World 経由で読む 2 bool（enemyTurnBusy/phaseObservedEnemy）を
    /// dual-write するため、パイプラインでは **EnemyTurnDriver.step より前**に置く
    /// （driver は当フレームの TopBar 確定値を読む）。
    /// バー不可視（タイトル / 選択画面）は presence gate で no-op。
    pub def step(delta: Duration.Duration):
                    Unit
                    \ {TurnPhase.State, GameEngine.Audio, World.Command,
                       TopBarState.State, UiWorldState.State} =
        let ui0 = UiWorldState.State.get();
        if (not isActive(ui0)) ()
        else {
            let data = TopBarState.State.get();
            let phase = TurnPhase.State.get();
            let frame = advance(delta, phase, data);
            if (frame#startWipe) AudioStreamPlayer.play(phaseChangeSound()) else ();
            TopBarState.State.put(frame#data);
            let ui1 = applyFrame(frame, phase == TurnPhase.Phase.GatherMove, ui0);
            UiWorldState.State.put(ui1);
            // 敵ターン driver が読む 2 bool を World に dual-write（確定 Data から）。
            World.Command.emit(World.Cmd.SetEnemyTurnBusy(isBusyOf(frame#data)));
            World.Command.emit(World.Cmd.SetPhaseObservedEnemy(hasObservedEnemyOf(frame#data)))
        }

    /// バーが可視（フロア進入済み）か。root が未 spawn / 不可視なら no-op ゲート。
    def isActive(ui: UiStore.UiWorld): Bool =
        UiStore.idOf(rootPath(), ui)
            |> Option.flatMap(id -> Map.get(id, ui#visible))
            |> Option.getWithDefault(false)

    /// 1 フレーム分の描画指示（Frame）を UiWorld へ塗り込む純粋適用。base 塗り → sweep →
    /// 集合中表示 → フェイズ/フロア文字の bind をこの順で重ねる。step が毎フレーム呼ぶほか、
    /// スナップショットが「実ロジックで作った見た目」を再現するのに使う共有の入口。
    /// `gathering` は集合(GatherMove)フェイズ中か（中央「集合中」表示の可視）。
    pub def applyFrame(frame: Frame, gathering: Bool, ui: UiStore.UiWorld): UiStore.UiWorld =
        ui
            |> applyBaseVisuals(frame#baseEnemy)
            |> applySweep(frame#sweepTarget, frame#progress)
            |> applyGather(gathering)
            |> UiBinding.apply(resolver(frame))

    /// フロア文字（floorNum/floorName）とフェイズ文字（phaseJp/phaseEn）の bind key を解決する。
    /// フロアは resource（TopBarState）から、フェイズ文字は base 確定陣営から引く。
    def resolver(frame: Frame): String -> Option[String] =
        let data = frame#data;
        let isEnemy = frame#baseEnemy;
        key -> match key {
            case "floorNum"  => Some(data#floorLabel)
            case "floorName" => Some(data#floorName)
            case "phaseJp"   => Some(phaseJpText(isEnemy))
            case "phaseEn"   => Some(phaseEnText(isEnemy))
            case _           => None
        }

    /// 帯 base（band 背景 / underline / dot / フェイズ和文の色）を確定陣営で塗る。
    /// フェイズ文字列自体は resolver + UiBinding が流し込む。
    def applyBaseVisuals(isEnemy: Bool, ui: UiStore.UiWorld): UiStore.UiWorld =
        ui
            |> UiStore.setBoxColor(bandPath(), bandColor(isEnemy))
            |> UiStore.setBoxColor(underlinePath(), accentColor(isEnemy))
            |> UiStore.setBoxColor(phaseDotPath(), accentColor(isEnemy))
            |> UiStore.setTextTint(phaseJpPath(), phaseJpColor(isEnemy))

    /// ワイプ用オーバーレイ。sweepTarget が Some なら新フェイズ色で幅 designWidth×progress、
    /// None なら幅 0 に畳む。
    def applySweep(sweepTarget: Option[Bool], progress: Float64, ui: UiStore.UiWorld): UiStore.UiWorld =
        match sweepTarget {
            case None =>
                ui
                    |> UiStore.setWidthPx(bandSweepPath(), 0.0)
                    |> UiStore.setWidthPx(underlineSweepPath(), 0.0)
            case Some(t) =>
                let sweepWidth = Float64.max(0.0, designWidth() * progress);
                ui
                    |> UiStore.setBoxColor(bandSweepPath(), accentColor(t))
                    |> UiStore.setWidthPx(bandSweepPath(), sweepWidth)
                    |> UiStore.setBoxColor(underlineSweepPath(), accentColor(t))
                    |> UiStore.setWidthPx(underlineSweepPath(), sweepWidth)
        }

    /// 中央「集合中」ラベルと再生マークの可視を集合(GatherMove)中だけ true にする。
    /// 中央寄せは gatherGroup の flex（mainAlign=center）が担うため位置操作は不要。
    def applyGather(gathering: Bool, ui: UiStore.UiWorld): UiStore.UiWorld =
        ui
            |> UiStore.setVisible(gatherIconPath(), gathering)
            |> UiStore.setVisible(gatherLabelPath(), gathering)
}
