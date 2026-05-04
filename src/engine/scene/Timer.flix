/// Godot Timer 準拠のタイマーノード
/// see: https://docs.godotengine.org/ja/4.x/classes/class_timer.html
///
/// waitTime で設定した秒数のカウントダウンを行う不可視ノード。
/// oneShot=true でタイムアウト後に停止、false で自動リスタート。
///
///   Timer
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
pub enum Timer {
    case Timer({
        waitTime = Float64,
        timeLeft = Float64,
        running = Bool,
        oneShot = Bool,
        autostart = Bool,
        timedOut = Bool,
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color
    })
}

mod Timer {
    /// デフォルト値で Timer を生成する
    /// running=false, oneShot=true, autostart=false
    pub def make(waitTime: Float64): Timer =
        Timer.Timer({
            waitTime = waitTime,
            timeLeft = waitTime,
            running = false,
            oneShot = true,
            autostart = false,
            timedOut = false,
            position = Vec2.zero(),
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = false,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
        })

    /// タイマーを開始する（timeLeft を waitTime にリセット）
    pub def start(timer: Timer): Timer =
        let Timer.Timer(r) = timer;
        Timer.Timer({ running = true, timeLeft = r#waitTime | r })

    /// タイマーを停止する
    pub def stop(timer: Timer): Timer =
        let Timer.Timer(r) = timer;
        Timer.Timer({ running = false | r })

    /// タイマーをリスタートする（start と同義）
    pub def restart(timer: Timer): Timer =
        start(timer)

    /// 残り時間を取得する
    pub def getTimeLeft(timer: Timer): Float64 =
        let Timer.Timer(r) = timer;
        r#timeLeft

    /// タイマーが動作中かどうか
    pub def isRunning(timer: Timer): Bool =
        let Timer.Timer(r) = timer;
        r#running

    /// タイマーが停止中かどうか
    pub def isStopped(timer: Timer): Bool =
        not isRunning(timer)

    /// oneShot フラグを設定する
    pub def setOneShot(oneShot: Bool, timer: Timer): Timer =
        let Timer.Timer(r) = timer;
        Timer.Timer({ oneShot = oneShot | r })

    /// autostart フラグを設定する
    pub def setAutostart(autostart: Bool, timer: Timer): Timer =
        let Timer.Timer(r) = timer;
        Timer.Timer({ autostart = autostart | r })

    /// 毎フレームの更新処理
    /// running かつ timeLeft > 0 なら dt 分減算。0 以下で oneShot なら停止、でなければ waitTime にリセット
    /// タイマー満了時に timedOut フラグを立てる
    pub def process(dt: Float64, timer: Timer): Timer =
        let Timer.Timer(r) = timer;
        if (not r#running or r#timeLeft <= 0.0) timer
        else {
            let newTimeLeft = r#timeLeft - dt;
            if (newTimeLeft <= 0.0) {
                if (r#oneShot)
                    Timer.Timer({ timeLeft = 0.0, running = false, timedOut = true | r })
                else
                    Timer.Timer({ timeLeft = r#waitTime, timedOut = true | r })
            } else
                Timer.Timer({ timeLeft = newTimeLeft | r })
        }

    /// タイマーがタイムアウトしたかどうか
    pub def isTimedOut(timer: Timer): Bool =
        let Timer.Timer(r) = timer;
        r#timedOut

    /// timedOut フラグをクリアする
    pub def clearTimedOut(timer: Timer): Timer =
        let Timer.Timer(r) = timer;
        Timer.Timer({ timedOut = false | r })

    /// ready ライフサイクル: autostart なら running=true
    pub def ready(timer: Timer): Timer =
        let Timer.Timer(r) = timer;
        if (r#autostart) Timer.Timer({ running = true | r })
        else timer
}

// -- CanvasItem 実装 --

instance CanvasItem[Timer] {
    pub def isVisible(timer: Timer): Bool =
        let Timer.Timer(r) = timer;
        r#visible
    pub def setVisible(visible: Bool, timer: Timer): Timer =
        let Timer.Timer(r) = timer;
        Timer.Timer({ visible = visible | r })
    pub def getModulate(timer: Timer): Color =
        let Timer.Timer(r) = timer;
        r#modulate
    pub def setModulate(color: Color, timer: Timer): Timer =
        let Timer.Timer(r) = timer;
        Timer.Timer({ modulate = color | r })
    pub def getZIndex(timer: Timer): Int32 =
        let Timer.Timer(r) = timer;
        r#zIndex
    pub def setZIndex(zIndex: Int32, timer: Timer): Timer =
        let Timer.Timer(r) = timer;
        Timer.Timer({ zIndex = zIndex | r })
}

// -- Node2D 実装 --

instance Node2D[Timer] {
    pub def getPosition(timer: Timer): Vec2.Vec2 =
        let Timer.Timer(r) = timer;
        r#position
    pub def setPosition(position: Vec2.Vec2, timer: Timer): Timer =
        let Timer.Timer(r) = timer;
        Timer.Timer({ position = position | r })
    pub def getRotation(timer: Timer): Float64 =
        let Timer.Timer(r) = timer;
        r#rotation
    pub def setRotation(rotation: Float64, timer: Timer): Timer =
        let Timer.Timer(r) = timer;
        Timer.Timer({ rotation = rotation | r })
    pub def getScale(timer: Timer): Vec2.Vec2 =
        let Timer.Timer(r) = timer;
        r#scale
    pub def setScale(scale: Vec2.Vec2, timer: Timer): Timer =
        let Timer.Timer(r) = timer;
        Timer.Timer({ scale = scale | r })
    pub def getSkew(timer: Timer): Float64 =
        let Timer.Timer(r) = timer;
        r#skew
    pub def setSkew(skew: Float64, timer: Timer): Timer =
        let Timer.Timer(r) = timer;
        Timer.Timer({ skew = skew | r })
}
