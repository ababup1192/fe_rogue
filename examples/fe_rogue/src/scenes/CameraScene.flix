/// CameraScene — 単独のトップレベル Camera2D を持ち、フェーズに応じて追従先を切り替える
///
/// FE 風 SRPG では「カーソルにカメラを付ける／キャラ移動中はカメラを止める／
/// キャラが画面外に行ったらカメラを動かす／敵ターンはキャラを映す」という複合追従を
/// 実装する必要がある。Camera2D を Player の子にすると Player にしか追従できないため、
/// 親子関係を断ち切ってトップレベルに置き、毎フレーム `update` で位置を計算する形に変える。
///
/// ノード構造（トップレベル）:
///   Camera (Camera2D, NodeTag.NoTag)
///
/// 追従ルール（`TurnPhase.State.get` で分岐）:
///   - PlayerCursor    → カーソルのワールド座標
///   - PlayerMoving    → 選択中味方のワールド座標（drag margin で「画面内なら据え置き」が
///                        engine の Camera2D 側で自動的に効く）
///   - PlayerAttack    → カーソルのワールド座標（赤マスを動くカーソルに追従）
///   - PlayerAutoMove  → ロード(id 0)のワールド座標（合流先 = ロードを映す）
///   - RogueMove       → ロード(id 0)のワールド座標（自由歩行するロードに追従）
///   - RogueAlert      → 発見演出の焦点（同部屋なら部屋中心 / 索敵範囲なら検知した敵）
///   - EnemyTurn       → **alerted な敵が行動中ならその敵を映す**（`enemyTurnTarget`）。
///                        attacking 中の敵 > キュー先頭の敵 > 非 alerted ならプレイヤーへフォールバック
///
/// **追従の滑らかさ**:
///   `CameraScene.scene.json` の `positionSmoothingEnabled` / `dragHorizontalEnabled` /
///   `dragLeftMargin` 等で engine 組込の追従プロパティを宣言しており、
///   smoothing と drag margin は `Camera2D.process` が毎フレーム適用する。
///   CameraScene の責務は「フェーズ → どのノードを見るか」だけ（target 選択）。
///   滑らか追従や画面端マージンは engine が担当するため、手書きの `isPlayerVisible` 等は撤廃。
mod CameraScene {

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "Camera"
    pub def cameraPath(): NodePath = name() :: Nil

    /// scene.json への相対パス（cwd = プロジェクトルート想定）
    def scenePath(): String = AssetPath.resolve("src/scenes/CameraScene.scene.json")

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// MapScene + PlayerScene 登録済みの scene にトップレベル Camera2D を追加する。
    /// レイアウトと追従パラメータ（zoom / smoothing / drag margin）は scene.json
    /// に閉じ込めてあり、CameraScene 側は「フェーズ → target」のディスパッチだけ持つ。
    /// 初期 smoothPosition は scene.json の pos (0,0) になるが、最初の `update` で
    /// 正しいフォーカス位置に上書きされる（drag margin で 1〜2 フレーム後に追従完了）。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead} =
        let initial = focusedPlayerWorldPos(0, scene);
        SceneLoader.loadScene(scenePath(),
                               SceneLoader.constTagParser(NodeTag.NoTag),
                               scene)
            // パーティ先頭の位置で position と smoothPosition を初期化して、
            // ゲーム開始時点のスナップ違和感を消す
            |> Scene.mapEngineNode(cameraPath(),
                n -> EngineNode.mapCamera2D(c ->
                    c |> Node2D.setPosition(initial)
                      |> Camera2D.setSmoothPosition(initial), n))

    // ────────────────────────────────────────────────────────
    // (D) ロジック
    // ────────────────────────────────────────────────────────

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から、Camera ノードに
    /// 対して dispatch される (Camera は 1 個のみなので 1 フレーム 1 回)。
    /// Tween / AnimationPlayer による Player / Cursor の世界座標が反映された後に実行する。
    /// 動作:
    ///   1. フェーズに応じてターゲット NodePath の world 位置を取る
    ///   2. Camera2D.position に target をセット（engine の追従計算の入力）
    ///   3. Camera2D.process(delta, viewport, ...) で smoothPosition を進める
    /// 「画面内なら維持」「滑らかに追従」は engine の drag margin / smoothing が代替する。
    /// 注: 戻り値の node は engine の `processAll` が path に書き戻すので、scene 経由で
    /// `mapEngineNode(cameraPath, ...)` する代わりに **node 自体** を更新して返すこと
    /// (そうしないと古い node で上書きされてカメラが動かない)。
    pub def process(delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {GameEngine.Game, EnemyTurn.Queue,
                        TurnPhase.State, SelectedPlayer.State,
                        PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        let phase = TurnPhase.State.get();
        let selected = SelectedPlayer.State.get()#id;
        let target = computeTarget(phase, selected, scene);
        let vp = GameEngine.Game.getViewportRect();
        let viewport = {viewportWidth = vp#size#x, viewportHeight = vp#size#y};
        let newNode = EngineNode.mapCamera2D(
            c -> c |> Node2D.setPosition(target)
                   |> Camera2D.process(delta, viewport),
            node);
        (newNode, scene)

    /// 各フェーズでカメラが向かうべきターゲット位置を計算する。
    /// `selected` が None のときはパーティの代表（id=0、または最初のアクティブ）の位置に向く。
    /// PlayerMoving の「画面内なら維持」は engine の drag margin が引き受けるため、
    /// この関数は単に「選択中味方の位置」を返すだけになる。
    /// EnemyTurn は `enemyTurnTarget` で「alerted な敵の動きを映す」分岐に入る。
    def computeTarget(phase: TurnPhase.Phase,
                       selected: Option[Int32],
                       scene: Scene[NodeTag]): Vec2.Vec2
            \ {EnemyTurn.Queue, PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        let focusId = focusIdOf(selected);
        let focusPos = focusedPlayerWorldPos(focusId, scene);
        match phase {
            case TurnPhase.Phase.PlayerCursor     => cursorWorldPos(scene)
            case TurnPhase.Phase.PlayerMoving     => focusPos
            case TurnPhase.Phase.ActionSelect     =>
                // SelectedPlayer = None でメニューを開くのは 2 系統あり、由来で追従先が違う:
                //   - PlayerCursor 由来 (集合メニュー)     → カーソルにカメラを保つ
                //   - RogueMove 由来 (ひろう / かいさん)   → ロードを映す
                // RogueMove 中はカーソルが非表示で更新されず集合地点に置き去りなので、
                // cursorWorldPos を使うとカメラが集合した場所へ飛んでしまう。
                // 由来の判別は onActionCancelled と同じく hiddenAllies 非空 = ローグ由来。
                match selected {
                    case Some(_) => focusPos
                    case None    =>
                        if (not List.isEmpty(PlayerScene.hiddenAllies(scene)))
                            lordWorldPos(scene)
                        else
                            cursorWorldPos(scene)
                }
            case TurnPhase.Phase.ItemSelect       => focusPos
            case TurnPhase.Phase.ItemActionSelect => focusPos
            case TurnPhase.Phase.StaffAim         => focusPos
            case TurnPhase.Phase.AttackForecast   => cursorWorldPos(scene)
            case TurnPhase.Phase.PlayerAttack     => cursorWorldPos(scene)
            case TurnPhase.Phase.PlayerAttackHold => cursorWorldPos(scene)
            // レベルアップ表示中はレベルアップした味方（選択中の駒）を映したまま据え置く。
            case TurnPhase.Phase.LevelUpView      => focusPos
            case TurnPhase.Phase.TradeTargetSelect => cursorWorldPos(scene)
            case TurnPhase.Phase.TradeInventory    => focusPos
            case TurnPhase.Phase.PlayerAutoMove   => lordWorldPos(scene)
            case TurnPhase.Phase.RogueMove        => lordWorldPos(scene)
            case TurnPhase.Phase.RogueAlert       => AutoMoveScene.alertInfo(scene)#focus
            case TurnPhase.Phase.EnemyTurn        => enemyTurnTarget(focusPos, scene)
        }

    /// 敵ターン中のカメラターゲットを決める。
    /// 優先順位:
    ///   1. **attacking 中の敵** (attack_lunge アニメ中の敵) → 攻撃の見せ場を映す
    ///   2. **キュー先頭の敵** (移動中 / 次に行動する敵)
    /// その敵が `alerted` なら追従、非 alerted (Skip フェーズ) なら fallback (プレイヤー位置)。
    /// 「敵に発見されている状態では敵の動きが見える」ようにするためのロジック。
    def enemyTurnTarget(fallback: Vec2.Vec2, scene: Scene[NodeTag]):
            Vec2.Vec2 \ {EnemyTurn.Queue, EnemyScene.RosterQuery} =
        let activeId = match attackingEnemyId() {
            case Some(id) => Some(id)
            case None     => match EnemyTurn.Queue.peekFront() {
                case Some(step) => Some(step#id)
                case None       => None
            }
        };
        match activeId {
            case None     => fallback
            case Some(id) =>
                match EnemyScene.RosterQuery.get(id) {
                    case Some(d) =>
                        if (d#alerted)
                            Scene.globalPositionAt(EnemyScene.enemyPath(id), scene)
                        else fallback
                    case None => fallback
                }
        }

    /// attack_lunge 中の敵 id を 1 つ返す。`stepEnemyTurn` が attacking 中は他の step を
    /// 進めない設計なので、複数 attacking 状態は通常起きない（防御的に head を取る）。
    def attackingEnemyId(): Option[Int32] \ EnemyScene.RosterQuery =
        EnemyScene.RosterQuery.getAll()
            |> List.filterMap(e ->
                if (Option.nonEmpty(e#attackTargetId)) Some(e#id) else None)
            |> List.head

    // ────────────────────────────────────────────────────────
    // (E) カメラ追従の到達判定
    // ────────────────────────────────────────────────────────

    /// 現在のカメラ target に smoothPosition が「drag dead zone 内」に収まったか。
    /// 敵ターン中、カメラが新しい敵に切り替わったあと「カメラが到達するまで敵の行動を待つ」
    /// gating に使う（`stepEnemyTurn` の冒頭で `not isSettled(scene)` なら処理スキップ）。
    ///
    /// 判定式は `Camera2D.isWithinDragDeadZone` に閉じてあり、drag margin の幾何から
    /// 収束 threshold を逆算する（drag 有効時 = `worldHalf × dragMargin` + 2 px buffer、
    /// drag 無効時 = 4 px）。viewport size が必要なため `GameEngine.Game` 効果を使う。
    /// カメラノードが未登録の場合は true を返す（テスト/初期化時の安全側）。
    pub def isSettled(scene: Scene[NodeTag]): Bool \ GameEngine.Game =
        match Scene.getEngineNode(cameraPath(), scene) {
            case Some(EngineNode.Camera2DWithState(cam, _)) =>
                let vp = GameEngine.Game.getViewportRect();
                Camera2D.isWithinDragDeadZone(cam,
                    {viewportWidth = vp#size#x, viewportHeight = vp#size#y})
            case _ => true
        }

    /// 「いまカメラが向くべき」プレイヤー id を選ぶ。
    /// 選択中があればそれ、無ければパーティ先頭（id=0、それも無ければ 0 fallback）。
    def focusIdOf(selected: Option[Int32]): Int32 \ PlayerScene.PartyQuery =
        match selected {
            case Some(id) => id
            case None     =>
                match List.head(PlayerScene.PartyQuery.getAll()) {
                    case Some(d) => d#id
                    case None    => 0
                }
        }

    // ────────────────────────────────────────────────────────
    // 内部: 座標取得
    // ────────────────────────────────────────────────────────

    /// 指定 id のプレイヤーの現在ワールド座標。Tween 中ならその時点の補間位置を返す。
    /// 該当 id が登録されていなければ scene の原点（0,0）を返す。
    def focusedPlayerWorldPos(id: Int32, scene: Scene[NodeTag]): Vec2.Vec2 =
        match Scene.getEngineNode(PlayerScene.playerPath(id), scene) {
            case Some(_) => Scene.globalPositionAt(PlayerScene.playerPath(id), scene)
            case None    => Vec2.zero()
        }

    /// カーソルの現在ワールド座標。CursorScene 未登録なら原点を返すが、`add` 後に
    /// `update` を呼ぶ運用なので実機では到達しない。
    def cursorWorldPos(scene: Scene[NodeTag]): Vec2.Vec2 =
        Scene.globalPositionAt(CursorScene.cursorPath(), scene)

    /// ローグ移動モード中のカメラ target = ロード(id 0)のワールド座標。
    /// 合流中(PlayerAutoMove)はロードに味方が集まり、自由歩行中(RogueMove)はロードが動くので、
    /// どちらもロードを映していれば見せ場を外さない。
    def lordWorldPos(scene: Scene[NodeTag]): Vec2.Vec2 =
        focusedPlayerWorldPos(0, scene)
}
