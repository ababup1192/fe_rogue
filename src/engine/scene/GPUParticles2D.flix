/// GPU パーティクルエミッター（Godot GPUParticles2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_gpuparticles2d.html
///
/// テクスチャの残像をフェードアウトしながら放出するノード。
/// engineProcess で自動的にパーティクルを放出・加齢・除去する。
///
///   GPUParticles2D
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew

mod GPUParticles2D {
    /// 個々のパーティクル
    pub type alias Particle = {
        position = Vec2.Vec2,   // 放出時のグローバル座標
        age = Float64           // 経過時間（秒）
    }

    /// GPUParticles2D の生成パラメータ
    pub type alias Config = {
        texture = String,
        amount = Int32,
        lifetime = Float64,
        speedScale = Float64,
        startAlpha = Float32,
        endAlpha = Float32,
        startScale = Float64,
        endScale = Float64
    }
}

pub enum GPUParticles2D {
    case GPUParticles2D({
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color,
        texture = String,
        particleLifetime = Float64,
        emitInterval = Float64,
        startAlpha = Float32,
        endAlpha = Float32,
        startScale = Float64,
        endScale = Float64,
        particles = List[GPUParticles2D.Particle],
        emitTimer = Float64
    })
}

mod GPUParticles2D {
    /// Config からパラメータを名前付きで渡して生成する
    pub def make(config: Config): GPUParticles2D =
        let effectiveLifetime = config#lifetime / config#speedScale;
        let interval = config#lifetime / (Int32.toFloat64(config#amount) * config#speedScale);
        GPUParticles2D.GPUParticles2D({
            position = Vec2.zero(),
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            texture = config#texture,
            particleLifetime = effectiveLifetime,
            emitInterval = interval,
            startAlpha = config#startAlpha,
            endAlpha = config#endAlpha,
            startScale = config#startScale,
            endScale = config#endScale,
            particles = Nil,
            emitTimer = 0.0
        })

    /// パーティクルの放出・加齢・除去を一括処理する
    pub def process(delta: Float64, emitPos: Vec2.Vec2, emitter: GPUParticles2D): GPUParticles2D =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        // パーティクルの加齢
        let aged = List.map(p -> {age = p#age + delta | p}, r#particles);
        // 期限切れ除去
        let alive = List.filter(p -> p#age < r#particleLifetime, aged);
        // 放出タイマー減算
        let newTimer = r#emitTimer - delta;
        if (newTimer <= 0.0) {
            // 新しいパーティクルを放出
            let newParticle: Particle = {position = emitPos, age = 0.0};
            GPUParticles2D.GPUParticles2D({
                particles = newParticle :: alive,
                emitTimer = r#emitInterval + newTimer
                | r})
        } else {
            GPUParticles2D.GPUParticles2D({
                particles = alive,
                emitTimer = newTimer
                | r})
        }

    /// 各パーティクルを alpha 付き Drawable に変換する
    pub def toDrawables(emitter: GPUParticles2D, _globalPos: Vec2.Vec2): List[GameEngine.Drawable] =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        List.map(p -> {
            let t = p#age / r#particleLifetime;
            let alpha = r#startAlpha + Float64.truncateToFloat32(Float32.toFloat64(r#endAlpha - r#startAlpha) * t);
            let sc = r#startScale + (r#endScale - r#startScale) * t;
            {
                texture = r#texture,
                position = p#position,
                scale = {x = sc, y = sc},
                rotation = 0.0,
                color = r#modulate,
                alpha = alpha,
                centered = true,
                uvOffset = {x = 0.0, y = 0.0},
                uvScale = {x = 1.0, y = 1.0},
                zIndex = r#zIndex
            }
        }, r#particles)
}

// -- CanvasItem 実装 --

instance CanvasItem[GPUParticles2D] {
    pub def isVisible(emitter: GPUParticles2D): Bool =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        r#visible
    pub def setVisible(visible: Bool, emitter: GPUParticles2D): GPUParticles2D =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        GPUParticles2D.GPUParticles2D({ visible = visible | r })
    pub def getModulate(emitter: GPUParticles2D): Color =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        r#modulate
    pub def setModulate(color: Color, emitter: GPUParticles2D): GPUParticles2D =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        GPUParticles2D.GPUParticles2D({ modulate = color | r })
    pub def getZIndex(emitter: GPUParticles2D): Int32 =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        r#zIndex
    pub def setZIndex(zIndex: Int32, emitter: GPUParticles2D): GPUParticles2D =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        GPUParticles2D.GPUParticles2D({ zIndex = zIndex | r })
}

// -- Node2D 実装 --

instance Node2D[GPUParticles2D] {
    pub def getPosition(emitter: GPUParticles2D): Vec2.Vec2 =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        r#position
    pub def setPosition(position: Vec2.Vec2, emitter: GPUParticles2D): GPUParticles2D =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        GPUParticles2D.GPUParticles2D({ position = position | r })
    pub def getRotation(emitter: GPUParticles2D): Float64 =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        r#rotation
    pub def setRotation(rotation: Float64, emitter: GPUParticles2D): GPUParticles2D =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        GPUParticles2D.GPUParticles2D({ rotation = rotation | r })
    pub def getScale(emitter: GPUParticles2D): Vec2.Vec2 =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        r#scale
    pub def setScale(scale: Vec2.Vec2, emitter: GPUParticles2D): GPUParticles2D =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        GPUParticles2D.GPUParticles2D({ scale = scale | r })
    pub def getSkew(emitter: GPUParticles2D): Float64 =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        r#skew
    pub def setSkew(skew: Float64, emitter: GPUParticles2D): GPUParticles2D =
        let GPUParticles2D.GPUParticles2D(r) = emitter;
        GPUParticles2D.GPUParticles2D({ skew = skew | r })
}
