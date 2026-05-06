/// アニメーション付きスプライト（Godot AnimatedSprite2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_animatedsprite2d.html
///
/// SpriteFrames リソースを参照して、アニメーション名 → フレーム列を切り替えながら表示する。
/// 各アニメーションは独自の loop / speed (FPS) を持ち、各フレームは duration 倍率で
/// 表示時間を個別に伸縮できる。speedScale は再生全体の速度倍率。
///
///   AnimatedSprite2D
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
///     +-- spriteFrames: 参照する SpriteFrames リソース
///     +-- animation: 現在再生中のアニメ名
///     +-- frame: 現在表示中のフレーム index
///     +-- frameProgress: 現フレーム内の進捗（0.0..1.0）
///     +-- speedScale: 再生速度の倍率
///     +-- autoplay: 起動時に自動再生するアニメ名（"" なら無効）
///     +-- playing: 再生中フラグ
pub enum AnimatedSprite2D {
    case AnimatedSprite2D({
        visible = Bool,
        zIndex = Int32,
        modulate = Color,
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        centered = Bool,
        offset = Vec2.Vec2,
        flipH = Bool,
        flipV = Bool,
        spriteFrames = SpriteFrames,
        animation = String,
        frame = Int32,
        frameProgress = Float64,
        speedScale = Float64,
        autoplay = String,
        playing = Bool
    })
}

mod AnimatedSprite2D {

    /// AnimatedSprite2D を生成する。
    /// `animation` で指定したアニメから即時再生開始する（autoplay は空にする）。
    pub def make(
        spriteFrames: SpriteFrames,
        animation: {animation = String},
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
            centered = true,
            offset = {x = 0.0, y = 0.0},
            flipH = false,
            flipV = false,
            spriteFrames = spriteFrames,
            animation = animation#animation,
            frame = 0,
            frameProgress = 0.0,
            speedScale = 1.0,
            autoplay = "",
            playing = true
        })

    /// autoplay 指定で AnimatedSprite2D を生成する。autoplay と animation が同名で開始する。
    pub def makeWithAutoplay(
        spriteFrames: SpriteFrames,
        autoplay: {autoplay = String},
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
            centered = true,
            offset = {x = 0.0, y = 0.0},
            flipH = false,
            flipV = false,
            spriteFrames = spriteFrames,
            animation = autoplay#autoplay,
            frame = 0,
            frameProgress = 0.0,
            speedScale = 1.0,
            autoplay = autoplay#autoplay,
            playing = true
        })

    /// 現在のフレームのテクスチャ名を返す（アニメや frame index が無効なら "" を返す）
    pub def currentTexture(sprite: AnimatedSprite2D): String =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        SpriteFrames.frameTexture(r#animation, r#frame, r#spriteFrames)
            |> Option.getWithDefault("")

    /// 時間経過に応じてフレームを進める。
    /// 進捗計算: progress += delta / (1 / (anim.speed * speedScale) * frame.duration)
    /// loop=false で最終フレームに到達したら playing=false にして停止する。
    pub def advanceFrame(delta: Duration.Duration, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        if (not r#playing) sprite
        else match SpriteFrames.getAnimation(r#animation, r#spriteFrames) {
            case None       => sprite
            case Some(anim) =>
                let frames = anim#frames;
                let totalFrames = List.length(frames);
                if (totalFrames == 0) sprite
                else if (anim#speed * r#speedScale <= 0.0) sprite
                else {
                    // frame index を有効範囲にクランプ（外部で setFrame されたとき等の安全ガード）
                    let clampedFrame =
                        if (r#frame < 0) 0
                        else if (r#frame >= totalFrames) totalFrames - 1
                        else r#frame;
                    let baseDuration = 1.0 / (anim#speed * r#speedScale);
                    let advanced = stepProgress(Duration.toSeconds(delta), clampedFrame, r#frameProgress,
                                                  frames, totalFrames, anim#loop, baseDuration);
                    AnimatedSprite2D.AnimatedSprite2D({
                        frame = advanced#frame,
                        frameProgress = advanced#progress,
                        playing = advanced#playing
                        | r
                    })
                }
        }

    /// 1 delta 分の進捗を消費して frame / progress / playing を返す内部関数。
    /// 高 fps × 短い frameDuration で 1 delta が複数フレームをまたぐケースに対応する。
    def stepProgress(remainingDelta: Float64, frame: Int32, progress: Float64,
                     frames: List[SpriteFrames.Frame], totalFrames: Int32, loops: Bool,
                     baseDuration: Float64):
                     {frame = Int32, progress = Float64, playing = Bool} =
        let currentFrame = match List.nth(frame, frames) {
            case Some(f) => f
            case None    => {texture = "", duration = 1.0}  // ガード（クランプ後なので通常起きない）
        };
        let frameDuration = baseDuration * currentFrame#duration;
        if (frameDuration <= 0.0)
            {frame = frame, progress = 0.0, playing = true}
        else {
            let progressIncrement = remainingDelta / frameDuration;
            let newProgress = progress + progressIncrement;
            if (newProgress < 1.0)
                {frame = frame, progress = newProgress, playing = true}
            else {
                // 1 フレーム消費して次へ
                let nextFrame = frame + 1;
                let consumedDelta = (1.0 - progress) * frameDuration;
                let leftoverDelta = remainingDelta - consumedDelta;
                if (nextFrame >= totalFrames) {
                    if (loops)
                        // 先頭に戻って残り delta を続ける
                        stepProgress(leftoverDelta, 0, 0.0, frames, totalFrames, loops, baseDuration)
                    else
                        // 最終フレームで停止
                        {frame = totalFrames - 1, progress = 0.0, playing = false}
                } else
                    stepProgress(leftoverDelta, nextFrame, 0.0, frames, totalFrames, loops, baseDuration)
            }
        }

    /// アニメーションを再生する（Godot 準拠）。
    /// 同じアニメ名なら現フレームから再開、違えば frame=0 にリセットして再生。
    pub def play(animationName: String, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        if (r#animation == animationName)
            AnimatedSprite2D.AnimatedSprite2D({playing = true | r})
        else
            AnimatedSprite2D.AnimatedSprite2D({
                animation = animationName,
                frame = 0,
                frameProgress = 0.0,
                playing = true
                | r
            })

    /// 再生を停止する
    pub def stop(sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({playing = false | r})

    /// 現在のアニメーション名を取得する（Godot の `animation` プロパティ）
    pub def getAnimation(sprite: AnimatedSprite2D): String =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        r#animation

    /// 水平反転を設定する
    pub def setFlipH(h: Bool, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({flipH = h | r})

    /// 垂直反転を設定する
    pub def setFlipV(v: Bool, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({flipV = v | r})

    /// 再生速度の倍率を設定する（1.0 = 通常、2.0 = 2 倍速、0.5 = 半速）
    pub def setSpeedScale(speedScale: Float64, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({speedScale = speedScale | r})

    /// autoplay 対象のアニメ名を設定する（"" で無効化）
    pub def setAutoplay(name: String, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({autoplay = name | r})

    /// 表示フレーム index を直接設定する（progress は 0 にリセット）
    pub def setFrame(frame: Int32, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({frame = frame, frameProgress = 0.0 | r})

    /// SpriteFrames リソースを差し替える
    pub def setSpriteFrames(spriteFrames: SpriteFrames, sprite: AnimatedSprite2D): AnimatedSprite2D =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        AnimatedSprite2D.AnimatedSprite2D({spriteFrames = spriteFrames | r})
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
