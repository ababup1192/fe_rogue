/// アニメーション付きスプライト（Godot AnimatedSprite2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_animatedsprite2d.html
///
/// 複数のフレーム（テクスチャ）を切り替えてアニメーションを表示する。
///
///   AnimatedSprite2D
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
///     +-- animations: アニメーション定義 (名前 → テクスチャ名リスト)
///     +-- currentAnimation: 再生中のアニメーション名
///     +-- currentFrame: 現在のフレームインデックス
///     +-- fps: 秒あたりのフレーム数
///     +-- playing: 再生中フラグ
pub enum AnimatedSprite2D {
    case AnimatedSprite2D({
        visible = Bool,                            // 表示フラグ
        zIndex = Int32,                            // 描画順
        modulate = Color,                          // 色変調
        position = Vec2.Vec2,                      // 位置
        rotation = Float64,                        // 回転（ラジアン）
        scale = Vec2.Vec2,                         // スケール
        skew = Float64,                            // スキュー
        animations = Map[String, List[String]],    // アニメーション定義
        currentAnimation = String,                 // 再生中アニメーション名
        currentFrame = Int32,                      // 現在フレーム
        fps = Float64,                             // フレームレート
        elapsed = Float64,                         // 経過時間アキュムレータ
        playing = Bool,                            // 再生中フラグ
        centered = Bool,                           // 中心を原点にするか
        offset = Vec2.Vec2,                        // 描画オフセット
        flipH = Bool,                              // 水平反転
        flipV = Bool                               // 垂直反転
    })
}

mod AnimatedSprite2D {

    /// AnimatedSprite2D を生成する
    pub def make(
        animations: Map[String, List[String]],
        initialAnimation: {initialAnimation = String},
        fps: {fps = Float64},
        position: Vec2.Vec2,
        scale: Vec2.Vec2
    ): AnimatedSprite2D =
        AnimatedSprite2D.AnimatedSprite2D({
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            position = position,
            rotation = 0.0,
            scale = scale,
            skew = 0.0,
            animations = animations,
            currentAnimation = initialAnimation#initialAnimation,
            currentFrame = 0,
            fps = fps#fps,
            elapsed = 0.0,
            playing = true,
            centered = true,
            offset = {x = 0.0, y = 0.0},
            flipH = false,
            flipV = false
        })

    /// 現在のフレームのテクスチャ名を返す
    pub def currentTexture(sprite: AnimatedSprite2D): String =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        match Map.get(r#currentAnimation, r#animations) {
            case Some(frames) =>
                match List.drop(r#currentFrame, frames) {
                    case tex :: _ => tex
                    case Nil => ""
                }
            case None => ""
        }

    /// 時間経過に応じてフレームを進める
    pub def advanceFrame(delta: Float64, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        if (not r#playing) sprite
        else {
            let newElapsed = r#elapsed + delta;
            let frameDuration = 1.0 / r#fps;
            if (newElapsed >= frameDuration) {
                let totalFrames = match Map.get(r#currentAnimation, r#animations) {
                    case Some(fs) => List.length(fs)
                    case None => 1
                };
                let nextFrame = if (totalFrames <= 1) 0
                                else Int32.remainder(r#currentFrame + 1, totalFrames);
                AnimatedSprite2D.AnimatedSprite2D({
                    currentFrame = nextFrame,
                    elapsed = newElapsed - frameDuration
                    | r
                })
            } else {
                AnimatedSprite2D.AnimatedSprite2D({elapsed = newElapsed | r})
            }
        }

    /// アニメーションを再生する（Godot 準拠）
    /// 同じアニメーションなら再開（フレーム維持）、違えばリセットして再生
    pub def play(animationName: String, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        if (r#currentAnimation == animationName)
            AnimatedSprite2D.AnimatedSprite2D({playing = true | r})
        else
            AnimatedSprite2D.AnimatedSprite2D({
                currentAnimation = animationName,
                currentFrame = 0,
                elapsed = 0.0,
                playing = true
                | r
            })

    /// 再生を停止する
    pub def stop(sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({playing = false | r})

    /// 現在のアニメーション名を取得する
    pub def getCurrentAnimation(sprite: AnimatedSprite2D): String =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        r#currentAnimation

    /// 水平反転を設定する
    pub def setFlipH(h: Bool, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({flipH = h | r})

    /// 垂直反転を設定する
    pub def setFlipV(v: Bool, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({flipV = v | r})

    /// フレームレートを設定する
    pub def setFps(fps: Float64, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({fps = fps | r})
}

// ── CanvasItem 実装 ──

instance CanvasItem[AnimatedSprite2D] {
    pub def isVisible(sprite: AnimatedSprite2D): Bool =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        r#visible
    pub def setVisible(visible: Bool, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({visible = visible | r})
    pub def getModulate(sprite: AnimatedSprite2D): Color =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        r#modulate
    pub def setModulate(color: Color, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({modulate = color | r})
    pub def getZIndex(sprite: AnimatedSprite2D): Int32 =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        r#zIndex
    pub def setZIndex(zIndex: Int32, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({zIndex = zIndex | r})
}

// ── Node2D 実装 ──

instance Node2D[AnimatedSprite2D] {
    pub def getPosition(sprite: AnimatedSprite2D): Vec2.Vec2 =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        r#position
    pub def setPosition(position: Vec2.Vec2, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({position = position | r})
    pub def getRotation(sprite: AnimatedSprite2D): Float64 =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        r#rotation
    pub def setRotation(rotation: Float64, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({rotation = rotation | r})
    pub def getScale(sprite: AnimatedSprite2D): Vec2.Vec2 =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        r#scale
    pub def setScale(scale: Vec2.Vec2, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({scale = scale | r})
    pub def getSkew(sprite: AnimatedSprite2D): Float64 =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        r#skew
    pub def setSkew(skew: Float64, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({skew = skew | r})
}
