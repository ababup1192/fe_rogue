/// MobScene — 画面端からランダムに湧くモブ (RigidBody2D + AnimatedSprite2D + Notifier)
///
/// ノード構成:
///   RigidBody2D "mob_<id>"             ─ NodeTag.Mob({mobId})
///     ├── AnimatedSprite2D "sprite"    ─ NodeTag.NoTag
///     └── VisibleOnScreenNotifier2D    ─ NodeTag.NoTag (画面外で削除)
///
/// スポーンは TimerHandler (MobTimer) から呼ばれる。
/// Path2D の screenEdgePath から位置と向きをサンプリングし、垂直方向の速度を与える。
mod MobScene {

    // ── 型 ──

    pub type alias Data = { mobId = Int32 }

    // ── 定数 ──

    pub def mobGroup(): String = "mobs"

    /// mobId から一意なノード名を生成する
    pub def mobName(mobId: Int32): String = "mob_${mobId}"

    def spriteName(): String = "sprite"
    def notifierName(): String = "notifier"

    /// モブの種類 (テクスチャ 2 枚 + 名前) 一覧。スポーン時に Math.Random で選ぶ
    def mobTypes(): List[(String, String, String)] =
        ("walk", "enemyWalking_1",  "enemyWalking_2") ::
        ("fly",  "enemyFlyingAlt_1", "enemyFlyingAlt_2") ::
        ("swim", "enemySwimming_1", "enemySwimming_2") :: Nil

    /// モブの基本速度（ピクセル/秒）。実値は randomRange で 150〜250 程度に変動させる
    def minSpeed(): Float64 = 150.0
    def maxSpeed(): Float64 = 250.0

    /// 衝突形状の半径（RigidBody2D の CircleShape2D）
    def collisionRadius(): Float64 = 30.0

    // ── 構築 ──

    /// mobId の SpriteFrames を生成する。1 個のアニメだけ持ち、loop=true
    def buildSpriteFrames(mobKind: (String, String, String)): SpriteFrames =
        let (animName, t1, t2) = mobKind;
        let anim: SpriteFrames.Animation = {
            loop  = true,
            speed = 5.0,
            frames = ({texture = t1, duration = 1.0}: SpriteFrames.Frame) ::
                      ({texture = t2, duration = 1.0}: SpriteFrames.Frame) :: Nil
        };
        SpriteFrames.empty()
            |> SpriteFrames.addAnimation(animName, anim)

    /// path 上の (position, direction) から、画面中央向きに飛ぶモブを生成する。
    /// direction は内向き法線 (= 画面中心方向) のラジアン。速度ベクトルはそこから計算する。
    pub def spawnMob(mobId: Int32, position: Vec2.Vec2, direction: Float64,
                     scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        // 速度の大きさをランダムに選ぶ
        let speedRange = maxSpeed() - minSpeed();
        let speedRand = Math.Random.randomFloat64();
        let mag = minSpeed() + speedRand * speedRange;
        // 進行方向にランダムオフセット (±π/4) を与えて単調を崩す
        let jitterRand = Math.Random.randomFloat64();
        let jitter = (jitterRand - 0.5) * (Vec2.pi() / 2.0);
        let dir = direction + jitter;
        let vel: Vec2.Vec2 = {x = Vec2.cos(dir) * mag, y = Vec2.sin(dir) * mag};

        // モブ種類をランダムに選ぶ
        let chosenKind = match RandomUtil.pick(mobTypes()) {
            case Some(k) => k
            case None    => ("walk", "enemyWalking_1", "enemyWalking_2")
        };
        let (animName, _, _) = chosenKind;

        let shape = CollisionShape2D.CircleShape2D({radius = collisionRadius()});
        // Mob は自分のレイヤに属するが mask=0 で誰も観測しない。
        // 結果として Mob ↔ Mob の重なり判定や Mob → Player の発火経路がエンジン側で
        // 自動的に skip され、Player 側 (mask=Mob) の onAreaEntered だけが呼ばれる。
        let body = RigidBody2D.make(position, shape)
            |> RigidBody2D.setLinearVelocity(vel)
            |> RigidBody2D.setGravityScale(0.0)
            |> RigidBody2D.setCollisionLayer(CollisionLayers.mob())
            |> RigidBody2D.setCollisionMask(0i32);
        let sprite = AnimatedSprite2D.make(
            buildSpriteFrames(chosenKind),
            {animation = animName},
            {x = 0.0, y = 0.0},
            {x = 1.0, y = 1.0}
        );
        let notifier = VisibleOnScreenNotifier2D.make({
            x = Int32.toFloat64(Game.designWi()),
            y = Int32.toFloat64(Game.designHi())
        });
        let name = mobName(mobId);
        let data: Data = { mobId = mobId };
        scene
            |> Scene.addNode(name,
                EngineNode.RigidBody2DWithState(body, NodeTag.Mob(data)))
            |> Scene.addToGroup(name :: Nil, mobGroup())
            |> Scene.addChild(name, spriteName(),
                EngineNode.AnimSprite2DWithState(sprite, NodeTag.NoTag))
            |> Scene.addChild(name, notifierName(),
                EngineNode.ScreenNotifier2DWithState(notifier, NodeTag.NoTag))

    /// MobTimer から呼ばれる: Path2D ノードから 1 点サンプリングしてモブをスポーン
    pub def spawnFromPath(mobId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ Math.Random =
        let t = Math.Random.randomFloat64();
        // 画面端パスは buildState で "mob_path" として登録してある
        let pathOpt = Scene.getEngineNode("mob_path" :: Nil, scene);
        match pathOpt {
            case Some(EngineNode.Path2DWithState(p, _)) =>
                let sample = Path2D.sample(t, p);
                spawnMob(mobId, sample#position, sample#direction, scene)
            case _ => scene
        }

    /// 画面外に出たモブを削除する。ScreenNotifyHandler から呼ばれる
    pub def onScreenExit(path: NodePath, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(path, scene)
}
