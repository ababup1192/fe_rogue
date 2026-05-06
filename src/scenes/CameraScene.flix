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
///   - PlayerCursor → カーソルのワールド座標
///   - PlayerMoving → 直前の位置を維持。ただしプレイヤーが画面外に出たら追従に切替
///   - EnemyTurn    → プレイヤーのワールド座標（敵ターン中は味方を映す）
///
/// **ビューポートサイズ**:
///   designWi/Hi (= 128) と Camera の zoom (= 0.5) から、世界における「見えている矩形」の
///   半幅は `designWi / (2 * zoomX)` = 128 で求まる。これを `isPlayerVisible` の判定に使う。
mod CameraScene {

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "Camera"
    pub def cameraPath(): NodePath = name() :: Nil

    /// Player を子にしていた頃と同じズーム倍率を踏襲する（見え方を維持する）
    def defaultZoom(): Vec2.Vec2 = {x = 0.5, y = 0.5}

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// MapScene + PlayerScene 登録済みの scene にトップレベル Camera2D を追加する。
    /// 初期位置は id=0 のプレイヤー座標（パーティの代表位置）。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let initial = focusedPlayerWorldPos(0, scene);
        let cam = Camera2D.make(initial)
                  |> Camera2D.setZoom(defaultZoom());
        Scene.addNode(name(),
            EngineNode.Camera2DWithState(cam, NodeTag.NoTag),
            scene)

    // ────────────────────────────────────────────────────────
    // (D) ロジック
    // ────────────────────────────────────────────────────────

    /// gameLoop が毎フレーム末尾で呼ぶ更新フック。
    /// Tween による Player / Cursor の世界座標が反映された後に実行する。
    pub def update(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {TurnPhase.State, SelectedPlayer.State} =
        let phase = TurnPhase.State.get();
        let selected = SelectedPlayer.State.get()#id;
        let target = computeTarget(phase, selected, scene);
        Scene.mapEngineNode(cameraPath(),
            n -> Node2D.setPosition(target, n), scene)

    /// 各フェーズでカメラが向かうべきターゲット位置を計算する。
    /// `PlayerMoving` で「画面内なら維持」する分岐がここにあるため、計算は純粋関数で書く。
    /// `selected` が None のときはパーティの代表（id=0、または最初のアクティブ）の位置に向く。
    def computeTarget(phase: TurnPhase.Phase,
                       selected: Option[Int32],
                       scene: Scene[NodeTag]): Vec2.Vec2 =
        let focusId = focusIdOf(selected, scene);
        let focusPos = focusedPlayerWorldPos(focusId, scene);
        match phase {
            case TurnPhase.Phase.PlayerCursor =>
                cursorWorldPos(scene)
            case TurnPhase.Phase.PlayerMoving =>
                let camPos = currentPos(scene);
                if (isPlayerVisible(camPos, focusPos)) camPos
                else focusPos
            case TurnPhase.Phase.PlayerAttack =>
                // 攻撃フェーズはカーソルが赤マスを動く。PlayerCursor と同じく
                // カーソル追従でターゲットを表示できるようにする。
                cursorWorldPos(scene)
            case TurnPhase.Phase.PlayerAutoMove =>
                // 自動移動中は旗（行き先）を映して、味方が歩いてくるのを見守る。
                flagWorldPos(scene)
            case TurnPhase.Phase.EnemyTurn =>
                focusPos
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

    /// カメラ自身の現在ワールド座標。
    def currentPos(scene: Scene[NodeTag]): Vec2.Vec2 =
        Scene.globalPositionAt(cameraPath(), scene)

    /// `camPos` を中心としたビューポート内に `playerPos` があるか。
    /// half-extent は designWi/Hi と zoom から逆算する（zoom 0.5 で 256x256 世界 px）。
    /// 完全に画面外（境界 1 px 外）になったときに false を返す保守的な判定。
    def isPlayerVisible(camPos: Vec2.Vec2, playerPos: Vec2.Vec2): Bool =
        let halfW = Int32.toFloat64(Game.designWi()) / (2.0 * defaultZoom()#x);
        let halfH = Int32.toFloat64(Game.designHi()) / (2.0 * defaultZoom()#y);
        let dx = Float64.abs(playerPos#x - camPos#x);
        let dy = Float64.abs(playerPos#y - camPos#y);
        dx <= halfW and dy <= halfH
}
