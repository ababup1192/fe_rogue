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
///   - PlayerAutoMove  → 旗のワールド座標
///   - EnemyTurn       → プレイヤーのワールド座標（敵ターン中は味方を映す）
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
    def scenePath(): String = "src/scenes/CameraScene.scene.json"

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

    /// gameLoop が毎フレーム末尾で呼ぶ更新フック。
    /// Tween / AnimationPlayer による Player / Cursor の世界座標が反映された後に実行する。
    /// 動作:
    ///   1. フェーズに応じてターゲット NodePath の world 位置を取る
    ///   2. Camera2D.position に target をセット（engine の追従計算の入力）
    ///   3. Camera2D.process(delta, viewport, ...) で smoothPosition を進める
    /// 「画面内なら維持」「滑らかに追従」は engine の drag margin / smoothing が代替する。
    pub def update(delta: Duration.Duration, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, TurnPhase.State, SelectedPlayer.State} =
        let phase = TurnPhase.State.get();
        let selected = SelectedPlayer.State.get()#id;
        let target = computeTarget(phase, selected, scene);
        let vp = GameEngine.Game.getViewportRect();
        let viewport = {viewportWidth = vp#size#x, viewportHeight = vp#size#y};
        Scene.mapEngineNode(cameraPath(),
            n -> EngineNode.mapCamera2D(c ->
                c |> Node2D.setPosition(target)
                  |> Camera2D.process(delta, viewport), n),
            scene)

    /// 各フェーズでカメラが向かうべきターゲット位置を計算する純粋関数。
    /// `selected` が None のときはパーティの代表（id=0、または最初のアクティブ）の位置に向く。
    /// PlayerMoving の「画面内なら維持」は engine の drag margin が引き受けるため、
    /// この関数は単に「選択中味方の位置」を返すだけになる。
    def computeTarget(phase: TurnPhase.Phase,
                       selected: Option[Int32],
                       scene: Scene[NodeTag]): Vec2.Vec2 =
        let focusId = focusIdOf(selected, scene);
        let focusPos = focusedPlayerWorldPos(focusId, scene);
        match phase {
            case TurnPhase.Phase.PlayerCursor   => cursorWorldPos(scene)
            case TurnPhase.Phase.PlayerMoving   => focusPos
            case TurnPhase.Phase.PlayerAttack   => cursorWorldPos(scene)
            case TurnPhase.Phase.PlayerAutoMove => flagWorldPos(scene)
            case TurnPhase.Phase.EnemyTurn      => focusPos
        }

    /// 「いまカメラが向くべき」プレイヤー id を選ぶ。
    /// 選択中があればそれ、無ければパーティ先頭（id=0、それも無ければ 0 fallback）。
    def focusIdOf(selected: Option[Int32], scene: Scene[NodeTag]): Int32 =
        match selected {
            case Some(id) => id
            case None     =>
                match List.head(PlayerScene.getAll(scene)) {
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

    /// 旗の現在ワールド座標。FlagScene 未登録なら原点。
    /// 立てていない場合 Marker2D の位置はダミーだが、PlayerAutoMove フェーズにしか
    /// 参照されないので、立てた直後は必ず正しい位置にある。
    def flagWorldPos(scene: Scene[NodeTag]): Vec2.Vec2 =
        match Scene.getEngineNode(FlagScene.flagPath(), scene) {
            case Some(_) => Scene.globalPositionAt(FlagScene.flagPath(), scene)
            case None    => Vec2.zero()
        }
}
