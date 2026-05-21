/// PhaseTransitions — フェーズ遷移時の overlay / cursor 副作用を集約する
///
/// `TurnPhase.Phase` を変更すると同時に「画面上の overlay (移動範囲・攻撃範囲)」と
/// 「カーソル (表示・スナップ)」を遷移先のフェーズに合わせて整える必要がある。
/// これらの副作用が散在すると「フェーズと表示の不整合」バグの温床になるため、
/// **フェーズに入る側 (= 遷移先) ごとに 1 関数** にまとめてここで管理する。
///
/// 命名: `enter<Phase>(scene)` は「scene を <Phase> に遷移させて、その時に必要な
/// overlay/cursor の状態を整えた scene を返す」関数。`TurnPhase.State.put` も内側で
/// 呼ぶので、呼び出し側は put を意識しなくてよい。
///
/// 呼び出し元の典型:
///   - `TurnInputBridge.apply` (TurnRules.decide の結果) → enter* を呼ぶ
///   - データ Scene の遷移関数 (`PlayerScene.commitWaitedAndAdvance` 等) → enter* を呼ぶ
///   - 駆動 Scene (`EnemyTurnDriverScene.beginTurn`) → enter* を呼ぶ
///
/// データ Scene 側 (PlayerScene 等) は「自分のデータ更新」のみ責任を持ち、overlay/cursor は
/// この module に全部任せる。これで PlayerScene → 各 overlay Scene の直接依存が消える。
mod PhaseTransitions {

    /// PlayerCursor フェーズに入る。
    /// `cancelSelection` で「移動キャンセルで戻す」分岐、`AutoMoveScene.exitToCursor` の
    /// AutoMove 終了などから呼ぶ。
    /// 動作: 全 player overlay を clear → カーソルを表示してプレイヤー
    /// (`CursorScene.snapToPlayer` のフォールバック規則) にスナップ。
    ///
    /// `commitWaitedAndAdvance` のように **フレーム内で `setWaited` を行った直後** に呼ぶ
    /// 経路では `enterPlayerCursorAt` の方を使う。snapToPlayer 内のフォールバックは
    /// `PartyQuery` (= `sceneRef` = フレーム冒頭の snapshot) を読むので、mid-frame 更新が
    /// 反映されず「いま waited にした駒」をアクティブ扱いしてしまうため。
    pub def enterPlayerCursor(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State,
                              PlayerScene.PartyQuery} =
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        scene
            |> MoveRangeScene.clear
            |> MoveAttackRangeScene.clear
            |> PlayerAttackRangeScene.clear
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToPlayer

    /// PlayerCursor フェーズに入り、カーソルを **明示的に指定された座標** にスナップする。
    /// 呼び出し側がフレーム内で計算した「次にアクティブな味方の gridPos」を渡す想定。
    /// `enterPlayerCursor` のフォールバック (PartyQuery 経由) では sceneRef の更新タイミング
    /// 都合で stale な味方を返してしまうケース (`commitWaitedAndAdvance` 直後) に使う。
    pub def enterPlayerCursorAt(target: {x = Int32, y = Int32},
                                  scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State} =
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        scene
            |> MoveRangeScene.clear
            |> MoveAttackRangeScene.clear
            |> PlayerAttackRangeScene.clear
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToCell(target)

    /// PlayerMoving フェーズに入る (味方マスで Z 押下時)。
    /// 動作: EnemyRange を消す → 選択中味方の移動範囲 (青) と攻撃範囲 (赤) を組み立て →
    ///       カーソルを隠す (移動中はカーソル不要)。
    /// `SelectedPlayer.State` には選択駒の id を入れた後でこの関数を呼ぶ前提
    /// (MoveRangeScene.refresh が選択 id を見るため)。
    pub def enterPlayerMoving(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        TurnPhase.State.put(TurnPhase.Phase.PlayerMoving);
        scene
            |> EnemyRangeScene.clear
            |> MoveRangeScene.refresh
            |> MoveAttackRangeScene.refresh
            |> CursorScene.setVisible(false)

    /// PlayerAttack フェーズに入る (ActionMenu「こうげき」確定時)。
    /// 動作: 移動・予備範囲 (青/赤マス) を消す → 武器射程の赤マスを出す → カーソル表示し、
    ///       赤マス内の最初の敵にスナップ (敵が居なければ自分位置)。
    pub def enterPlayerAttack(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State,
                              PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        TurnPhase.State.put(TurnPhase.Phase.PlayerAttack);
        scene
            |> MoveRangeScene.clear
            |> MoveAttackRangeScene.clear
            |> PlayerAttackRangeScene.show
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToFirstTargetOrPlayer

    /// PlayerAutoMove フェーズに入る (空マスで Z 押下 → 旗を立てた直後)。
    /// 動作: EnemyRange を消す (AutoMove 中は赤レンジを出さない) → カーソルを隠す。
    /// 旗自体の表示は呼び出し側 (`FlagScene.markAt`) が責任。
    pub def enterPlayerAutoMove(scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.PlayerAutoMove);
        scene
            |> EnemyRangeScene.clear
            |> CursorScene.setVisible(false)

    /// EnemyTurn フェーズに入る (全味方 waited または 敵ターン遷移時)。
    /// 動作: 全 player overlay を消す (敵ターン中は赤/青マス不要)。
    /// 敵キューのビルドや log は `EnemyTurnDriverScene.beginTurn` 側で行うのでここでは扱わない。
    pub def enterEnemyTurn(scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.EnemyTurn);
        scene
            |> MoveRangeScene.clear
            |> MoveAttackRangeScene.clear
            |> PlayerAttackRangeScene.clear
}
