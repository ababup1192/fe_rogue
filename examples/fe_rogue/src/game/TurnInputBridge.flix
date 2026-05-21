/// TurnInputBridge — 入力 → 純粋判断 (TurnRules.decide) → Scene 適用 の 3 段配線
///
/// `Game.flix` の `InputHandler` instance から「PlayerCursor / PlayerMoving / PlayerAttack
/// の Z/X 入力」が来たときに呼ばれるブリッジ。流れ:
///   1. `TurnContextBuilder.build` で現フレームの状態から純粋な `TurnRules.Context` を構築
///   2. `TurnRules.decide` (純粋関数) で次の `Transition` を決める
///   3. `apply` の中央 match で対応する 1 つの Scene 関数を呼ぶ
///
/// この match が「ゲームの中心ルールが画面にどう反映されるか」を一覧できる窓口で、
/// 各 case は 1 行 (対応する Scene 関数の呼び出しのみ) に痩せている。
/// 「次セレクトか敵ターンか」を決める `AttackSkip` だけは複数 effect を跨ぐので
/// `PlayerScene.commitWaitedAndAdvance` を経由する。
mod TurnInputBridge {

    /// 1 回のキー入力 (Confirm / Cancel) を処理する。
    pub def handle(input: TurnRules.Input, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State} =
        let context = TurnContextBuilder.build(input, scene);
        apply(TurnRules.decide(context), scene)

    /// `decide` が返した `Transition` をシーンに適用する。
    /// 各 case の本体は対応する 1 つの Scene 関数を呼ぶだけに痩せている。
    def apply(transition: TurnRules.Transition,
               scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State} =
        match transition {
            case TurnRules.Transition.Stay                              => scene
            case TurnRules.Transition.CursorSelectPlayer(playerId)      =>
                PlayerScene.beginSelection(playerId, scene)
            case TurnRules.Transition.CursorPlantFlag(targetX, targetY) =>
                FlagScene.plant({x = targetX, y = targetY}, scene)
            case TurnRules.Transition.MovingOpenActionMenu              =>
                ActionMenuScene.openFromMoving(scene)
            case TurnRules.Transition.MovingCancel                      =>
                PlayerScene.cancelSelection(scene)
            case TurnRules.Transition.OpenWeaponMenu(attackerId, defenderId, _defX, _defY) =>
                WeaponMenuScene.openFor(attackerId, defenderId, scene)
            case TurnRules.Transition.AttackSkip                        =>
                PlayerScene.commitWaitedAndAdvance(scene)
        }
}
