// BirdScene — Flappy Bird の鳥シーン構築・フラップ・回転制御
//
// 鳥は RigidBody2D（gravity_scale=1.0）で重力を受け、フラップで上昇する。
// 回転は物理エンジンの angularVelocity で制御し、physicsProcess の Flapping 分岐で
// -30° クランプと落下時 angVel = 1.5 を適用する（bird.gd FlappingState.update 準拠）。
// 衝突検知用の Area2D 子ノードを持つ。
//
//   RigidBody2DWithState(body, Bird(BirdData))
//     ├── AnimSprite2DWithState(sprite, NoTag)
//     └── Area2DWithState(area, BirdArea)

// ========================================================================
// 鳥の状態マシン
// ========================================================================

/// 鳥の状態遷移: Flying → Flapping → Hit → Grounded
/// Flying:   メニュー画面（重力なし）
/// Flapping: プレイ中（重力あり、フラップ操作可）
/// Hit:      パイプ衝突（移動停止、回転のみ）
/// Grounded: 地面着地（完全停止）
pub enum BirdState with Eq, ToString {
    case Flying
    case Flapping
    case Hit
    case Grounded
}

/// 鳥に届く入力イベント（bird.gd の `event` 引数相当）
/// キーボード押下とマウスボタン押下を統一的に扱う
pub enum BirdInputEvent with Eq, ToString {
    case KeyPressed(GameEngine.Key)
    case MouseButtonPressed(GameEngine.MouseButton)
}

/// 鳥の状態変化イベント（bird.gd の `state_changed` シグナル相当）
/// handleHit / handleGrounded 内で新状態と現在の Scene を emit し、ハンドラ側で
/// カメラシェイク等の副作用を行ってから新しい Scene を返す。
pub eff BirdStateChanged {
    def emit(newState: BirdState, scene: Scene[NodeTag]): Scene[NodeTag]
}

mod BirdScene {
    use NodeBuilder.{position, rotation, show, hide}

    // ========================================================================
    // 型定義
    // ========================================================================

    /// 鳥の状態データ（フレーム間で変化する純粋データ）
    /// state:   鳥の状態マシン
    /// speed:   横方向の移動速度（px/秒）
    /// hitPipe: Hit 状態に遷移する原因となったパイプの NodePath（onBirdHitPipe での同一パイプ判定に使う）
    pub type alias BirdData = {state = BirdState, speed = Float64, hitPipe = Option[NodePath]}

    // ========================================================================
    // 定数 — ノード名・パス
    // ========================================================================

    /// 鳥のルートノード名
    pub def name(): String = "bird"

    /// 鳥のルートノードパス
    pub def birdPath(): NodePath = name() :: Nil

    /// スプライト子ノード名
    def spriteName(): String = "sprite"

    /// スプライト子ノードパス
    pub def spritePath(): NodePath = name() :: spriteName() :: Nil

    /// 衝突検知用 Area2D 子ノード名
    def areaName(): String = "area"

    /// 衝突検知用 Area2D 子ノードパス
    pub def areaPath(): NodePath = name() :: areaName() :: Nil

    // ========================================================================
    // 定数 — 物理パラメータ（2x スケール）
    // ========================================================================
    // gravityScale / linearVelocity は Node 本来の物理プロパティのため
    // BirdScene.scene.json で管理する。BirdState / BirdData.speed はゲーム
    // ロジックのメタデータのため Flix 側で管理する。

    /// 横方向の移動速度（px/秒）。BirdData.speed の初期値として使う
    def birdSpeed(): Float64 = 100.0

    /// フラップ時の上方向初速度（px/秒）。参考実装の -150 を 2 倍した値
    def flapVelocityY(): Float64 = -300.0

    /// フラップ時の角速度（rad/秒）。反時計回り（上を向く）
    def flapAngularVelocity(): Float64 = -3.0

    /// 落下時の角速度下限（rad/秒）。時計回り（下を向く）
    def fallAngularVelocity(): Float64 = 1.5

    /// 上方向の回転上限（-30° = -π/6 rad）
    def minRotationDeg(): Float64 = -30.0

    /// -30° をラジアンに変換した値
    def minRotation(): Float64 = minRotationDeg() * Vec2.pi() / 180.0

    /// 画面上端の Y 座標（鳥がこれより上に行かないようにクランプする）
    /// 本家 Flappy Bird 準拠: 上端で鳥が張り付き、上向き速度はゼロにする
    def ceilingY(): Float64 = 0.0

    // ========================================================================
    // シーン定義 JSON のパス
    // ========================================================================

    /// 鳥のシーン定義 JSON ファイルのパス
    def sceneJsonPath(): String = "src/scenes/BirdScene.scene.json"

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// 鳥のノードをシーンに追加する（プレイ用）。
    /// 構造・gravityScale・linearVelocity は BirdScene.scene.json から読み込み、
    /// Bird(BirdData) タグ（ゲーム状態）は Flix 側で付与する
    pub def addBird(scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
        let birdData: BirdData = {state = BirdState.Flapping, speed = birdSpeed(), hitPipe = None};
        SceneLoader.loadScene(sceneJsonPath(), scene)
            |> Scene.setState(birdPath(), NodeTag.Bird(birdData))

    /// メニュー画面用の鳥をシーンに追加する。
    /// JSON で読み込んだ後、Flying 状態・重力ゼロ・速度ゼロで上書きする
    /// （毎フレーム update は no-op）
    pub def addBirdForMenu(scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
        let menuData: BirdData = {state = BirdState.Flying, speed = 0.0, hitPipe = None};
        addBird(scene)
            |> Scene.setState(birdPath(), NodeTag.Bird(menuData))
            |> Scene.mapEngineNode(birdPath(),
                EngineNode.mapRigidBody2D(body -> body
                    |> RigidBody2D.setGravityScale(0.0)
                    |> RigidBody2D.setLinearVelocity(Vec2.zero())))

 
    // ========================================================================
    // physicsProcess コールバック（bird.gd _physics_process 相当）
    // ========================================================================

    /// FlappingState.update(delta) — bird.gd: 回転 -30° クランプ + 落下時 angVel = 1.5
    /// + 本家準拠の Y クランプ（Godot 版にはない独自追加）
    def flappingUpdate(body: RigidBody2D): RigidBody2D =
        let rot = Node2D.getRotation(body);
        let vel = RigidBody2D.getLinearVelocity(body);
        let pos = Node2D.getPosition(body);
        // bird.gd FlappingState.update と同順:
        //   1. rot < -30°  → rot=-30°, angVel=0
        //   2. vel.y > 0   → angVel=1.5  (上書き)
        let (rot1, angVel1) =
            if (rot < minRotation()) (minRotation(), 0.0)
            else (rot, RigidBody2D.getAngularVelocity(body));
        let angVel2 = if (vel#y > 0.0) fallAngularVelocity() else angVel1;
        // Y クランプ: 上端を超えたら位置を上端に戻し、上向き速度をゼロにする
        let (newPos, newVel) =
            if (pos#y < ceilingY())
                ({x = pos#x, y = ceilingY()}, {x = vel#x, y = Float64.max(vel#y, 0.0)})
            else (pos, vel);
        body
            |> Node2D.setPosition(newPos)
            |> Node2D.setRotation(rot1)
            |> RigidBody2D.setLinearVelocity(newVel)
            |> RigidBody2D.setAngularVelocity(angVel2)

    /// bird.gd `flap()` 相当: y velocity を flapVelocityY、angular velocity を flapAngularVelocity に上書き
    /// x velocity は現在値を保持する（input / ready 両方ともこの挙動でよい）
    def flap(body: RigidBody2D): RigidBody2D =
        let vel = RigidBody2D.getLinearVelocity(body);
        body
            |> RigidBody2D.setLinearVelocity({x = vel#x, y = flapVelocityY()})
            |> RigidBody2D.setAngularVelocity(flapAngularVelocity())

    /// physicsProcess コールバック: bird.gd の `_physics_process(delta) → state.update(delta)` の Flix 移植
    /// 状態ごとに上記の per-state update 関数にディスパッチ
    /// Node[NodeTag] の Aef ({ Math.Random }) に合わせてエフェクトを宣言する
    pub def physicsProcess(_delta: Float64, node: EngineNode[NodeTag],
                           _path: NodePath, scene: Scene[NodeTag]
                          ): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.RigidBody2DWithState(body, NodeTag.Bird(birdData)) =>
                let newBody = match birdData#state {
                    case BirdState.Flapping => flappingUpdate(body)
                    case _ => body
                };
                (EngineNode.RigidBody2DWithState(newBody, NodeTag.Bird(birdData)), scene)
            case _ => (node, scene)
        }

    /// ready コールバック: bird.gd `FlappingState._init → flap()` 相当
    /// addBird で配置された Flapping 状態の鳥に初期 flap を適用する
    /// (addBirdForMenu の Flying 状態では何もしない)
    pub def ready(node: EngineNode[NodeTag], _path: NodePath,
                  scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.RigidBody2DWithState(body, NodeTag.Bird(birdData)) =>
                if (birdData#state == BirdState.Flapping) {
                    (EngineNode.RigidBody2DWithState(flap(body), NodeTag.Bird(birdData)), scene)
                } else {
                    (node, scene)
                }
            case _ => (node, scene)
        }

    /// input ディスパッチャ — bird.gd `_input(event) → state.input(event)` 相当
    /// Flapping 状態のみ flap 動作を実行し、他の状態は Godot に倣い no-op。
    /// メニュー / GameOver の遷移は Play ボタンクリック（MenuScene / GameOverScene）が担当する。
    pub def input(event: BirdInputEvent, scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Audio =
        let isFlapAction = match event {
            case BirdInputEvent.KeyPressed(GameEngine.Key.Space) => true
            case BirdInputEvent.MouseButtonPressed(GameEngine.MouseButton.Left) => true
            case _ => false
        };
        match getBirdData(scene)#state {
            case BirdState.Flapping =>
                if (isFlapAction) {
                    GameEngine.Audio.playAudio("sfx_wing");
                    scene |> mapBirdBody((body, birdData) -> (flap(body), birdData))
                } else scene
            case _ => scene
        }

    // ========================================================================
    // 状態遷移
    // ========================================================================

    /// 鳥を Hit 状態に遷移させる（bird.gd `HitState._init` 相当）
    /// 横移動停止、回転加速、衝突相手を collisionException に登録（sfx_hit + sfx_die）
    /// otherBodyPath: 衝突相手の StaticBody2D path。以降の物理衝突解決でこのペアは skip される。
    pub def handleHit(otherBodyPath: NodePath, scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, BirdStateChanged} =
        GameEngine.Audio.playAudio("sfx_hit");
        GameEngine.Audio.playAudio("sfx_die");
        let updatedScene = scene |> mapBirdBody((body, birdData) ->
            (body
                |> RigidBody2D.setLinearVelocity(Vec2.zero())
                |> RigidBody2D.setAngularVelocity(2.0)
                |> RigidBody2D.addCollisionException(otherBodyPath),
             {state = BirdState.Hit, hitPipe = Some(otherBodyPath) | birdData}));
        BirdStateChanged.emit(BirdState.Hit, updatedScene)

    /// 鳥を Grounded 状態に遷移させる（bird.gd `GroundedState._init` 相当）
    /// 停止（速度ゼロ、重力無効）。直前状態が Hit 以外なら sfx_hit を再生
    pub def handleGrounded(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, BirdStateChanged} =
        if (getBirdData(scene)#state != BirdState.Hit)
            GameEngine.Audio.playAudio("sfx_hit")
        else ();
        let updatedScene = scene |> mapBirdBody((body, birdData) ->
            (body
                |> RigidBody2D.setLinearVelocity(Vec2.zero())
                |> RigidBody2D.setAngularVelocity(0.0)
                |> RigidBody2D.setGravityScale(0.0),
             {state = BirdState.Grounded | birdData}));
        BirdStateChanged.emit(BirdState.Grounded, updatedScene)

    // ========================================================================
    // 衝突応答（AreaHandler から呼ばれる）
    // ========================================================================

    /// 鳥が地面に衝突したときの処理
    /// 鳥を Grounded 状態にする。地面への押し戻しは PhysicsStep.resolveStaticCollisions が自動処理。
    /// SE は handleGrounded 内で再生、camera shake は BirdStateChanged ハンドラ側で発火される
    pub def onBirdHitGround(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, BirdStateChanged} =
        let flappingOrHit = match getBirdData(scene)#state {
            case BirdState.Flapping => true
            case BirdState.Hit      => true
            case _                  => false
        };
        if (flappingOrHit) handleGrounded(scene)
        else scene

    /// 鳥がパイプに衝突したときの処理
    /// Flapping → Hit: 衝突パイプを collisionException に登録し、鳥は重力で落下する
    /// Hit → Grounded: hitPipe と異なるパイプに当たった = 別パイプの上に乗ってしまった
    ///                 状態とみなし、Grounded に遷移してゲームオーバーへ繋ぐ
    /// SE は handleHit / handleGrounded 内で再生、camera shake は BirdStateChanged ハンドラ側で発火される
    pub def onBirdHitPipe(pipePath: {pipePath = NodePath}, scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, BirdStateChanged} =
        let birdData = getBirdData(scene);
        match birdData#state {
            case BirdState.Flapping =>
                handleHit(pipePath#pipePath, scene)
            case BirdState.Hit =>
                if (Some(pipePath#pipePath) == birdData#hitPipe) scene
                else handleGrounded(scene)
            case _ => scene
        }

    // ========================================================================
    // ヘルパー: RigidBody2D と BirdData の変換・取得
    // ========================================================================

    /// 鳥の RigidBody2D と BirdData を変換する
    pub def mapBirdBody(f: (RigidBody2D, BirdData) -> (RigidBody2D, BirdData),
                        scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(birdPath(), engineNode -> match engineNode {
            case EngineNode.RigidBody2DWithState(body, NodeTag.Bird(birdData)) =>
                let (newBody, newData) = f(body, birdData);
                EngineNode.RigidBody2DWithState(newBody, NodeTag.Bird(newData))
            case other => other
        }, scene)

    /// Scene から BirdData を取り出す
    pub def getBirdData(scene: Scene[NodeTag]): BirdData =
        match Scene.getState(birdPath(), scene) {
            case Some(NodeTag.Bird(birdData)) => birdData
            case _ => bug!("bird not found")
        }
}
