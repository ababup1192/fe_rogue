/// PlayerScene — プレイヤーキャラクター（CharacterBody2D）と子 Sprite / 子 Camera
///
/// ノード構造（Godot 準拠）:
///   Player (CharacterBody2D, NodeTag.Player(Data))
///     ├─ Sprite (Sprite2D, 描画専用)
///     └─ Camera (Camera2D, 親追従でビューが Player を中心に表示)
///
/// シーン構造とプロパティは PlayerScene.scene.json で管理し、`add` 時に
/// SceneLoader でロードする。NodeTag のデータ（pendingMotion 等）だけは
/// JSON に含めず、ロード後に `Scene.setState` で書き込む。
///
/// 移動指示は `Data#pendingMotion` に積み、physicsProcess が CharacterBody2D.moveAndCollide で
/// 消費する（衝突応答はエンジン側に委譲）。
/// Camera は Player の子なので、`findActiveCamera` がシーンツリーから求めた global 座標を
/// 介して自動追従する（手動同期不要）。
mod PlayerScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// プレイヤー固有の状態（Godot のキャラクタ固有メンバ変数相当）。
    /// CharacterBody2D の拡張ではなく、ゲーム側 state として保持する。
    pub type alias Data = {
        pendingMotion = Vec2.Vec2  // 次の physicsProcess で消費される移動指示
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "Player"
    pub def playerPath(): NodePath = name() :: Nil

    def sceneJsonPath(): String = "src/scenes/PlayerScene.scene.json"

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    def initialData(): Data = { pendingMotion = Vec2.zero() }

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

    /// 入力イベント等から呼ばれ、1 グリッド分の移動指示を pendingMotion に積む。
    /// 実際の移動は次の physicsProcess で行われる。
    /// tileSize は MapQuery effect 経由で取得する（PlayerScene は MapScene の
    /// 存在・パスを知らない。実体は Game.start で注入される handler が答える）。
    pub def requestMove(d: Vec2.Vec2i, scene: Scene[NodeTag]):
            Scene[NodeTag] \ MapQuery =
        let s = MapQuery.tileSize();
        let motion = Vec2.mul(Vec2.fromI(d), s);
        scene |> mapPlayer((body, data) -> (body, {pendingMotion = motion | data}))

    /// pendingMotion を消費して CharacterBody2D を移動・衝突応答させる。
    /// Camera は子ノードなので親子変換で自動追従される（手動同期不要）。
    /// Game.flix の Node[NodeTag] redef からディスパッチされる。
    pub def physicsProcess(_delta: Float64,
                            node: EngineNode[NodeTag],
                            _path: NodePath,
                            scene: Scene[NodeTag]):
                           (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.Body2DWithState(body, NodeTag.Player(data)) =>
                // Godot 同様、毎フレーム無条件に move_and_collide を呼ぶ。
                // motion がゼロベクトルでも moveAndCollide は安全（位置は変わらない）。
                // 壁などの衝突体に当たれば手前で止まり、collided=true が返るが今は使わない。
                let (movedBody, _collided) =
                    CharacterBody2D.moveAndCollide(data#pendingMotion, scene, body);
                // 同じ指示を次フレームでも繰り返し実行しないよう消化済みとしてリセット。
                // input によって次の指示が積まれるまで待機する。
                let cleared: Data = {pendingMotion = Vec2.zero() | data};
                (EngineNode.Body2DWithState(movedBody, NodeTag.Player(cleared)), scene)
            case _ => (node, scene)
        }

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
}
