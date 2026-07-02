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

    /// `ready` / `physicsProcess` 用の Aef 集合 (`FrameAef.T`)。Player.physicsProcess / Cursor.physicsProcess
    /// などが要求する集合 (BoardQuery で盤面参照、Tween でアニメ進行、TurnPhase で gating 等)。
    /// `World.WorldQuery`: waited の sim reader（PlayerMovementDriver の集合/追従判定）が
    /// frame 内の権威 World を読むため許可。gameLoop 全体が
    /// WorldQuery handler 内なので physicsProcess でも取得できる。
    pub type alias T = {GameEngine.Game, BoardQuery,
                         EnemyData.RosterQuery,
                         Tween.Scheduler, AnimationPlayer.Scheduler,
                         GameLogger.GameLogger,
                         TurnPhase.State, SelectedPlayer.State, CursorState.State, World.Command,
                         World.WorldQuery,
                         // 手動移動の着地自動取得（stepFor→autoPickupOrLog）が中央ポップアップの
                         // 取得音予約/表示を State resource に書くため。
                         ItemPickupPopupScene.State}

    /// `process` redef の分岐先が消費する Aef 集合 (`FrameAef.ProcessT`)。
    /// 分岐先は `CombatDriver.process`（Player/Enemy の drainSignals で attack:hit /
    /// death_blink / attack_lunge を解決）と、メニュー/カード/パネルの `refreshItems`/`process`
    /// （ItemMenu/ActionMenu/WeaponSelect/GameOverMenu/SuspendConfirm/Trade/
    /// UnitCard/EnemyCard/BattlePanel/LevelUpPanel）。
    ///   - `EnemyTurn.Queue` / `Pacing.State` / `GameOverRequest` / `ThiefDropRequest` /
    ///     `World.RngDraw` は `CombatDriver.process` が要求（命中ロールは RngDraw chokepoint 経由）。
    ///   - `BattlePanelScene.State` / `UnitHPBarRender.ForecastState` は BattlePanel.process が
    ///     攻撃予報を put、`LevelUpPanelScene.State` は LevelUpPanel.process が演出に使う。
    pub type alias ProcessT = {GameEngine.Game, GameEngine.Audio,
                                PlayerData.PartyQuery, EnemyData.RosterQuery,
                                Tween.Scheduler, AnimationPlayer.Scheduler,
                                GameLogger.GameLogger,
                                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                                CustomEffects.GameOverRequest,
                                CustomEffects.ThiefDropRequest,
                                Pacing.State,
                                BattlePanelScene.State, LevelUpPanelScene.State,
                                ItemMenuState.State, TradeMenuState.State,
                                UnitHPBarRender.ForecastState,
                                World.Command, World.PhaseQuery, World.WorldQuery,
                                World.RngDraw}
}
