/// 2D キャラクター物理ボディ（Godot CharacterBody2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_characterbody2d.html
///
/// 速度ベースの移動とスライド処理を提供するノード。
/// move_and_slide で velocity に基づく移動を行う。
///
///   CharacterBody2D
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
///     +-- CollisionObject2D: collisionShape, monitoring, monitorable
///     +-- velocity: 現在の速度ベクトル
///     +-- moveSpeed: 最大移動速度（ピクセル/秒）
///     +-- moveAndSlide: velocity に基づく移動（衝突スライド付き）
///
pub enum CharacterBody2D {
    case CharacterBody2D({
        visible = Bool,                              // 表示フラグ
        zIndex = Int32,                              // 描画順
        modulate = Color,                            // 色変調
        position = Vec2.Vec2,                        // 位置
        rotation = Float64,                          // 回転（ラジアン）
        scale = Vec2.Vec2,                           // スケール
        skew = Float64,                              // スキュー
        velocity = Vec2.Vec2,                        // 現在の速度ベクトル
        moveSpeed = Float64,                         // 最大移動速度
        collisionShape = Option[CollisionShape2D],   // 衝突形状
        monitoring = Bool,                           // 他エリアの侵入を検出するか
        monitorable = Bool,                          // 他エリアから検出されるか
        priority = Int32,                            // 衝突判定の処理優先度
        upDirection = Vec2.Vec2,                     // 床判定の上方向（デフォルト: (0, -1)）
        floorMaxAngle = Float64,                     // 床と判定する最大角度（ラジアン、デフォルト: π/4）
        maxSlides = Int32                            // moveAndSlide のスライド最大回数（デフォルト: 4）
    })
}

mod CharacterBody2D {

    /// デフォルト値で CharacterBody2D を生成する
    pub def make(position: Vec2.Vec2, moveSpeed: {moveSpeed = Float64}): CharacterBody2D =
        CharacterBody2D.CharacterBody2D({
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            position = position,
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            velocity = Vec2.zero(),
            moveSpeed = moveSpeed#moveSpeed,
            collisionShape = None,
            monitoring = false,
            monitorable = false,
            priority = 0,
            upDirection = Vec2.up(),
            floorMaxAngle = 0.7853981633974483,
            maxSlides = 4
        })

    /// 速度ベクトルを取得する
    pub def getVelocity(body: CharacterBody2D): Vec2.Vec2 =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#velocity

    /// 速度ベクトルを設定する
    pub def setVelocity(velocity: Vec2.Vec2, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({velocity = velocity | r})

    /// 最大移動速度を取得する
    pub def getMoveSpeed(body: CharacterBody2D): Float64 =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#moveSpeed

    /// 衝突形状を設定する
    pub def setCollisionShape(shape: Option[CollisionShape2D], body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({collisionShape = shape | r})

    /// monitoring フラグを設定する
    pub def setMonitoring(v: Bool, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({monitoring = v | r})

    /// monitorable フラグを設定する
    pub def setMonitorable(v: Bool, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({monitorable = v | r})

    /// priority を設定する
    pub def setPriority(p: Int32, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({priority = p | r})

    // ── move_and_slide 関連 ──

    /// 床判定の上方向を取得する（デフォルト: (0, -1) = 画面上）
    pub def getUpDirection(body: CharacterBody2D): Vec2.Vec2 =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#upDirection

    /// 床判定の上方向を設定する
    pub def setUpDirection(direction: Vec2.Vec2, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({upDirection = Vec2.normalized(direction) | r})

    /// 床と判定する最大角度（ラジアン）を取得する
    pub def getFloorMaxAngle(body: CharacterBody2D): Float64 =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#floorMaxAngle

    /// 床と判定する最大角度（ラジアン）を設定する
    pub def setFloorMaxAngle(angle: Float64, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({floorMaxAngle = angle | r})

    /// moveAndSlide のスライド最大回数を取得する
    pub def getMaxSlides(body: CharacterBody2D): Int32 =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#maxSlides

    /// moveAndSlide のスライド最大回数を設定する
    pub def setMaxSlides(count: Int32, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({maxSlides = count | r})

    /// velocity に基づいて位置を更新する（Godot move_and_slide 準拠）
    ///
    /// Godot では衝突検出 + 衝突面に沿ったスライド処理を行うが、
    /// 衝突応答は本エンジンのスコープ外のため、
    /// 現在は velocity * delta で位置を更新するのみ。
    /// 将来の衝突応答実装時にスライドロジックを追加する想定。
    ///
    /// Godot との違い:
    ///   - Godot では引数なし（内部で physics delta を使用）だが、
    ///     本エンジンでは純粋関数のため delta を明示的に受け取る
    ///   - 戻り値は更新後の CharacterBody2D（Godot は bool を返す）
    pub def moveAndSlide(delta: Float64, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        let motion = Vec2.mul(r#velocity, delta);
        CharacterBody2D.CharacterBody2D({position = Vec2.add(r#position, motion) | r})
}

// ── CanvasItem 実装 ──

instance CanvasItem[CharacterBody2D] {
    pub def isVisible(body: CharacterBody2D): Bool =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#visible
    pub def setVisible(visible: Bool, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({visible = visible | r})
    pub def getModulate(body: CharacterBody2D): Color =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#modulate
    pub def setModulate(color: Color, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({modulate = color | r})
    pub def getZIndex(body: CharacterBody2D): Int32 =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#zIndex
    pub def setZIndex(zIndex: Int32, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({zIndex = zIndex | r})
}

// ── Node2D 実装 ──

instance Node2D[CharacterBody2D] {
    pub def getPosition(body: CharacterBody2D): Vec2.Vec2 =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#position
    pub def setPosition(position: Vec2.Vec2, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({position = position | r})
    pub def getRotation(body: CharacterBody2D): Float64 =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#rotation
    pub def setRotation(rotation: Float64, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({rotation = rotation | r})
    pub def getScale(body: CharacterBody2D): Vec2.Vec2 =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#scale
    pub def setScale(scale: Vec2.Vec2, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({scale = scale | r})
    pub def getSkew(body: CharacterBody2D): Float64 =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#skew
    pub def setSkew(skew: Float64, body: CharacterBody2D): CharacterBody2D =
        let CharacterBody2D.CharacterBody2D(r) = body;
        CharacterBody2D.CharacterBody2D({skew = skew | r})
}

// ── CollisionObject2D 実装 ──

instance CollisionObject2D[CharacterBody2D] {
    pub def getCollisionShape(body: CharacterBody2D): Option[CollisionShape2D] =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#collisionShape
    pub def isMonitoring(body: CharacterBody2D): Bool =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#monitoring
    pub def isMonitorable(body: CharacterBody2D): Bool =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#monitorable
    redef getCollisionPriority(body: CharacterBody2D): Int32 =
        let CharacterBody2D.CharacterBody2D(r) = body;
        r#priority
}

// ── PhysicsBody2D 実装 ──

instance PhysicsBody2D[CharacterBody2D] {
    pub def getLinearVelocity(body: CharacterBody2D): Vec2.Vec2 =
        CharacterBody2D.getVelocity(body)
    pub def setLinearVelocity(velocity: Vec2.Vec2, body: CharacterBody2D): CharacterBody2D =
        CharacterBody2D.setVelocity(velocity, body)
}

// ── Node 実装 ──

instance Node[CharacterBody2D] {
    type Aef = {}
}
