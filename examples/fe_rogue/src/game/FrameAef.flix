/// FrameAef — フレームパイプライン全体で使う effect set の type alias
///
/// `Node[NodeTag] instance` の `physicsProcess` / `process` が消費する effect 集合を
/// type alias として名前付きにすることで:
///   1. Flix の型推論を単純化する (13 変数を超える複雑度を回避)
///   2. 各 Scene の `process` 関数が同じ alias を参照することで `checked_ecast` を省略可能
///   3. 「フレームで使える effect は何か」が 1 か所で読める
///
/// `FrameAef.T` は `physicsProcess` 用 (Player/Cursor 移動など物理ライク処理)、
/// `FrameAef.ProcessT` は `process` 用 (signal drain や per-Scene tick で必要な追加 effect 含む)。
mod FrameAef {

    /// `physicsProcess` 用の Aef 集合 (`FrameAef.T`)。engine の physicsProcess 巡回で動くのは
    /// Player ノードだけ（`PlayerMovementDriver.physicsStep` / `gatherStep`）なので、その集合に一致させる。
    /// `World.WorldQuery`: waited の sim reader（PlayerMovementDriver の集合/追従判定）が
    /// frame 内の権威 World を読むため許可。gameLoop 全体が WorldQuery handler 内なので取得できる。
    pub type alias T = {GameEngine.Game, BoardQuery,
                         GameLogger.GameLogger,
                         TurnPhase.State, SelectedPlayer.State, World.Command,
                         World.WorldQuery,
                         // 移動範囲の clamp 述語（selectAllowedPred→MoveRangeScene.isInRange）が範囲 resource を読む。
                         RangeOverlayState.State,
                         // 手動移動の着地自動取得（stepFor→autoPickupOrLog）が中央ポップアップの
                         // 取得音予約/表示を State resource に書くため。
                         ItemPickupPopupState.State}

    /// `Node[NodeTag]` の関連型 `ProcessAef` に束ねる Aef 集合 (`FrameAef.ProcessT`)。
    /// trait Node が関連型を要求するための宣言専用で、engine の process 巡回自体は gameLoop から
    /// 呼ばない（Player/Enemy の戦闘シグナル解決は `CombatDriver.stepEntities` が明示 System として
    /// 回す＝この集合の上位互換）。
    ///   - `EnemyTurn.Queue` / `Pacing.State` / `GameOverRequest` / `ThiefDropRequest` /
    ///     `World.RngDraw` は `CombatDriver.process`（drainSignals で attack:hit / death_blink /
    ///     attack_lunge を解決）が要求（命中ロールは RngDraw chokepoint 経由）。
    pub type alias ProcessT = {GameEngine.Game, GameEngine.Audio,
                                PlayerData.PartyQuery, EnemyData.RosterQuery,
                                AnimationPlayer.Scheduler,
                                GameLogger.GameLogger,
                                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                                CustomEffects.GameOverRequest,
                                CustomEffects.ThiefDropRequest,
                                Pacing.State,
                                ItemMenuState.State, TradeMenuState.State,
                                UnitHPBarRender.ForecastState,
                                World.Command, World.PhaseQuery, World.WorldQuery,
                                World.RngDraw,
                                UiWorldState.State}
}
