/// CursorState — 選択カーソルの論理状態 + 描画位置 + 補間を保持する resource
///
/// 味方ターンの選択カーソル（四隅 L字）が指す論理マス、移動加速・敵ホバー検出の入力状態に加えて、
/// **視覚位置の単一権威**（`renderPos`・pixel）と進行中の**スライド補間**（`tweens`）・駒に乗った時の
/// **引っかかりタイマー**（`snagRemaining`）・四隅 L字の**可視フラグ**（`visible`）も持つ。カーソルは
/// scene ノードを持たず（`ArrowCursorState` と同流儀）、`RenderWorld.renderCursor` がこの resource から
/// 直描きし、`CameraScene` が `renderPos` を追従読みする。
///
/// 補間は engine の `Tween`（NodePath バインド）ではなく lib `EcsTween`（純粋・値の補間だけ）を使う
/// （World の renderPos 補間と同流儀）。カーソルは世界に 1 つなので複合キーの entity 部は定数 0 を使う。
/// `step(dt)` を gameLoop が毎フレーム 1 回呼び、tween を進めて `renderPos` を書き、`snagRemaining` を減らす。
///
/// `CursorScene.step` の各フェーズ stepper が読み書きし、`getGridPos` を通じて
/// UnitCard / EnemyCard / BattlePanel / WeaponSelect / ItemMenu などが現在の指しセルを読む。
/// TurnPhase / SelectedPlayer と同じ Ref-based handler 注入パターンに揃える。
mod CursorState {

    /// tween チャンネル＝「何を」補間するかの意味（`EcsTween` は値の補間だけ知る）。
    /// カーソルは視覚位置のスライドだけを補間するので 1 種類。
    pub enum Channel with Eq, Order {
        case Position
    }

    /// カーソル固有の状態。
    /// `gridPos`: カーソルが指している論理マス。moveStep で即更新される。
    /// `lastHoveredEnemyId`: 直前フレームでカーソルが乗っていた敵 id。
    ///   None ↔ Some(id) や Some(a) ↔ Some(b) の遷移をログ・赤レンジ再構築のトリガーに使う。
    /// `holdDir`: 直前フレームに方向キーが押されていた向き。同方向継続の判定と加速リセットに使う。
    /// `holdSteps`: 同方向に連続で進んだマス数。`computeSlideDuration` で 1 マス分のスライド時間を
    ///   初速 → 最高速に補間するのに使う。
    /// `renderPos`: 連続的な描画位置（pixel・tween 込み）。`RenderWorld.renderCursor` と
    ///   `CameraScene` が読む視覚位置の単一権威。静止時は最後のセル中心 pixel を保持。
    /// `tweens`: 進行中のスライド補間（entity 部は定数 0）。`step` が毎フレ実時間 dt(秒) 進め、
    ///   Position 出力を `renderPos` へ書く。完了で除去（`isTweening` の入力ゲートの意味を保つ）。
    /// `snagRemaining`: 駒に乗った後に入力を捨てる残り秒。`step` が dt ずつ減らし 0 で解除。
    /// `visible`: 四隅 L字を描くか（フェーズ遷移が `setVisible` で書く単一真実源）。
    pub type alias Data = {
        gridPos            = {x = Int32, y = Int32},
        lastHoveredEnemyId = Option[Int32],
        holdDir            = Option[{x = Int32, y = Int32}],
        holdSteps          = Int32,
        renderPos          = Vec2.Vec2,
        tweens             = EcsTween.Tweens[Int32, Channel],
        snagRemaining      = Float64,
        visible            = Bool
    }

    /// 初期状態（原点・ホバーなし・hold なし・補間なし・可視）。`add` の初期セルは `CursorScene` が put で上書きする。
    pub def initial(): Data =
        {gridPos = {x = 0, y = 0}, lastHoveredEnemyId = None, holdDir = None, holdSteps = 0,
         renderPos = Vec2.zero(), tweens = Map.empty(), snagRemaining = 0.0, visible = true}

    /// 補間の複合キー（entity 部は世界に 1 つのカーソルなので定数 0）。
    def tweenKey(): (Int32, Channel) = (0, Channel.Position)

    /// `withState` が提供する handler 1 つで処理する。
    pub eff State {
        def get(): Data
        def put(target: Data): Unit
    }

    // ────────────────────────────────────────────────────────
    // 補間・スナップ・引っかかり・可視の API（値の補間だけ知る EcsTween と snag タイマーで完結）
    // ────────────────────────────────────────────────────────

    /// スライド補間中か（次の方向入力をブロックする入力ゲート）。`tweens` が空でなければ真。
    pub def isTweening(): Bool \ State =
        not Map.isEmpty(State.get()#tweens)

    /// 駒に乗った引っかかり中か（入力を捨てる入力ゲート）。`snagRemaining > 0` なら真。
    pub def isSnagging(): Bool \ State =
        State.get()#snagRemaining > 0.0

    /// `start` から `target` へ `durSeconds` 秒かけてスライドを開始する（linear・単発）。
    /// 開始フレームで `renderPos` を `start` に合わせる。
    pub def startMove(start: Vec2.Vec2, target: Vec2.Vec2, durSeconds: Float64): Unit \ State =
        let d = State.get();
        let ts = EcsTween.start(tweenKey(),
            EcsTween.Track.Vec({start = start, target = target}),
            durSeconds, EcsTween.Easing.Linear, false, d#tweens);
        State.put({renderPos = start, tweens = ts | d})

    /// 補間・引っかかりを止めて `worldPos` へ瞬間移動する（tween を空にし snag を 0 に戻す）。
    pub def snapTo(worldPos: Vec2.Vec2): Unit \ State =
        let d = State.get();
        State.put({renderPos = worldPos, tweens = Map.empty(), snagRemaining = 0.0 | d})

    /// 引っかかりタイマーを `durSeconds` 秒でセットする（`step` が dt ずつ減らし 0 で解除）。
    pub def beginSnag(durSeconds: Float64): Unit \ State =
        State.put({snagRemaining = durSeconds | State.get()})

    /// 論理フィールド（gridPos / lastHoveredEnemyId / holdDir / holdSteps）だけを最新の
    /// state へ書き戻す。視覚フィールド（renderPos / tweens / snagRemaining / visible）は
    /// 同フレームで `startMove` と `beginSnag` が既に書いているので、呼び出し側が
    /// 握っているフレーム冒頭スナップショット由来の古い値で上書きしないよう state から引き継ぐ。
    /// これを介さず `{... | 冒頭スナップショット}` を丸ごと put すると開始した補間・snag が消える。
    pub def commitLogical(logical: Data): Unit \ State =
        let cur = State.get();
        State.put({gridPos            = logical#gridPos,
                   lastHoveredEnemyId = logical#lastHoveredEnemyId,
                   holdDir            = logical#holdDir,
                   holdSteps          = logical#holdSteps | cur})

    /// 四隅 L字の可視フラグを書く（フェーズ遷移が参照する単一真実源）。
    pub def setVisible(v: Bool): Unit \ State =
        State.put({visible = v | State.get()})

    /// 四隅 L字を描くか。`RenderWorld.renderCursor` が読む。
    pub def isVisible(): Bool \ State =
        State.get()#visible

    /// 視覚位置（pixel）。`RenderWorld.renderCursor` と `CameraScene` が読む。
    pub def renderPos(): Vec2.Vec2 \ State =
        State.get()#renderPos

    /// 毎フレーム 1 回、tween を dt(秒)進めて `renderPos` を書き、`snagRemaining` を減らす。
    /// gameLoop が入力 polling の後に呼ぶ（入力処理で開始した補間を同フレーム末に進める）。
    /// tween 完了フレームは `EcsTween.step` が t=1.0 スナップ値を返すので取りこぼしなく target へ確定する。
    pub def step(dt: Float64): Unit \ State =
        let d = State.get();
        let (nextTweens, outs, _done) = EcsTween.step(dt, d#tweens);
        let newRenderPos = List.foldLeft((acc, pair) -> {
            let ((_, ch), out) = pair;
            match (ch, out) {
                case (Channel.Position, EcsTween.Out.VecOut(v)) => v
                case _ => acc
            }
        }, d#renderPos, outs);
        let newSnag = Float64.max(0.0, d#snagRemaining - dt);
        State.put({renderPos = newRenderPos, tweens = nextTweens, snagRemaining = newSnag | d})

    /// 内部 `cursorRef` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let cursorRef: Ref[Data, r] = Ref.fresh(rc, initial());
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(cursorRef))
                def put(target, k) = {
                    Ref.put(target, cursorRef);
                    k()
                }
            }
        }
}
