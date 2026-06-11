/// FrameAef — フレームパイプライン全体で使う effect set の type alias
///
/// `Node[NodeTag] instance` の `physicsProcess` / `process` が消費する effect 集合を
/// type alias として名前付きにすることで:
///   1. Flix の型推論を単純化する (13 変数を超える複雑度を回避)
///   2. 各 Scene の `process` 関数が同じ alias を参照することで `checked_ecast` を省略可能
///   3. 「フレームで使える effect は何か」が 1 か所で読める
///
/// `FrameAef` は `physicsProcess` 用 (Player/Cursor 移動など物理ライク処理)、
/// `FrameProcessAef` は `process` 用 (signal drain や per-Scene tick で必要な追加 effect 含む)。
mod FrameAef {

    /// `ready` / `physicsProcess` 用の Aef 集合。Player.physicsProcess / Cursor.physicsProcess
    /// などが要求する集合 (BoardQuery で盤面参照、Tween でアニメ進行、TurnPhase で gating 等)。
    pub type alias T = {GameEngine.Game, BoardQuery,
                         EnemyData.RosterQuery,
                         Tween.Scheduler, AnimationPlayer.Scheduler,
                         GameLogger.GameLogger,
                         TurnPhase.State, SelectedPlayer.State}

    /// `process` 用の広い Aef 集合。Player/Enemy の `process` が drainSignals 経由で
    /// attack:hit / death_blink / attack_lunge を捌き、EnemyTurnDriverScene が phase 判定で
    /// `stepOnce` や `commitWaitedAndAdvance` を起動するため、Audio / EnemyTurn / GameOverRequest /
    /// Pacing が追加される。`BoardSnapshot.fromScene` は純粋関数なので `BoardQuery` 不要。
    /// `Math.Random` は attack:hit 時の命中ロール（Combat.isHit 用の乱数）に使う。
    pub type alias ProcessT = {GameEngine.Game, GameEngine.Audio,
                                PlayerData.PartyQuery, EnemyData.RosterQuery,
                                Tween.Scheduler, AnimationPlayer.Scheduler,
                                GameLogger.GameLogger,
                                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                                CustomEffects.GameOverRequest, Pacing.State, Math.Random}
}
