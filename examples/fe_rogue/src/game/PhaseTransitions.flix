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
/// ## フェーズ別 overlay / cursor 仕様 (この表が単一の真理点)
///
/// | Phase             | MoveRange | MoveAttackRange | PlayerAttackRange | TradeRange | EnemyRange | Cursor             |
/// |-------------------|-----------|-----------------|-------------------|------------|------------|--------------------|
/// | PlayerCursor      | Clear     | Clear           | Clear             | Clear      | Keep       | Show + SnapPlayer  |
/// | PlayerCursorAt    | Clear     | Clear           | Clear             | Clear      | Keep       | Show + SnapCell    |
/// | PlayerMoving      | Refresh   | Refresh         | Keep              | Clear      | Clear      | Hide               |
/// | PlayerAttack      | Clear     | Clear           | Show              | Clear      | Keep       | Show + SnapTarget  |
/// | TradeTargetSelect | Clear     | Clear           | Clear             | Show       | Clear      | Show + SnapPlayer  |
/// | PlayerAutoMove    | Clear     | Clear           | Clear             | Clear      | Clear      | Hide               |
/// | RogueMove         | Clear     | Clear           | Clear             | Clear      | Clear      | Hide               |
/// | RogueAlert        | Keep      | Keep            | Keep              | Keep       | Keep       | Keep(Hidden)       |
/// | EnemyTurn         | Clear     | Clear           | Clear             | Clear      | Keep       | Keep               |
///
/// **意味**:
///   - Clear   — 既存のノードを scene から取り除く (なければ no-op)
///   - Refresh — 既存ノードを取り除いてから選択中味方を起点に再構築 (`SelectedPlayer.State` 必要)
///   - Show    — PlayerAttackRange 専用。武器射程で再構築 (`SelectedPlayer.State` 必要)
///   - Keep    — そのノードには触れない (前 phase の表示状態を温存)
///   - SnapPlayer / SnapCell / SnapTarget — `CursorScene.snap*` をそれぞれ呼ぶ
///
/// 新しいフェーズを追加するときはこの表に行を追加し、対応する `enter<Phase>` 関数と
/// `TestPhaseTransitions` の @Test を追加すること。
///
/// ## 呼び出し元の典型
///   - `TurnInputBridge.apply` (TurnRules.decide の結果) → enter* を呼ぶ
///   - データ Scene の遷移関数 (`TurnFlow.commitWaitedAndAdvance` 等) → enter* を呼ぶ
///   - 駆動 Scene (`EnemyTurnDriverScene.beginTurn`) → enter* を呼ぶ
///
/// データ Scene 側 (PlayerScene 等) は「自分のデータ更新」のみ責任を持ち、overlay/cursor は
/// この module に全部任せる。これで PlayerScene → 各 overlay Scene の直接依存が消える。
mod PhaseTransitions {

    /// 味方系 4 range (Move / MoveAttack / PlayerAttack / TradeRange) を全消し。
    /// PlayerCursor / PlayerCursorAt / EnemyTurn が共通で使う「味方の範囲表示を全部閉じる」操作。
    def clearAllPlayerRanges(scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> MoveRangeScene.clear
            |> MoveAttackRangeScene.clear
            |> PlayerAttackRangeScene.clear
            |> TradeRangeScene.clear

    /// 移動系 2 range (Move / MoveAttack) を消す。PlayerAttackRange は呼び出し側 (`show`) が
    /// 引き継いで再構築するので、ここでは触らない。PlayerAttack 進入で使う。
    def clearMoveOnlyRanges(scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> MoveRangeScene.clear
            |> MoveAttackRangeScene.clear

    /// PlayerCursor フェーズに入る。
    /// `cancelSelection` で「移動キャンセルで戻す」分岐、`AutoMoveScene.exitToCursor` の
    /// AutoMove 終了などから呼ぶ。
    ///
    /// **フレーム内で `setWaited` した直後** に呼ぶ経路では `enterPlayerCursorAt` の方を使う。
    /// `snapToPlayer` 内のフォールバックは `PartyQuery` (= `sceneRef` = フレーム冒頭の snapshot)
    /// を読むため、同フレーム内の waited 更新が反映されず「いま waited にした駒」を
    /// まだアクティブと誤判定してしまう。
    pub def enterPlayerCursor(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State,
                              PlayerData.PartyQuery} =
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        clearAllPlayerRanges(scene)
            |> EnemyScene.showAllActive        // 味方フェーズ中は敵を通常色(アクティブ)で見せる
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
        clearAllPlayerRanges(scene)
            |> EnemyScene.showAllActive        // 味方フェーズ中は敵を通常色(アクティブ)で見せる
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToCell(target)

    /// LevelUpView フェーズに入る (攻撃解決でレベルアップを検出したとき)。
    /// ステータス変化パネルを出して入力待ちにするフェーズ。味方の範囲表示を全消しし、
    /// カーソルも隠してモーダル表示にする。パネルの可視化と内容は LevelUpPanelScene.process が
    /// phase を見て行うので、ここはフェーズ設定と下地の片付けだけに徹する。
    pub def enterLevelUpView(scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.LevelUpView);
        clearAllPlayerRanges(scene)
            |> CursorScene.setVisible(false)

    /// PlayerMoving フェーズに入る (味方マスで Z 押下時)。
    /// EnemyRange を先に消してから Move/MoveAttack を refresh する順序を守る必要がある。
    /// `MoveRangeScene.refresh` は `SelectedPlayer.State` から選択駒 id を読むため、
    /// この関数を呼ぶ **前** に `SelectedPlayer.State` に id をセットしておくこと。
    /// 逆順 (先に refresh) にすると敵の危険範囲と移動範囲が重複表示される。
    pub def enterPlayerMoving(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        TurnPhase.State.put(TurnPhase.Phase.PlayerMoving);
        scene
            |> EnemyRangeScene.clear
            |> EnemyAttackRangeScene.clear
            |> MoveRangeScene.refresh
            |> MoveAttackRangeScene.refresh
            |> CursorScene.setVisible(false)

    /// PlayerAttack フェーズに入る (ActionMenu「こうげき」確定時)。
    /// 動作 (表 4 行目): Move/MoveAttack 消去 → 武器射程の赤マスを show → カーソル表示し、
    ///                    赤マス内の最初の敵にスナップ (敵が居なければ自分位置)。
    pub def enterPlayerAttack(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State,
                              PlayerData.PartyQuery, EnemyData.RosterQuery} =
        TurnPhase.State.put(TurnPhase.Phase.PlayerAttack);
        clearMoveOnlyRanges(scene)
            |> PlayerAttackRangeScene.show
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToFirstTargetOrPlayer

    /// PlayerAutoMove フェーズに入る (「しゅうごう」確定直後 = ロードへの合流開始)。
    /// 動作: 味方系 range と EnemyRange を全消し → カーソルを隠す。
    /// 合流者の移動・非表示化は `AutoMoveScene` の driver が担当する。
    pub def enterPlayerAutoMove(scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.PlayerAutoMove);
        clearAllPlayerRanges(scene)
            |> EnemyRangeScene.clear
            |> EnemyAttackRangeScene.clear
            |> CursorScene.setVisible(false)

    /// RogueMove フェーズに入る (合流完了 = 1 キャラ自由歩行の開始)。
    /// 動作: 味方系 range と EnemyRange を全消し → カーソルを隠す
    ///       (ロードは自分の physicsProcess で動くのでカーソルは不要)。
    pub def enterRogueMove(scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.RogueMove);
        clearAllPlayerRanges(scene)
            |> EnemyRangeScene.clear
            |> EnemyAttackRangeScene.clear
            |> CursorScene.setVisible(false)

    /// RogueAlert フェーズに入る (敵に検知された瞬間の発見演出)。
    /// overlay / cursor は RogueMove の状態(全消し・カーソル非表示)を温存し、フェーズだけ進める。
    /// 「！」表示・カメラ寄せ・find SE・入力ロック(hold = 演出中の操作無効) は
    /// 呼び出し側 (`AutoMoveScene.triggerAlert`) と `CameraScene` が担当する。
    pub def enterRogueAlert(scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.RogueAlert);
        scene

    /// EnemyTurn フェーズに入る (全味方 waited または 敵ターン遷移時)。
    /// 動作 (表 6 行目): 味方系 3 range 全消し (敵ターン中は赤/青マス不要)。
    /// EnemyRange と cursor visible は触らない。
    /// 敵キューのビルドや log は `EnemyTurnDriverScene.beginTurn` 側で行うのでここでは扱わない。
    pub def enterEnemyTurn(scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.EnemyTurn);
        clearAllPlayerRanges(scene)
            // Shift の危険範囲(紫)は敵が動くと古くなるので敵ターン開始で消す（トグルは OFF に戻る）
            |> DangerZoneScene.clear
            |> PlayerScene.showAllActive       // 敵フェーズ中は味方を通常色(アクティブ)で見せる

    /// ItemSelect フェーズに入る (ActionMenu「アイテム」確定時)。
    /// 動作: 味方系の青/赤マスを片付けて、カーソルを隠す（メニュー操作専用画面のため）。
    /// EnemyRange は触らない。`ItemMenuScene.applyVisibility` が表示を毎フレーム反映する。
    pub def enterItemSelect(scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect);
        clearAllPlayerRanges(scene)
            |> CursorScene.setVisible(false)

    /// StaffAim フェーズに入る (杖「使う」確定時)。
    /// 動作: メニュー / overlay は触らず、通常カーソルを隠し、選択中プレイヤーの
    /// 隣接マス (デフォルト方向 Up) に矢印カーソルを表示する。方向キーで矢印を
    /// 回し、Z で発射する。
    pub def enterStaffAim(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        TurnPhase.State.put(TurnPhase.Phase.StaffAim);
        let withCursorHidden = CursorScene.setVisible(false, scene);
        match SelectedPlayer.State.get()#id {
            case None           => withCursorHidden
            case Some(playerId) =>
                match PlayerScene.get(playerId, withCursorHidden) {
                    case None         => withCursorHidden
                    case Some(player) =>
                        let withArrow =
                            ArrowCursorScene.showFor(player#gridPos, withCursorHidden);
                        // 回復の杖なら HP が減っている味方の方向に初期照準を向ける。
                        // 負傷味方が居ない / 回復杖でないならデフォルト(Up)のまま。
                        StaffCastScene.staffAimInitialDirection(playerId, withArrow)
                            |> Option.map(dir -> ArrowCursorScene.aim(dir, withArrow))
                            |> Option.getWithDefault(withArrow)
                }
        }

    /// ThrowAim フェーズに入る（アイテム「投げる」確定時）。StaffAim と同じ矢印カーソルを
    /// 選択中プレイヤーの隣接マス（デフォルト Up）に出すだけ。回復方向の初期照準は行わない
    /// （投擲は対象を読み合うので一律 Up から始める）。
    pub def enterThrowAim(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        TurnPhase.State.put(TurnPhase.Phase.ThrowAim);
        let withCursorHidden = CursorScene.setVisible(false, scene);
        match SelectedPlayer.State.get()#id {
            case None           => withCursorHidden
            case Some(playerId) =>
                match PlayerScene.get(playerId, withCursorHidden) {
                    case None         => withCursorHidden
                    case Some(player) => ArrowCursorScene.showFor(player#gridPos, withCursorHidden)
                }
        }

    /// AttackForecast フェーズに入る (PlayerAttack で敵に Z 押下時)。
    /// 動作: overlay/cursor は PlayerAttack 中の状態を温存し、フェーズだけ進める。
    /// `BattlePanelScene` の毎フレーム process が visible 切替と内容更新を担う。
    pub def enterAttackForecast(scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.AttackForecast);
        scene

    /// TradeTargetSelect / TradeInventory から ActionSelect に戻す共通動作。
    /// 緑マス overlay を片付けて TradeMenu の PanelData を初期値にリセットし、
    /// フェーズを戻す (ActionMenu は visibility で自動再表示される)。
    /// X キャンセル + 交換完了後の両方で呼ぶ。
    pub def enterActionSelectFromTrade(scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        scene
            |> TradeRangeScene.clear
            |> TradeMenuScene.mapPanelData(_ -> TradeMenuScene.defaultPanelData())

    /// TradeInventory フェーズに入る (TradeTargetSelect で Z 押下時の隣接 2 人交換)。
    /// 緑マス overlay を片付け (もう不要)、`members = [選択中味方, partnerId]` を PanelData に
    /// セットして `focus = 0 / pick = None / origin = FromTurn` に初期化する。
    /// カーソルは TradeInventory 中は使われないので隠す (ActionSelect から
    /// 戻ったときに再表示される)。
    pub def enterTradeInventory(partnerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        TurnPhase.State.put(TurnPhase.Phase.TradeInventory);
        let selfId = SelectedPlayer.State.get()#id |> Option.getWithDefault(0);
        scene
            |> TradeRangeScene.clear
            |> CursorScene.setVisible(false)
            |> TradeMenuScene.mapPanelData(_ ->
                ({members  = selfId :: partnerId :: Nil,
                  focus    = 0,
                  pick     = None,
                  origin   = TradeMenuScene.Origin.FromTurn,
                  marks    = Set#{},
                  markPane = None}: TradeMenuScene.PanelData))

    /// TradeInventory フェーズに入る (集合後の RogueMove「交換」確定時の N 人交換)。
    /// `members` は集合した生存メンバーの player id (ロード + 退避中の味方)。
    /// `origin = FromRogue` なので、交換を抜けると RogueMove に戻る。
    /// `members` の構築は RogueMove 側で行うが、集合対象が 1 人になる端ケースを
    /// その場で排除しきれないため、ここで 2 人未満ガードを入れる (防御)。
    pub def enterGatherTrade(members: List[Int32], scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        if (List.length(members) < 2) scene
        else {
            TurnPhase.State.put(TurnPhase.Phase.TradeInventory);
            scene
                |> CursorScene.setVisible(false)
                |> TradeMenuScene.mapPanelData(_ ->
                    ({members  = members,
                      focus    = 0,
                      pick     = None,
                      origin   = TradeMenuScene.Origin.FromRogue,
                      marks    = Set#{},
                      markPane = None}: TradeMenuScene.PanelData))
        }

    /// TradeTargetSelect フェーズに入る (ActionMenu「こうかん」確定時)。
    /// 動作 (上の表): 味方系の青/赤マスを片付け、緑マス (TradeRange) を敷き直し、
    ///                カーソルを表示し **最初の隣接味方マス** (reading order:
    ///                y 昇順 → x 昇順) にスナップする。
    /// 隣接味方が複数居るときは北 → 西 → 東 → 南の順で最も若いマスを選ぶ。
    /// 緑マスゼロ (= 隣接味方なし) のときは ActionMenu の「こうかん」項目自体が
    /// 出ないので、ここに来ることはない (防御的に選択中味方位置にスナップ)。
    pub def enterTradeTargetSelect(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State,
                              PlayerData.PartyQuery} =
        TurnPhase.State.put(TurnPhase.Phase.TradeTargetSelect);
        clearMoveOnlyRanges(scene)
            |> PlayerAttackRangeScene.clear
            |> EnemyRangeScene.clear
            |> EnemyAttackRangeScene.clear
            |> TradeRangeScene.show
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToFirstTradeCellOrPlayer
}
