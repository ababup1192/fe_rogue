/// CameraScene — フェーズに応じてカメラの追従先（World 座標）を選ぶ driver
///
/// FE 風 SRPG では「カーソルにカメラを付ける／キャラ移動中はカメラを止める／
/// キャラが画面外に行ったらカメラを動かす／敵ターンはキャラを映す」という複合追従を
/// 実装する。カメラの状態は World の `cameraSmoothPos`（実際に映している点）ただ 1 つで、
/// 毎フレーム `step` が「フェーズ → どの World 座標を見るか」だけを決めて `CameraFollow.step` に渡し、
/// 進んだ smoothPos を World へ書き戻す。滑らか追従・画面端の余白（deadZone）は `CameraFollow` の純粋計算が担う。
///
/// 追従ルール（`TurnPhase.State.get` で分岐）:
///   - PlayerCursor    → カーソルのワールド座標
///   - PlayerMoving    → 選択中味方のワールド座標。**移動モード中はキャラを画面中央に固定**
///                        したいので余白を切り（`isCenteredPhase`）、smoothing だけで
///                        キャラ中心へ寄せる（余白ありだと「画面内なら据え置き」になり中央に来ない）
///   - PlayerAttack    → カーソルのワールド座標（赤マスを動くカーソルに追従）
///   - GatherMove      → 主人公(id 0)のワールド座標（隊列を率いて動く主人公に追従）
///   - EnemyTurn       → **alerted な敵が行動中ならその敵を映す**（`enemyTurnTarget`）。
///                        attacking 中の敵 > キュー先頭の敵 > 非 alerted ならプレイヤーへフォールバック
///
/// 追従先の座標は **World 権威**（`renderPosOf` の描画位置、未 seed の静止駒は `posOf` のセル中心）で読み、
/// カーソルは `CursorState.renderPos`（スライド補間の視覚位置＝単一権威）を読む。
/// 駒 pixel 位置は World store が権威（scene ノードの座標は読まない）。
mod CameraScene {

    /// 毎フレーム 1 回、フェーズ別ターゲットを計算して `CameraFollow.step` で 1 ステップ進め、
    /// 進んだ smoothPos を `Cmd.SetCameraSmoothPos` で World へ書き戻す（frame-paced driver）。
    /// gameLoop が移動 tween・戦闘演出クロックで駒・カーソルの世界座標が反映された後に呼ぶ。
    /// カメラの唯一の状態は World の cameraSmoothPos。ターゲットは World / 各 query 由来で毎フレーム再計算する。
    /// カメラは盤面がある画面でのみ追従する（Title 等の盤面レス画面は空回りさせない）。
    pub def step(delta: Duration.Duration):
                    Unit
                    \ {GameEngine.Game, EnemyTurn.Queue,
                        SelectedPlayer.State,
                        PlayerData.PartyQuery, EnemyData.RosterQuery,
                        CursorState.State, World.WorldQuery, World.Command, TurnPhase.State} =
        let world = World.WorldQuery.get();
        if (not World.hasBoard(world)) ()
        else {
            let phase = TurnPhase.State.get();
            let selected = SelectedPlayer.State.get()#id;
            let target = computeTarget(phase, selected, world);
            let vp = GameEngine.Game.getViewportRect();
            let viewport = {width = vp#size#x, height = vp#size#y};
            // 追従を 1 ステップ進め、映している点を World へ書き戻す（他 driver と同じく emit を明示する）。
            let smoothPos = Camera.chase(World.cameraSmoothPosOf(world), target,
                                         isCenteredPhase(phase), CameraView.config(), delta, viewport);
            World.Command.emit(World.Cmd.SetCameraSmoothPos(smoothPos))
        }

    /// フロア構築時にカメラをパーティ先頭（id 0）へスナップする（カメラ初期位置の唯一の設定点）。
    /// `WorldSetup.setupHudAndDrivers` が PlayerScene.add（World へ位置 seed）後に 1 回呼ぶ。
    /// これで開始フレームから正しいフォーカス位置を映す（smoothing の 1〜2 フレーム遅れを消す）。
    pub def snapToParty(): Unit \ {World.WorldQuery, World.Command} =
        let world = World.WorldQuery.get();
        World.Command.emit(World.Cmd.SetCameraSmoothPos(
            unitWorldPos(World.EntityRef.Player(0), world)))

    /// カメラがターゲットの余白（deadZone）内に収まったか。
    /// 敵ターン中、カメラが新しい敵に切り替わったあと「カメラが到達するまで敵の行動を待つ」
    /// gating に使う（`stepEnemyTurn` の冒頭で `not isSettled()` なら処理スキップ）。
    /// ターゲットを保存せず `computeTarget` で毎フレーム再導出するのは、`step` と必ず同じ
    /// ターゲットで判定するための parity 上の選択（driver ローカルにターゲットを組むと
    /// `enemyTurnTarget` の選択規則とズレる）。そのぶん query effect が要るが、gameLoop が
    /// `step` 経由で既に保持しているため上流への波及はない。
    /// 呼び出し文脈（敵ターン / 階段退場）はどちらも非 centered ＝余白ありで判定される。
    pub def isSettled(): Bool
            \ {GameEngine.Game, EnemyTurn.Queue,
                SelectedPlayer.State,
                PlayerData.PartyQuery, EnemyData.RosterQuery,
                CursorState.State, World.WorldQuery, TurnPhase.State} =
        let world = World.WorldQuery.get();
        let phase = TurnPhase.State.get();
        let selected = SelectedPlayer.State.get()#id;
        let target = computeTarget(phase, selected, world);
        let vp = GameEngine.Game.getViewportRect();
        let viewport = {width = vp#size#x, height = vp#size#y};
        Camera.settled(World.cameraSmoothPosOf(world), target,
                       isCenteredPhase(phase), CameraView.config(), viewport)

    /// 「キャラを画面中央に固定する」フェーズか。移動モード (PlayerMoving) のみ true。
    /// true の間は余白（deadZone）を切ってキャラ中心に寄せる（`CameraFollow.step`）。
    def isCenteredPhase(phase: TurnPhase.Phase): Bool =
        match phase {
            case TurnPhase.Phase.PlayerMoving => true
            case _                            => false
        }

    /// `selected` が None のときはパーティの代表（id=0、または最初のアクティブ）の位置に向く。
    /// PlayerMoving は「選択中味方の位置」を返すだけ（中央固定の余白制御は `step` 側の
    /// `isCenteredPhase` → `CameraFollow.step` が担当する）。
    /// EnemyTurn は `enemyTurnTarget` で「alerted な敵の動きを映す」分岐に入る。
    def computeTarget(phase: TurnPhase.Phase,
                      selected: Option[Int32],
                      world: World): Vec2.Vec2
            \ {EnemyTurn.Queue, PlayerData.PartyQuery, EnemyData.RosterQuery, CursorState.State} =
        let focusId = focusIdOf(selected);
        let focusPos = unitWorldPos(World.EntityRef.Player(focusId), world);
        match phase {
            case TurnPhase.Phase.PlayerCursor     => cursorWorldPos()
            case TurnPhase.Phase.PlayerMoving     => focusPos
            case TurnPhase.Phase.ActionSelect     =>
                // SelectedPlayer あり (味方メニュー / 集合の隣接メニュー=主人公) は対象を映す。
                // None (空マスメニュー) はカーソルに保つ。
                match selected {
                    case Some(_) => focusPos
                    case None    => cursorWorldPos()
                }
            // 武器選択中は攻撃する味方（選択中の駒）を映したまま（ActionSelect と同じ挙動）。
            case TurnPhase.Phase.WeaponSelect     => focusPos
            case TurnPhase.Phase.ItemSelect       => focusPos
            case TurnPhase.Phase.ItemActionSelect => focusPos
            case TurnPhase.Phase.StaffAim         => focusPos
            case TurnPhase.Phase.ThrowAim         => focusPos
            case TurnPhase.Phase.AttackForecast   => cursorWorldPos()
            case TurnPhase.Phase.PlayerAttack     => cursorWorldPos()
            case TurnPhase.Phase.PlayerAttackHold => cursorWorldPos()
            // レベルアップ表示中はレベルアップした味方（選択中の駒）を映したまま据え置く。
            case TurnPhase.Phase.LevelUpView      => focusPos
            case TurnPhase.Phase.TradeTargetSelect => cursorWorldPos()
            case TurnPhase.Phase.TradeInventory    => focusPos
            case TurnPhase.Phase.GatherMove       => unitWorldPos(World.EntityRef.Player(0), world)
            // 階段離脱中は代表キャラ（=パーティ近辺）を映したまま据え置く。
            case TurnPhase.Phase.StairsExit       => focusPos
            case TurnPhase.Phase.EnemyTurn        => enemyTurnTarget(focusPos, world)
            // 全滅メニュー中は盤面フリーズ。代表キャラを映したまま据え置く。
            case TurnPhase.Phase.GameOver         => focusPos
            // 中断確認中も盤面はそのまま。カーソル位置に保つ（空マスメニューから入るため）。
            case TurnPhase.Phase.SuspendConfirm   => cursorWorldPos()
        }

    /// 敵ターン中のカメラターゲットを決める。
    /// 優先順位:
    ///   1. **attacking 中の敵** (lunge モーション中の敵) → 攻撃の見せ場を映す
    ///   2. **キュー先頭の敵** (移動中 / 次に行動する敵)
    /// その敵が `alerted` なら追従、非 alerted (Skip フェーズ) なら fallback (プレイヤー位置)。
    /// 「敵に発見されている状態では敵の動きが見える」ようにするためのロジック。
    def enemyTurnTarget(fallback: Vec2.Vec2, world: World):
            Vec2.Vec2 \ {EnemyTurn.Queue, EnemyData.RosterQuery} =
        // 注目する敵: lunge 中の敵を優先、居なければキュー先頭。内側 match は Option.map に畳む。
        let activeId = match attackingEnemyId() {
            case Some(id) => Some(id)
            case None     => EnemyTurn.Queue.peekFront() |> Option.map(step -> step#id)
        };
        // activeId → その敵 Data を forM で引き、alerted なら敵を、それ以外(未発見/不在)は fallback を注視。
        let target = forM (
            id <- activeId;
            d  <- EnemyData.RosterQuery.get(id)
        ) yield (if (d#alerted) unitWorldPos(World.EntityRef.Enemy(id), world) else fallback);
        Option.getWithDefault(fallback, target)

    /// lunge 中の敵 id を 1 つ返す。`stepEnemyTurn` が attacking 中は他の step を
    /// 進めない設計なので、複数 attacking 状態は通常起きない（防御的に head を取る）。
    def attackingEnemyId(): Option[Int32] \ EnemyData.RosterQuery =
        EnemyData.RosterQuery.getAll()
            |> List.filterMap(e ->
                if (Option.nonEmpty(e#attackTargetId)) Some(e#id) else None)
            |> List.head

    /// 「いまカメラが向くべき」プレイヤー id を選ぶ。
    /// 選択中があればそれ、無ければパーティ先頭（id=0、それも無ければ 0 fallback）。
    def focusIdOf(selected: Option[Int32]): Int32 \ PlayerData.PartyQuery =
        match selected {
            case Some(id) => id
            case None     =>
                match List.head(PlayerData.PartyQuery.getAll()) {
                    case Some(d) => d#id
                    case None    => 0
                }
        }

    /// 指定 entity の現在ワールド座標を World store から読む。
    /// 移動 tween 中/移動済みは `renderPosOf`（描画位置の権威）、まだ動いていない静止駒は renderPos が
    /// 未 seed なので `posOf` のセル中心へフォールバックする（spawn 時の初期描画位置 = セル中心と一致）。
    /// 未登録 entity は原点（初期化前に呼ばれた場合の安全側）。
    def unitWorldPos(ref: World.EntityRef, world: World): Vec2.Vec2 =
        match World.renderPosOf(ref, world) {
            case Some(p) => p
            case None    =>
                match World.posOf(ref, world) {
                    case Some(g) => MapSnapshot.cellCenter(g)
                    case None    => Vec2.zero()
                }
        }

    /// カーソルの現在ワールド座標。`CursorState.renderPos`（スライド補間の視覚位置＝単一権威）を読む。
    def cursorWorldPos(): Vec2.Vec2 \ CursorState.State =
        CursorState.renderPos()
}
