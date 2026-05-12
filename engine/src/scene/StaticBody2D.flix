/// 静的物理ボディ（Godot StaticBody2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_staticbody2d.html
///
/// 物理エンジンに動かされない静止ボディ。壁・床・パイプなどの固定障害物に使う。
/// 他の Area2D や RigidBody2D から衝突検出される。
///
///   StaticBody2D
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
///     +-- CollisionObject2D: collisionShape, monitoring, monitorable, priority
///
pub enum StaticBody2D {
    case StaticBody2D({
        visible = Bool,                              // 表示フラグ
        zIndex = Int32,                              // 描画順
        modulate = Color,                            // 色変調
        position = Vec2.Vec2,                        // 位置
        rotation = Float64,                          // 回転（ラジアン）
        scale = Vec2.Vec2,                           // スケール
        skew = Float64,                              // スキュー
        collisionShape = Option[CollisionShape2D],   // 衝突形状
        monitoring = Bool,                           // 他エリアの侵入を検出するか
        monitorable = Bool,                          // 他エリアから検出されるか
        priority = Int32,                            // 衝突判定の処理優先度
        physicsCollisionEnabled = Bool               // RigidBody2D を物理的に押し戻すか（true=ground のような固体、false=Area2D 検出のみ）
    })
}

mod StaticBody2D {

    /// デフォルト値で StaticBody2D を生成する。
    /// monitoring=false, monitorable=true（他の Area2D から検出される）。
    /// physicsCollisionEnabled=true（RigidBody2D を物理的に押し戻す。Pipe など Area2D 検出のみで使う場合は false に設定）。
    pub def make(position: Vec2.Vec2, shape: CollisionShape2D): StaticBody2D =
        StaticBody2D.StaticBody2D({
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
            physicsCollisionEnabled = true
        })

    /// 物理衝突解決の有効フラグを取得する
    pub def isPhysicsCollisionEnabled(body: StaticBody2D): Bool =
        let StaticBody2D.StaticBody2D(r) = body;
        r#physicsCollisionEnabled

    /// 物理衝突解決の有効フラグを設定する。false にすると RigidBody2D を押し戻さない（Area2D 検出のみ）
    pub def setPhysicsCollisionEnabled(v: Bool, body: StaticBody2D): StaticBody2D =
        let StaticBody2D.StaticBody2D(r) = body;
        StaticBody2D.StaticBody2D({physicsCollisionEnabled = v | r})

    // ── CollisionObject2D setter ──

    /// 衝突形状を設定する
    pub def setCollisionShape(shape: Option[CollisionShape2D], body: StaticBody2D): StaticBody2D =
        let StaticBody2D.StaticBody2D(r) = body;
        StaticBody2D.StaticBody2D({collisionShape = shape | r})

    /// monitoring フラグを設定する
    pub def setMonitoring(v: Bool, body: StaticBody2D): StaticBody2D =
        let StaticBody2D.StaticBody2D(r) = body;
        StaticBody2D.StaticBody2D({monitoring = v | r})

    /// monitorable フラグを設定する
    pub def setMonitorable(v: Bool, body: StaticBody2D): StaticBody2D =
        let StaticBody2D.StaticBody2D(r) = body;
        StaticBody2D.StaticBody2D({monitorable = v | r})

    /// priority を設定する
    pub def setPriority(p: Int32, body: StaticBody2D): StaticBody2D =
        let StaticBody2D.StaticBody2D(r) = body;
        StaticBody2D.StaticBody2D({priority = p | r})
}

// ── CanvasItem 実装 ──

instance CanvasItem[StaticBody2D] {
    pub def isVisible(body: StaticBody2D): Bool =
        let StaticBody2D.StaticBody2D(r) = body;
        r#visible
    pub def setVisible(visible: Bool, body: StaticBody2D): StaticBody2D =
        let StaticBody2D.StaticBody2D(r) = body;
        StaticBody2D.StaticBody2D({visible = visible | r})
    pub def getModulate(body: StaticBody2D): Color =
        let StaticBody2D.StaticBody2D(r) = body;
        r#modulate
    pub def setModulate(color: Color, body: StaticBody2D): StaticBody2D =
        let StaticBody2D.StaticBody2D(r) = body;
        StaticBody2D.StaticBody2D({modulate = color | r})
    pub def getZIndex(body: StaticBody2D): Int32 =
        let StaticBody2D.StaticBody2D(r) = body;
        r#zIndex
    pub def setZIndex(zIndex: Int32, body: StaticBody2D): StaticBody2D =
        let StaticBody2D.StaticBody2D(r) = body;
        StaticBody2D.StaticBody2D({zIndex = zIndex | r})
}

// ── Node2D 実装 ──

instance Node2D[StaticBody2D] {
    pub def getPosition(body: StaticBody2D): Vec2.Vec2 =
        let StaticBody2D.StaticBody2D(r) = body;
        r#position
    pub def setPosition(position: Vec2.Vec2, body: StaticBody2D): StaticBody2D =
        let StaticBody2D.StaticBody2D(r) = body;
        StaticBody2D.StaticBody2D({position = position | r})
    pub def getRotation(body: StaticBody2D): Float64 =
        let StaticBody2D.StaticBody2D(r) = body;
        r#rotation
    pub def setRotation(rotation: Float64, body: StaticBody2D): StaticBody2D =
        let StaticBody2D.StaticBody2D(r) = body;
        StaticBody2D.StaticBody2D({rotation = rotation | r})
    pub def getScale(body: StaticBody2D): Vec2.Vec2 =
        let StaticBody2D.StaticBody2D(r) = body;
        r#scale
    pub def setScale(scale: Vec2.Vec2, body: StaticBody2D): StaticBody2D =
        let StaticBody2D.StaticBody2D(r) = body;
        StaticBody2D.StaticBody2D({scale = scale | r})
    pub def getSkew(body: StaticBody2D): Float64 =
        let StaticBody2D.StaticBody2D(r) = body;
        r#skew
    pub def setSkew(skew: Float64, body: StaticBody2D): StaticBody2D =
        let StaticBody2D.StaticBody2D(r) = body;
        StaticBody2D.StaticBody2D({skew = skew | r})
}

// ── CollisionObject2D 実装 ──

instance CollisionObject2D[StaticBody2D] {
    pub def getCollisionShape(body: StaticBody2D): Option[CollisionShape2D] =
        let StaticBody2D.StaticBody2D(r) = body;
        r#collisionShape
    pub def isMonitoring(body: StaticBody2D): Bool =
        let StaticBody2D.StaticBody2D(r) = body;
        r#monitoring
    pub def isMonitorable(body: StaticBody2D): Bool =
        let StaticBody2D.StaticBody2D(r) = body;
        r#monitorable
    redef getCollisionPriority(body: StaticBody2D): Int32 =
        let StaticBody2D.StaticBody2D(r) = body;
        r#priority
}

// ── Node 実装 ──

instance Node[StaticBody2D] {
    type Aef = {}
}
