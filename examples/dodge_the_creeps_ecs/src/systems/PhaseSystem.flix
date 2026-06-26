// PhaseSystem — 時間管理・スコア・フェーズ遷移・HUD 同期（純粋）
//
// 旧 node 版の Timer ノード群（Start/Score/Message/Title）＋ TimerHandler ＋
// GamePhaseState effect ＋ applyPhaseChange を、1 本の純粋 System に畳む。
// 音（BGM/death）は phase の立ち上がりを見て gameLoop が鳴らす（ここは純粋に保つ）。
//
// HUD は World 内の entity（単層）。hudSync が phase/score/timers から各 HUD の
// text/visible を一方向に決める（tree=派生ビューに相当するものを World 内で行う）。

mod PhaseSystem {

    def scoreInterval(): Float64 = 1.0

    pub def phaseSystem(dt: Float64, world: World): World =
        hudSync(tickTimers(dt, world))

    // ── タイマー・遷移 ──

    def tickTimers(dt: Float64, world: World): World =
        let World.World(w) = world;
        match w#phase {
            case GamePhase.Menu     => world
            case GamePhase.Playing  => playingTick(dt, world)
            case GamePhase.GameOver => gameOverTick(dt, world)
        }

    /// Playing: startDelay 中（Get Ready）はスコア停止。経過後は scoreInterval ごとに +1。
    def playingTick(dt: Float64, world: World): World =
        let World.World(w) = world;
        let t = w#timers;
        if (t#startDelay > 0.0)
            World.World({timers = {startDelay = Float64.max(0.0, t#startDelay - dt) | t} | w})
        else {
            let acc = t#score + dt;
            if (acc < scoreInterval())
                World.World({timers = {score = acc | t} | w})
            else
                World.World({score = w#score + 1, timers = {score = acc - scoreInterval() | t} | w})
        }

    /// GameOver: "Game Over" 表示 → タイトル表示 → Menu へ。
    def gameOverTick(dt: Float64, world: World): World =
        let World.World(w) = world;
        let t = w#timers;
        if (t#gameOverMsg > 0.0)
            World.World({timers = {gameOverMsg = Float64.max(0.0, t#gameOverMsg - dt) | t} | w})
        else if (t#title > 0.0)
            World.World({timers = {title = Float64.max(0.0, t#title - dt) | t} | w})
        else
            World.World({phase = GamePhase.Menu | w})

    // ── HUD 同期（派生値を先に出して row-poly を避ける）──

    def hudSync(world: World): World =
        let World.World(w) = world;
        let scoreText = Int32.toString(w#score);
        let (msgText, msgVis) = messageState(w#phase, w#timers);
        let btnVis = buttonVisible(w#phase, w#timers);
        let newHuds = Map.map(h -> syncOne(scoreText, msgText, msgVis, btnVis, h), w#huds);
        World.World({huds = newHuds | w})

    def syncOne(scoreText: String, msgText: String, msgVis: Bool,
                btnVis: Bool, h: HudComp): HudComp =
        match h#kind {
            case HudKind.Score       => {text = scoreText | h}
            case HudKind.Message     => {text = msgText, visible = msgVis | h}
            case HudKind.StartButton => {visible = btnVis | h}
        }

    def messageState(phase: GamePhase, timers: Timers): (String, Bool) =
        match phase {
            case GamePhase.Menu     => ("Dodge the\nCreeps", true)
            case GamePhase.Playing  =>
                if (timers#startDelay > 0.0) ("Get Ready", true) else ("", false)
            case GamePhase.GameOver =>
                if (timers#gameOverMsg > 0.0) ("Game Over", true) else ("Dodge the\nCreeps", true)
        }

    def buttonVisible(phase: GamePhase, timers: Timers): Bool =
        match phase {
            case GamePhase.Menu     => true
            case GamePhase.Playing  => false
            case GamePhase.GameOver => timers#gameOverMsg <= 0.0
        }
}
