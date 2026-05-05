/// PlayerScene — プレイヤーキャラクター（CharacterBody2D）と子 Sprite / 子 Camera
///
/// ノード構造（Godot 準拠）:
///   Player (CharacterBody2D, NodeTag.Player(Data))
///     ├─ Sprite (Sprite2D, 描画専用)
///     └─ Camera (Camera2D, 親追従でビューが Player を中心に表示)
///
/// シーン構造とプロパティは PlayerScene.scene.json で管理し、`add` 時に
/// SceneLoader でロードする。NodeTag の Data はロード後に `Scene.setState` で書き込む。
///
/// 移動は moveTo(target) で論理位置（gridPos）を即更新し、
/// 見た目は engine 層の `Tween` モジュール（`Tween.Scheduler.tweenPosition`）に委ね、
/// 毎フレーム gameLoop が `Tween.tickAll` で進める。**壁判定は BoardLogic が
/// moveTo を呼ぶ前に済ませている前提**で、PlayerScene 自身は衝突応答も補間も持たない。
/// Camera は Player の子なので親子変換で自動追従する。
mod PlayerScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// プレイヤー固有の状態。
    /// gridPos: 盤面上の駒の論理位置。moveTo で即座に更新される。BoardLogic が読む値。
    pub type alias Data = {
        gridPos = Vec2.Vec2i
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "Player"
    pub def playerPath(): NodePath = name() :: Nil

    def sceneJsonPath(): String = "src/scenes/PlayerScene.scene.json"

    /// プレイヤーの初期グリッド座標。PlayerScene.scene.json の `pos` と
    /// 整合させる必要がある（タイル中心座標で 16 倍 + 8 のオフセット）。
    pub def initialGrid(): Vec2.Vec2i = {x = 5, y = 5}

    /// 1 マス分の slide にかかる時間（秒）。Godot の tween_property の duration 相当
    def slideDuration(): Float64 = 16.0 / 120.0   // ≈ 0.133 秒

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    def initialData(): Data = { gridPos = initialGrid() }

    /// PlayerScene.scene.json から Player / Sprite / Camera を読み込んで Scene に追加する。
    /// JSON にはノード構造とプロパティのみが入っており、NodeTag のデータは
    /// ここで Scene.setState によって注入する。
    /// 全ノードは constTagParser により NoTag でロードし、Player ノードだけ
    /// ここで NodeTag.Player(initialData()) に差し替える。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead} =
        SceneLoader.loadScene(sceneJsonPath(),
                              SceneLoader.constTagParser(NodeTag.NoTag),
                              scene)
            |> Scene.setState(playerPath(), NodeTag.Player(initialData()))

    // ────────────────────────────────────────────────────────
    // (D) ロジック
    // ────────────────────────────────────────────────────────

    /// 目標グリッドへの移動を開始する。**壁判定は呼び出し側（BoardLogic）が済ませている前提**で、
    /// PlayerScene 自身は衝突判定を考えない。
    ///
    /// gridPos を即更新（論理位置）し、`Tween.Scheduler.tweenPosition` で
    /// 見た目の補間を engine に委ねる（Godot の `tween.tween_property(self, "position", ...)` 同等）。
    pub def moveTo(map: MapSnapshot, target: Vec2.Vec2i, scene: Scene[NodeTag]):
            Scene[NodeTag] \ Tween.Scheduler =
        let targetWorld = map#gridToWorld(target);
        let startWorld = Scene.globalPositionAt(playerPath(), scene);
        Tween.tweenPosition(playerPath(), startWorld, targetWorld, slideDuration());
        scene |> mapPlayer((body, _data) -> (body, {gridPos = target}))

    /// プレイヤーが現在 tween 中（次の入力を受け付けない状態）か。
    /// physicsProcess は連打や長押しでもこの間は moveTo を発火しない。
    pub def isMoving(): Bool \ Tween.Scheduler =
        Tween.Scheduler.isActive(playerPath())

    /// 毎フレーム engine から呼ばれる。tween 中でなければ方向キーの押下状態を polling し、
    /// 押されていれば次の moveTo を発火する（押しっぱなしで 1 マスずつ滑らかに連続移動する仕掛け）。
    /// `InputEvent.onKeyPressed` は押下エッジ専用で echo events が来ないため、
    /// 連続移動はここでの per-frame polling で実現する。
    /// Game.flix の Node[NodeTag] redef からディスパッチされる。
    pub def physicsProcess(_delta: Float64,
                            node: EngineNode[NodeTag],
                            _path: NodePath,
                            scene: Scene[NodeTag]):
                           (EngineNode[NodeTag], Scene[NodeTag])
                           \ {GameEngine.Game, BoardQuery, Tween.Scheduler} =
        match node {
            case EngineNode.Body2DWithState(_, NodeTag.Player(_)) =>
                if (isMoving()) (node, scene)
                else
                    match readHeldDirection() {
                        case None    => (node, scene)
                        case Some(d) =>
                            let board = BoardQuery.board();
                            match BoardLogic.tryMove(board, d) {
                                case None         => (node, scene)
                                case Some(target) =>
                                    // moveTo は scene 内の Player ノードの gridPos を更新するが、
                                    // Scene.foldNodes は f が返した (newEn, s1) のうち newEn で
                                    // path 位置を上書きするため、戻り値の node も更新後の scene
                                    // から取り直さないと gridPos が古い値に巻き戻る。
                                    let nextScene = moveTo(board#map, target, scene);
                                    let nextNode = match Scene.getEngineNode(playerPath(), nextScene) {
                                        case Some(en) => en
                                        case None     => node
                                    };
                                    (nextNode, nextScene)
                            }
                    }
            case _ => (node, scene)
        }

    /// 押されている方向キーを Option で返す（複数同時押しは上 > 下 > 左 > 右 の優先順位）
    def readHeldDirection(): Option[Vec2.Vec2i] \ GameEngine.Game =
        let isDown = key -> GameEngine.Game.isKeyPressed(key);
        if      (isDown(GameEngine.Key.W) or isDown(GameEngine.Key.Up))    Some(Vec2.upI())
        else if (isDown(GameEngine.Key.S) or isDown(GameEngine.Key.Down))  Some(Vec2.downI())
        else if (isDown(GameEngine.Key.A) or isDown(GameEngine.Key.Left))  Some(Vec2.leftI())
        else if (isDown(GameEngine.Key.D) or isDown(GameEngine.Key.Right)) Some(Vec2.rightI())
        else None

    // ────────────────────────────────────────────────────────
    // (E) ボイラプレート — pattern match を関数化
    // ────────────────────────────────────────────────────────

    /// Player の CharacterBody2D と Data をまとめて変換する
    pub def mapPlayer(f: (CharacterBody2D, Data) -> (CharacterBody2D, Data),
                       scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(playerPath(), engineNode -> match engineNode {
            case EngineNode.Body2DWithState(body, NodeTag.Player(data)) =>
                let (newBody, newData) = f(body, data);
                EngineNode.Body2DWithState(newBody, NodeTag.Player(newData))
            case other => other
        }, scene)

    /// Player の Data を取り出す（存在しない場合は bug!）
    pub def getPlayerData(scene: Scene[NodeTag]): Data =
        match Scene.getState(playerPath(), scene) {
            case Some(NodeTag.Player(data)) => data
            case _ => bug!("PlayerScene: player not found at ${playerPath()}")
        }

    /// プレイヤーの現在グリッド座標。BoardLogic 等が移動可否判定の起点として使う
    pub def getGridPos(scene: Scene[NodeTag]): Vec2.Vec2i =
        getPlayerData(scene)#gridPos
}
