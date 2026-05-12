/// 2D 剛体物理ボディ（Godot RigidBody2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_rigidbody2d.html
///
/// 物理エンジンによって動作する剛体。重力・速度積分・ダンピングを受ける。
/// PhysicsStep モジュールが毎フレームの物理更新を担当する。
///
///   RigidBody2D
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
///     +-- CollisionObject2D: collisionShape, monitoring, monitorable
///     +-- Physics: linearVelocity, angularVelocity, gravityScale, mass, bounce, linearDamp, angularDamp
///
pub enum RigidBody2D {
    case RigidBody2D({
        visible = Bool,                              // 表示フラグ
        zIndex = Int32,                              // 描画順
        modulate = Color,                            // 色変調
        position = Vec2.Vec2,                        // 位置
        rotation = Float64,                          // 回転（ラジアン）
        scale = Vec2.Vec2,                           // スケール
        skew = Float64,                              // スキュー
        collisionShape = Option[CollisionShape2D],   // 衝突形状
        monitoring = Bool,                           // ��エリアの侵入を検出するか
        monitorable = Bool,                          // 他エリアから検���されるか
        priority = Int32,                            // ��突判定の処理優先度
        linearVelocity = Vec2.Vec2,                  // 線形速度（ピ��セル/秒）
        angularVelocity = Float64,                   // 角速度（ラジアン/秒）
        gravityScale = Float64,                      // 重力倍率（0 で重力無効）
        mass = Float64,                              // 質量（kg）
        bounce = Float64,                            // 反発係数（0.0–1.0）
        linearDamp = Float64,                        // 線形ダンピング
        angularDamp = Float64,                       // 角ダンピング
        collisionExceptions = Set[NodePath]          // この path のボディとは物理衝突解決をしない（Godot add_collision_exception_with 相当）
    })
}

mod RigidBody2D {

    /// デフォルト値で RigidBody2D を生成する。
    /// monitoring=false, monitorable=true（他のエリアから検出される）。
    pub def make(position: Vec2.Vec2, shape: CollisionShape2D): RigidBody2D =
        RigidBody2D.RigidBody2D({
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            position = position,
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            collisionShape = Some(shape),
            monitoring = false,
            monitorable = true,
            priority = 0,
            linearVelocity = Vec2.zero(),
            angularVelocity = 0.0,
            gravityScale = 1.0,
            mass = 1.0,
            bounce = 0.0,
            linearDamp = 0.0,
            angularDamp = 0.0,
            collisionExceptions = Set.empty()
        })

    /// 衝突例外リストに other path を追加する（Godot add_collision_exception_with 相当）
    /// この body は other path の StaticBody2D との物理衝突解決 (resolveStaticCollisions) を skip する。
    /// Area2D の重なり検出には影響しない。
    pub def addCollisionException(otherPath: NodePath, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({collisionExceptions = Set.insert(otherPath, r#collisionExceptions) | r})

    /// other path が衝突例外リストに含まれるか
    pub def hasCollisionException(otherPath: NodePath, body: RigidBody2D): Bool =
        let RigidBody2D.RigidBody2D(r) = body;
        Set.memberOf(otherPath, r#collisionExceptions)

    // ── Physics getter/setter ──

    /// 線形速度を取得する
    pub def getLinearVelocity(body: RigidBody2D): Vec2.Vec2 =
        let RigidBody2D.RigidBody2D(r) = body;
        r#linearVelocity

    /// 線形速度を設定する
    pub def setLinearVelocity(velocity: Vec2.Vec2, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({linearVelocity = velocity | r})

    /// 角速度を取得する
    pub def getAngularVelocity(body: RigidBody2D): Float64 =
        let RigidBody2D.RigidBody2D(r) = body;
        r#angularVelocity

    /// 角速度を設定する
    pub def setAngularVelocity(velocity: Float64, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({angularVelocity = velocity | r})

    /// 重力倍率を取得する
    pub def getGravityScale(body: RigidBody2D): Float64 =
        let RigidBody2D.RigidBody2D(r) = body;
        r#gravityScale

    /// 重力倍率を設定する
    pub def setGravityScale(scale: Float64, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({gravityScale = scale | r})

    /// 質量を取得する
    pub def getMass(body: RigidBody2D): Float64 =
        let RigidBody2D.RigidBody2D(r) = body;
        r#mass

    /// ��量を設定��る
    pub def setMass(mass: Float64, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({mass = mass | r})

    /// 反発係数を取得する
    pub def getBounce(body: RigidBody2D): Float64 =
        let RigidBody2D.RigidBody2D(r) = body;
        r#bounce

    /// 反発係数を設定する
    pub def setBounce(bounce: Float64, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({bounce = bounce | r})

    /// 線形ダンピングを取得する
    pub def getLinearDamp(body: RigidBody2D): Float64 =
        let RigidBody2D.RigidBody2D(r) = body;
        r#linearDamp

    /// 線形ダンピングを設定する
    pub def setLinearDamp(damp: Float64, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({linearDamp = damp | r})

    /// 角ダンピングを取得する
    pub def getAngularDamp(body: RigidBody2D): Float64 =
        let RigidBody2D.RigidBody2D(r) = body;
        r#angularDamp

    /// 角ダンピングを設定する
    pub def setAngularDamp(damp: Float64, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({angularDamp = damp | r})

    // ── CollisionObject2D setter ──

    /// 衝突形状を設定する
    pub def setCollisionShape(shape: Option[CollisionShape2D], body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({collisionShape = shape | r})

    /// monitoring フラグを設定する
    pub def setMonitoring(v: Bool, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({monitoring = v | r})

    /// monitorable フラグを設定する
    pub def setMonitorable(v: Bool, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({monitorable = v | r})

    /// priority を設定する
    pub def setPriority(p: Int32, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({priority = p | r})
}

// ── CanvasItem 実装 ──

instance CanvasItem[RigidBody2D] {
    pub def isVisible(body: RigidBody2D): Bool =
        let RigidBody2D.RigidBody2D(r) = body;
        r#visible
    pub def setVisible(visible: Bool, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({visible = visible | r})
    pub def getModulate(body: RigidBody2D): Color =
        let RigidBody2D.RigidBody2D(r) = body;
        r#modulate
    pub def setModulate(color: Color, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({modulate = color | r})
    pub def getZIndex(body: RigidBody2D): Int32 =
        let RigidBody2D.RigidBody2D(r) = body;
        r#zIndex
    pub def setZIndex(zIndex: Int32, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({zIndex = zIndex | r})
}

// ── Node2D 実装 ──

instance Node2D[RigidBody2D] {
    pub def getPosition(body: RigidBody2D): Vec2.Vec2 =
        let RigidBody2D.RigidBody2D(r) = body;
        r#position
    pub def setPosition(position: Vec2.Vec2, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({position = position | r})
    pub def getRotation(body: RigidBody2D): Float64 =
        let RigidBody2D.RigidBody2D(r) = body;
        r#rotation
    pub def setRotation(rotation: Float64, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({rotation = rotation | r})
    pub def getScale(body: RigidBody2D): Vec2.Vec2 =
        let RigidBody2D.RigidBody2D(r) = body;
        r#scale
    pub def setScale(scale: Vec2.Vec2, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({scale = scale | r})
    pub def getSkew(body: RigidBody2D): Float64 =
        let RigidBody2D.RigidBody2D(r) = body;
        r#skew
    pub def setSkew(skew: Float64, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        RigidBody2D.RigidBody2D({skew = skew | r})
}

// ── CollisionObject2D 実装 ──

instance CollisionObject2D[RigidBody2D] {
    pub def getCollisionShape(body: RigidBody2D): Option[CollisionShape2D] =
        let RigidBody2D.RigidBody2D(r) = body;
        r#collisionShape
    pub def isMonitoring(body: RigidBody2D): Bool =
        let RigidBody2D.RigidBody2D(r) = body;
        r#monitoring
    pub def isMonitorable(body: RigidBody2D): Bool =
        let RigidBody2D.RigidBody2D(r) = body;
        r#monitorable
    redef getCollisionPriority(body: RigidBody2D): Int32 =
        let RigidBody2D.RigidBody2D(r) = body;
        r#priority
}

// ── PhysicsBody2D 実装 ��─

instance PhysicsBody2D[RigidBody2D] {
    pub def getLinearVelocity(body: RigidBody2D): Vec2.Vec2 =
        RigidBody2D.getLinearVelocity(body)
    pub def setLinearVelocity(velocity: Vec2.Vec2, body: RigidBody2D): RigidBody2D =
        RigidBody2D.setLinearVelocity(velocity, body)
}

// ── Node 実装 ──

instance Node[RigidBody2D] {
    type Aef = {}
}
