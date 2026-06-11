/// TurnFlow — 味方ターンの確定とフェーズ前進（`commitWaitedAndAdvance` の単独所有）
///
/// PlayerAttack / WeaponSelect / ActionMenu「たいき」/ 杖・アイテム使用 / 反撃完了など、
/// 「行動が確定した」すべての経路がここを通って次フェーズを判定する。
/// 状態所有 Scene（PlayerScene / EnemyScene）からターン進行のオーケストレーションを
/// 分離したモジュールで、process を持たないため Game.flix の dispatch 表に登録せず
/// `src/game/` に置く（dispatch 表に載るとフレーム毎に呼ばれる Scene として扱われる）。
///
/// 許容している相互参照（ターン編成ペア）: `EnemyTurnDriverScene.process` は
/// PlayerAttackHold 解除時に `TurnFlow.commitWaitedAndAdvance` を呼び、
/// `commitWaitedAndAdvance` は全員 waited のとき `EnemyTurnDriverScene.beginTurn` を呼ぶ。
/// 「味方ターンの終わり」と「敵ターンの始まり」が表裏一体であるための設計的サイクルで、
/// beginTurn を phase 経由に externalize すると敵ターン開始タイミング（同一フレームでの
/// キュー構築・距離順ソート・clearActedAll）が変わるため直接呼び出しのまま残す。
mod TurnFlow {

    /// PlayerAttack / WeaponSelect / ActionMenu「たいき」を抜けるときの共通確定処理。
    /// 複数 Scene が「行動完了」を検知する経路を持つため、次フェーズ判定を分散させると
    /// 「waited にせず先へ進む」「レベルアップ割り込みを見落とす」バグが起きやすい。
    /// それを防ぐ単一割り込み保証点としてここに集約する。
    pub def commitWaitedAndAdvance(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State} =
        // レベルアップ表示待ちの味方が居れば、ターンを進めずステータス変化パネル (LevelUpView) へ割り込む。
        // パネルを閉じると LevelUpPanelScene.confirm が pendingLevelUp を消して再度ここを呼ぶので、
        // そのとき保留が無くなって通常の確定・前進に進む。Kill / Counter / Commit の 3 経路すべてが
        // 最後にここを通るため、自分の攻撃で得たレベルアップ表示の割り込みは 1 箇所で足りる。
        if (PlayerScene.anyPendingLevelUp(scene))
            PhaseTransitions.enterLevelUpView(scene)
        else
        let withWaited = match SelectedPlayer.State.get()#id {
            case Some(id) => PlayerScene.setWaited(id, scene)
            case None     => scene   // 防御的: 選択なしで Attack に入ることは UI フロー上起こらないが、
                                   // waited 化する駒が存在しないだけなので scene をそのまま返しても安全
        };
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        // 次の active 味方の gridPos をローカル `withWaited` から直接拾って渡す。
        // `enterPlayerCursor` 側の PartyQuery フォールバックは sceneRef (frame 冒頭の snapshot)
        // を読むので、たった今 setWaited した駒をまだ active として返してしまう。
        match PlayerScene.firstActive(withWaited) {
            case Some(next) =>
                PhaseTransitions.enterPlayerCursorAt(next#gridPos, withWaited)
            case None       =>
                EnemyTurnDriverScene.beginTurn(withWaited)
        }
}
