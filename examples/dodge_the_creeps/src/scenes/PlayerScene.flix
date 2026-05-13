/// PlayerScene — Dodge the Creeps のプレイヤー (AnimatedSprite2D + Area2D)
///
/// ノード構成:
///   AnimatedSprite2D "player"  ─ NodeTag.Player(Data)
///     ├── Area2D "area"        ─ NodeTag.PlayerArea
///     └── CollisionShape2D ... ─ Area2D の中にラップされる
///
/// 入力は physicsProcess で WASD / 矢印キーから方向ベクトルを読み、
/// 等速移動してスクリーン端でクランプする。
mod PlayerScene {

    // ── 型 ──

    pub type alias Data = {
        velocity = Vec2.Vec2,
        hit      = Bool
    }

    // ── 定数 ──

    pub def name(): String = "player"
    pub def playerPath(): NodePath = name() :: Nil
    def areaName(): String = "area"
    pub def areaPath(): NodePath = name() :: areaName() :: Nil

    /// 移動速度（ピクセル/秒）。Godot 元プロジェクトのデフォルトに合わせる
    def speed(): Float64 = 400.0

    /// プレイヤーのコリジョン半径（CircleShape2D ベース）
    def collisionRadius(): Float64 = 30.0

    /// 初期スポーン位置（画面中央付近のやや下）
    pub def startPosition(): Vec2.Vec2 = {x = 240.0, y = 450.0}

    // ── 構築 ──

    /// SpriteFrames を構築する。
    /// "walk" : 横向き歩行 (2 フレームループ, 5fps)
    /// "up"   : 上下方向 (2 フレームループ, 5fps)
    def buildSpriteFrames(): SpriteFrames =
        let walk: SpriteFrames.Animation = {
            loop  = true,
            speed = 5.0,
            frames = ({texture = "playerGrey_walk1", duration = 1.0}: SpriteFrames.Frame) ::
                      ({texture = "playerGrey_walk2", duration = 1.0}: SpriteFrames.Frame) :: Nil
        };
        let up: SpriteFrames.Animation = {
            loop  = true,
            speed = 5.0,
            frames = ({texture = "playerGrey_up1", duration = 1.0}: SpriteFrames.Frame) ::
                      ({texture = "playerGrey_up2", duration = 1.0}: SpriteFrames.Frame) :: Nil
        };
        SpriteFrames.empty()
            |> SpriteFrames.addAnimation("walk", walk)
            |> SpriteFrames.addAnimation("up", up)

    pub def addPlayer(scene: Scene[NodeTag]): Scene[NodeTag] =
        // 初期は非表示。ゲーム開始時に PlayerScene.start が表示する。
        // Menu フェーズではこのまま隠れたままで、タイトル + ボタンだけ見せる
        let sprite = AnimatedSprite2D.make(
            buildSpriteFrames(),
            {animation = "walk"},
            startPosition(),
            {x = 1.0, y = 1.0}
        ) |> CanvasItem.setVisible(false);
        let circle = CollisionShape2D.CircleShape2D({radius = collisionRadius()});
        // Player は Mob レイヤだけを観測する。Mob 同士の重なりや Mob → Player 方向の
        // 観測はエンジンレベルで遮断される（Mob 側は mask=0）。
        let area = Area2D.make({x = 0.0, y = 0.0}, circle)
            |> Area2D.setMonitoring(true)
            |> Area2D.setMonitorable(true)
            |> Area2D.setCollisionLayer(CollisionLayers.player())
            |> Area2D.setCollisionMask(CollisionLayers.mob());
        let data: Data = {velocity = Vec2.zero(), hit = false};
        scene
            |> Scene.addNode(name(),
                EngineNode.AnimSprite2DWithState(sprite, NodeTag.Player(data)))
            |> Scene.addChild(name(), areaName(),
                EngineNode.Area2DWithState(area, NodeTag.PlayerArea))

    // ── ライフサイクル ──

    /// プレイヤーは addPlayer 時に visible=false で配置済みなので、ready は no-op。
    /// 表示は PlayerScene.start (Playing フェーズ移行時) が担当する
    pub def ready(node: EngineNode[NodeTag], _path: NodePath,
                  scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        (node, scene)

    /// physicsProcess: 入力を読み、Player スプライト位置を更新し、画面端でクランプする。
    /// hit 中は移動を停止する。
    pub def physicsProcess(delta: Duration.Duration,
                           node: EngineNode[NodeTag], _path: NodePath,
                           scene: Scene[NodeTag]):
            (EngineNode[NodeTag], Scene[NodeTag]) \ GameEngine.Game =
        match node {
            case EngineNode.AnimSprite2DWithState(sprite, NodeTag.Player(data)) =>
                if (data#hit) (node, scene)
                else {
                    let dt = Duration.toSeconds(delta);
                    let dir = readInputDirection();
                    let normalized = if (Vec2.length(dir) > 0.0) Vec2.normalized(dir) else dir;
                    let newVel = Vec2.mul(normalized, speed());
                    let curPos = Node2D.getPosition(sprite);
                    let nextPos = Vec2.add(curPos, Vec2.mul(newVel, dt));
                    let clamped = clampToScreen(nextPos);
                    let withAnim = applyAnimation(newVel, sprite);
                    let moved = Node2D.setPosition(clamped, withAnim);
                    let newData = { velocity = newVel | data };
                    (EngineNode.AnimSprite2DWithState(moved, NodeTag.Player(newData)), scene)
                }
            case _ => (node, scene)
        }

    /// WASD / 矢印キーから方向ベクトルを返す
    def readInputDirection(): Vec2.Vec2 \ GameEngine.Game =
        let xDir =
            (if (GameEngine.Game.isKeyPressed(GameEngine.Key.D))     1.0 else 0.0) +
            (if (GameEngine.Game.isKeyPressed(GameEngine.Key.Right)) 1.0 else 0.0) +
            (if (GameEngine.Game.isKeyPressed(GameEngine.Key.A))    -1.0 else 0.0) +
            (if (GameEngine.Game.isKeyPressed(GameEngine.Key.Left)) -1.0 else 0.0);
        let yDir =
            (if (GameEngine.Game.isKeyPressed(GameEngine.Key.S))     1.0 else 0.0) +
            (if (GameEngine.Game.isKeyPressed(GameEngine.Key.Down))  1.0 else 0.0) +
            (if (GameEngine.Game.isKeyPressed(GameEngine.Key.W))    -1.0 else 0.0) +
            (if (GameEngine.Game.isKeyPressed(GameEngine.Key.Up))   -1.0 else 0.0);
        {x = xDir, y = yDir}

    def clampToScreen(pos: Vec2.Vec2): Vec2.Vec2 =
        let r = collisionRadius();
        let w = Int32.toFloat64(Game.designWi()) - r;
        let h = Int32.toFloat64(Game.designHi()) - r;
        {x = Float64.max(r, Float64.min(pos#x, w)),
         y = Float64.max(r, Float64.min(pos#y, h))}

    /// 速度に応じて適切なアニメーションに切り替える。
    /// 横方向 (vx != 0) → "walk" + flipH。縦方向 → "up" + flipV (下向き時)。
    def applyAnimation(vel: Vec2.Vec2, sprite: AnimatedSprite2D): AnimatedSprite2D =
        if (vel#x == 0.0 and vel#y == 0.0)
            // 停止中はアニメも止める。次の入力で play で再開する
            AnimatedSprite2D.stop(sprite)
        else if (vel#x != 0.0)
            sprite
                |> AnimatedSprite2D.play("walk")
                |> AnimatedSprite2D.setFlipH(vel#x < 0.0)
                |> AnimatedSprite2D.setFlipV(false)
        else
            sprite
                |> AnimatedSprite2D.play("up")
                |> AnimatedSprite2D.setFlipV(vel#y > 0.0)
                |> AnimatedSprite2D.setFlipH(false)

    // ── ゲーム制御 ──

    /// 新規ゲーム開始時にプレイヤーをリセットする。
    /// 位置を初期位置に戻し、表示し、ヒットフラグをクリアし、Area2D の monitoring を有効化する。
    pub def start(scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> mapPlayerSprite((sprite, data) ->
                let reset = sprite
                    |> Node2D.setPosition(startPosition())
                    |> CanvasItem.setVisible(true)
                    |> AnimatedSprite2D.play("walk");
                (reset, {velocity = Vec2.zero(), hit = false | data}))
            |> Scene.mapEngineNode(areaPath(),
                EngineNode.mapArea2D(Area2D.setMonitoring(true)))

    /// プレイヤーが Mob にぶつかったときの処理:
    /// 1. スプライトを非表示にし、hit=true に設定
    /// 2. Area2D の monitoring を無効化して連続発火を防ぐ
    /// 3. 死亡 SE を再生
    /// 4. GamePhase を GameOver に遷移
    pub def onHitMob(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, GamePhaseState} =
        AudioStreamPlayer.play("death");
        GamePhaseState.put(GamePhase.GameOver);
        scene
            |> mapPlayerSprite((sprite, data) ->
                (CanvasItem.setVisible(false, sprite), {hit = true | data}))
            |> Scene.mapEngineNode(areaPath(),
                EngineNode.mapArea2D(Area2D.setMonitoring(false)))

    // ── ボイラ ──

    pub def mapPlayerSprite(f: (AnimatedSprite2D, Data) -> (AnimatedSprite2D, Data),
                            scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(playerPath(), engineNode -> match engineNode {
            case EngineNode.AnimSprite2DWithState(sprite, NodeTag.Player(data)) =>
                let (newSprite, newData) = f(sprite, data);
                EngineNode.AnimSprite2DWithState(newSprite, NodeTag.Player(newData))
            case other => other
        }, scene)

    pub def getPlayerData(scene: Scene[NodeTag]): Option[Data] =
        match Scene.getState(playerPath(), scene) {
            case Some(NodeTag.Player(data)) => Some(data)
            case _                                 => None
        }
}
