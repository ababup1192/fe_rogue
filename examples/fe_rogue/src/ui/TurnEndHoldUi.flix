// TurnEndHoldUi — Shift（キーボード）/ ゲームパッド LB の長押しでターンエンドする充填ゲージ（World-entity UI 版）。
//
// UI ツリーは TurnEndHold.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。見た目は
// UiRender が毎フレーム描く。ここは Shift 押下をポーリングして純粋 `step` で経過時間を進め、充填リングの
// 頂点を毎フレーム塗り替え、満タン到達フレームで 1 回だけターンエンドを発火するゲーム側の配線を持つ。
//
// プレイヤーターン中（PlayerCursor / GatherMove）に Shift を押し続けると、ログ帯の上に「⭕ ターンスキップ」が
// 出て約 0.64 秒で満タンになり、満タン到達で「全員待機」（= ActionMenuUi.turnEndShortcut）を実行して敵ターンへ
// 移る。途中で離すとゲージは消えてターン継続。短いタップ（showDelaySeconds 未満）ではゲージを出さない。
//
// 充填は **Shift の新規押下エッジ（離した状態 → 押した状態）** でのみ arm（開始）する。macOS の cmd+shift+4 等で
// OS が Shift の key-up を食って `isKeyPressed` が押下のまま固着しても、固着中は新規押下エッジが立たないため
// arm されず、入力なしの毎ターン自動発火を防ぐ。状態（elapsed / prevHeld）は TurnEndHoldState resource が権威。
//
// 表示中はログ帯（World-entity UI の Log root）を背景として再利用する（`LogUi.holdForOverlay` で帯を出して
// ログ本文を消す）。本モジュールの frameStep は gameLoop のパイプラインで LogUi.step より後に走らせるため上書きが効く。
//
// ノード構造（TurnEndHold.ui.json / layer=7。ログ(1)/ItemPickup(6) より前面）:
//   TurnEndHold (none, 画面固定 HUD)
//     ├─ ringBg  (poly, 全周リングの薄いトラック)
//     ├─ ringFg  (poly, 12 時起点に時計回りで満ちる充填弧)  ← サブポリを毎フレーム setPolyPolys で塗り替え
//     └─ textRow (none) → label (text "ターンスキップ")
//
// リングは engine の Arc と同じアヌラス（中空円）分割の幾何を作る。UI の poly widget は 1 サブポリ =
// 1 PolygonRenderCmd（レンダラは GL_TRIANGLE_FAN で凸多角形しか塗れない）なので、外周 2 点＋内周 2 点の
// 凸クアッドをセグメントぶん並べた凸サブポリ列としてリングを組む（凹多角形は実機で中空にならない）。

mod TurnEndHoldUi {

    // ========================================================================
    // spec 置き場 / 名前パス
    // ========================================================================

    /// ui.json の置き場。起動時の spawnAsset・F1 リロードレジストリの登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/TurnEndHold.ui.json")

    /// root（可視トグルの対象）の名前パス。
    pub def rootPath(): String = "TurnEndHold"
    /// リング背景トラック（全周）と前景の充填弧（満ちる弧）の poly ノード。
    def ringBgPath(): String = "TurnEndHold/ringBg"
    def ringFgPath(): String = "TurnEndHold/ringFg"

    // ========================================================================
    // 定数（充填タイミング・発火・リング幾何）
    // ========================================================================

    /// ターンエンド発火時の効果音（gatherShortcut と同じ "confirm"）。
    def fireSound(): String = "confirm"

    /// 満タンまでの長押し秒数。
    def fillSeconds(): Float64 = 0.64
    /// この秒数を超えてからゲージを表示する（短いタップでチラ見えさせない）。
    def showDelaySeconds(): Float64 = 0.15

    /// 全周 = 2π。比率→角度の換算に使う（engine `Arc.tau` と同値）。
    def tau(): Float64 = 6.283185307179586
    /// 12 時方向（-π/2）を起点に、充填率に応じて時計回り（角度増加方向）へ伸ばす。
    def ringStartAngle(): Float64 = -1.5707963267948966
    /// 外周半径 / 太さ（内半径 = 外周 - 太さ = 1.8）。ui.json の poly ノードのレイアウト矩形（6×6）に収まる。
    def ringOuterRadius(): Float64 = 3.0
    def ringWidth(): Float64 = 1.2
    def ringInnerRadius(): Float64 = ringOuterRadius() - ringWidth()
    /// 弧の分割数（engine Arc の既定と同じ。多いほど滑らか）。
    def ringSegments(): Int32 = 32
    /// poly ノードのレイアウト矩形（6×6）左上を原点にしたときのリング中心（外周半径ぶん内側）。
    def ringLocalCenter(): Vec2.Vec2 = {x = ringOuterRadius(), y = ringOuterRadius()}

    // ========================================================================
    // 純粋: 1 フレーム分の状態更新
    // ========================================================================

    /// `step` の結果。
    /// `data`    — 次フレームへ持ち越す新しい状態。
    /// `ratio`   — ゲージ充填率 0.0〜1.0。
    /// `visible` — ゲージ一式を表示するか。
    /// `fire`    — このフレームでターンエンドを発火するなら true（満タン到達フレームのみ）。
    pub type alias StepResult = {
        data    = TurnEndHoldState.GaugeData,
        ratio   = Float64,
        visible = Bool,
        fire    = Bool
    }

    /// 1 フレーム分の状態更新（副作用なし・テスト対象）。
    ///   - `active`（対象フェーズ）かつ `held`（Shift 押下）でなければ即リセット（経過 0・非表示）。
    ///   - `held` の新規押下エッジ（`justPressed` = 前フレーム未押下→今フレーム押下）または
    ///     既に充填中（`elapsed > 0`）でなければ arm せず、held でも経過を進めない。
    ///     → 固着した Shift（離しても押下扱いのまま）はエッジが立たないので arm されず暴発しない。
    ///   - 経過が `fillSeconds` を初めて跨いだフレームだけ `fire=true`（到達フレームのみ）。
    ///     満タン後も `held` の間は経過を積み増すだけで再発火しない。
    ///   - 途中は充填率（1.0 でクランプ）を返し、`showDelaySeconds` を超えてから表示する。
    ///   - `prevHeld` は全枝で必ず今フレームの `held` に更新する（敵ターン中=active false でも更新し続け、
    ///     プレイヤーターン復帰フレームで固着 Shift が誤って arm されないようにする不変条件）。
    pub def step(data: TurnEndHoldState.GaugeData, active: Bool, held: Bool, dt: Duration.Duration): StepResult =
        let justPressed = InputEdge.pressed(data#prevHeld, held);
        if (not (active and held))
            {data = {elapsed = Duration.zero(), prevHeld = held},
             ratio = 0.0, visible = false, fire = false}
        else {
            let armed = Duration.toSeconds(data#elapsed) > 0.0 or justPressed;
            if (not armed)
                {data = {elapsed = Duration.zero(), prevHeld = held},
                 ratio = 0.0, visible = false, fire = false}
            else {
                let e = Duration.add(data#elapsed, dt);
                let secs = Duration.toSeconds(e);
                let prevSecs = Duration.toSeconds(data#elapsed);
                {data = {elapsed = e, prevHeld = held},
                 ratio = Float64.min(1.0, secs / fillSeconds()),
                 visible = secs >= showDelaySeconds(),
                 fire = prevSecs < fillSeconds() and secs >= fillSeconds()}
            }
        }

    // ========================================================================
    // 純粋: リング頂点生成（進捗率 → 弧の点列）
    // ========================================================================

    /// 全周トラック（薄い輪）を凸クアッド列へ。背景 poly ノードへ流し込む。sweep=2π 固定。
    pub def trackRingPolys(): List[List[Vec2.Vec2]] =
        ringSectorPolys(tau())

    /// 充填弧（12 時起点に時計回りで満ちる）を凸クアッド列へ。前景 poly ノードへ毎フレーム流し込む。
    /// `ratio` は 0..1 にクランプし、sweep = 2π·ratio ぶんの弧を作る。
    pub def progressRingPolys(ratio: Float64): List[List[Vec2.Vec2]] =
        ringSectorPolys(tau() * Float64.min(1.0, Float64.max(0.0, ratio)))

    /// 開始角 `ringStartAngle()` から `sweep` ラジアンぶんの中空扇形（アヌラス）を、`ringSegments()` 個の
    /// 凸クアッド（外周 2 点＋内周 2 点の 4 角形）へ分割する。レンダラは GL_TRIANGLE_FAN（凸前提）で
    /// 凹多角形を塗れないため、外周弧＋内周逆順の 1 本の凹多角形にはせず、engine `Arc.toRenderCmds` と
    /// 同じ角度刻み・中心・半径・頂点順（外周 a0, 外周 a1, 内周 a1, 内周 a0）でセグメントごとの凸クアッドに
    /// 割る（実機の塗り潰しと見た目一致のため）。sweep<=0 は空（非描画）。
    def ringSectorPolys(sweep: Float64): List[List[Vec2.Vec2]] =
        if (sweep <= 0.0) Nil
        else {
            let start = ringStartAngle();
            let n = ringSegments();
            let step = sweep / Int32.toFloat64(n);
            let angleAt = i -> start + step * Int32.toFloat64(i);
            List.range(0, n) |> List.map(i -> {
                let a0 = angleAt(i);
                let a1 = angleAt(i + 1);
                ringVertex(a0, ringOuterRadius()) :: ringVertex(a1, ringOuterRadius()) ::
                ringVertex(a1, ringInnerRadius()) :: ringVertex(a0, ringInnerRadius()) :: Nil
            })
        }

    /// リング中心 `ringLocalCenter()` から角度 `angle`・半径 `radius` の点（poly ノードのレイアウト矩形ローカル px）。
    def ringVertex(angle: Float64, radius: Float64): Vec2.Vec2 =
        let c = ringLocalCenter();
        {x = c#x + RenderUtil.cosF(angle) * radius,
         y = c#y + RenderUtil.sinF(angle) * radius}

    // ========================================================================
    // 毎フレーム System
    // ========================================================================

    /// gameLoop が 1 回呼ぶ frame-paced System。Shift 押下を読み、`step` で進め、リング頂点・可視を
    /// 反映し、満タン到達フレームでターンエンドを発火する。ダンジョン外（タイトル/選択画面）は
    /// 盤面未 seed で no-op（対象フェーズが PlayerCursor でも誤発火しない）。
    /// gameLoop のパイプラインでは LogUi.step より後に置く（ログ帯を上書きするため）。
    pub def frameStep(frame: App.Frame, delta: Duration.Duration):
                    Unit
                    \ {GameEngine.Audio, GameLogger.GameLogger,
                       EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                       GatherResume.State, World.Command, World.WorldQuery, TurnEndHoldState.State,
                       RangeOverlayState.State,
                       // 表示中はログ帯（World-entity UI の Log root）を背景として再利用する。
                       UiWorldState.State} =
        if (not World.hasBoard(World.WorldQuery.get())) ()
        else {
            let data = TurnEndHoldState.State.get();
            let phase = TurnPhase.State.get();
            // 対象は素のカーソル中と集合移動中のみ。
            let active = phase == TurnPhase.Phase.PlayerCursor
                            or phase == TurnPhase.Phase.GatherMove;
            let held = App.isDown(GameEngine.Key.LeftShift, frame);
            let result = step(data, active, held, delta);
            TurnEndHoldState.State.put(result#data);
            applyAppearance(result#ratio, result#visible);
            if (result#fire) {
                AudioStreamPlayer.play(fireSound());
                ActionMenuUi.turnEndShortcut()
            } else ()
        }

    /// 充填率と可視状態をリング頂点・root 可視へ反映する。表示中はログ帯を背景として再利用する
    /// （`LogUi.holdForOverlay` で帯を出しログ本文を消す）。前景弧は 12 時起点に充填率ぶんだけ満ちる。
    def applyAppearance(ratio: Float64, visible: Bool): Unit \ UiWorldState.State =
        UiWorldState.State.put(applyRing(ratio, visible, UiWorldState.State.get()));
        if (visible) LogUi.holdForOverlay() else ()

    /// 充填率・可視から UiWorld へリング頂点と root 可視を塗る純粋適用（frameStep が毎フレーム呼ぶほか、
    /// スナップショット／GIF が「実ロジックで作った見た目」を再現するのに使う共有の入口）。
    /// 表示中は背景トラックと充填弧の頂点を毎フレーム塗り替え、非表示なら root を隠す。
    pub def applyRing(ratio: Float64, visible: Bool, ui: UiStore.UiWorld): UiStore.UiWorld =
        if (visible)
            ui
                |> UiStore.setPolyPolys(ringBgPath(), trackRingPolys())
                |> UiStore.setPolyPolys(ringFgPath(), progressRingPolys(ratio))
                |> UiStore.setVisible(rootPath(), true)
        else UiStore.setVisible(rootPath(), false, ui)
}
