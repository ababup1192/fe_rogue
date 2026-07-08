/// ビューポートの中心を特定のノードに追従させる 2D カメラ。
/// position にターゲットの座標を入れておけば、スムージングや制限枠・ドラッグ余白を通して
/// 画面が滑らかに付いていくので、追従ロジックを毎フレーム書かずに済む（offset で微調整）。
/// 利用例: プレイヤーを画面中央に保つ / マップ端でスクロールを止める。
///
///   Camera
///     ├─ visual: visible, zIndex, modulate
///     └─ transform: position, rotation, scale, skew

/// カメラのアンカーモード。
///
///   - DragCenter: カメラの中心がターゲットに追従する（デフォルト）
///   - FixedTopLeft: ビューポートの左上をターゲットに固定する
pub enum Camera2DAnchorMode with Eq, Order, ToString {
    case DragCenter
    case FixedTopLeft
}

/// カメラの更新タイミング（プロセスコールバック）モード。
///
///   - PhysicsProcess: physicsProcess で更新する
///   - IdleProcess: process（毎フレーム）で更新する（デフォルト）
pub enum Camera2DProcessCallback with Eq, Order, ToString {
    case PhysicsProcess
    case IdleProcess
}

pub enum Camera {
    case Camera({
        transform = Transform,
        visual = Visual,
        offset = Vec2.Vec2,
        zoom = Vec2.Vec2,
        enabled = Bool,
        anchorMode = Camera2DAnchorMode,
        processCallback = Camera2DProcessCallback,
        ignoreRotation = Bool,
        limitLeft = Int32,
        limitTop = Int32,
        limitRight = Int32,
        limitBottom = Int32,
        limitSmoothed = Bool,
        positionSmoothingEnabled = Bool,
        positionSmoothingSpeed = Float64,
        rotationSmoothingEnabled = Bool,
        rotationSmoothingSpeed = Float64,
        dragHorizontalEnabled = Bool,
        dragVerticalEnabled = Bool,
        dragLeftMargin = Float64,
        dragRightMargin = Float64,
        dragTopMargin = Float64,
        dragBottomMargin = Float64,
        // 内部状態: 前フレームまでに到達した「実際に view が中心としている位置」。
        // `position` はゲームロジックがセットしたターゲット。`process` が delta ごとに
        // smoothPosition を position へ向けて補間する（drag margin を経て smoothing で滑らかに）。
        // smoothing/drag/limit のいずれも無効なら、getViewTransform は position をそのまま使う。
        smoothPosition = Vec2.Vec2
    })
}

mod Camera {

    // ========================================================================
    // コンストラクタ
    // ========================================================================

    /// デフォルト値で Camera を生成する
    ///
    /// デフォルト値:
    ///   offset = (0, 0), zoom = (1, 1), enabled = true,
    ///   anchorMode = DragCenter, limit = ±10_000_000
    pub def make(position: Vec2.Vec2): Camera =
        Camera.Camera({
            transform = { position = position, rotation = 0.0, scale = {x = 1.0, y = 1.0}, skew = 0.0 },
            visual = Visual.default(),
            offset = {x = 0.0, y = 0.0},
            zoom = {x = 1.0, y = 1.0},
            enabled = true,
            anchorMode = Camera2DAnchorMode.DragCenter,
            processCallback = Camera2DProcessCallback.IdleProcess,
            ignoreRotation = false,
            limitLeft = -10_000_000,
            limitTop = -10_000_000,
            limitRight = 10_000_000,
            limitBottom = 10_000_000,
            limitSmoothed = false,
            positionSmoothingEnabled = false,
            positionSmoothingSpeed = 5.0,
            rotationSmoothingEnabled = false,
            rotationSmoothingSpeed = 5.0,
            dragHorizontalEnabled = false,
            dragVerticalEnabled = false,
            dragLeftMargin = 0.2,
            dragRightMargin = 0.2,
            dragTopMargin = 0.2,
            dragBottomMargin = 0.2,
            // 初期は position と同値（`process` が走るまでは即座にカメラがそこを映す）
            smoothPosition = position
        })

    /// offset 付きで Camera を生成する
    pub def makeWithOffset(position: Vec2.Vec2, offset: Vec2.Vec2): Camera =
        make(position) |> setOffset(offset)

    /// 埋め込んだ Transform 部品を取り出す
    pub def transform(camera: Camera): Transform =
        let Camera.Camera(r) = camera;
        r#transform

    /// Transform 部品に関数を適用して差し替える
    pub def mapTransform(f: Transform -> Transform \ ef, camera: Camera): Camera \ ef =
        let Camera.Camera(r) = camera;
        Camera.Camera({transform = f(r#transform) | r})

    /// 埋め込んだ Visual 部品を取り出す
    pub def visual(camera: Camera): Visual =
        let Camera.Camera(r) = camera;
        r#visual

    /// Visual 部品に関数を適用して差し替える
    pub def mapVisual(f: Visual -> Visual \ ef, camera: Camera): Camera \ ef =
        let Camera.Camera(r) = camera;
        Camera.Camera({visual = f(r#visual) | r})

    // ========================================================================
    // Camera 固有プロパティ — getter / setter
    // ========================================================================

    /// ビューポートオフセットを取得する
    pub def getOffset(camera: Camera): Vec2.Vec2 =
        let Camera.Camera(r) = camera;
        r#offset

    /// ビューポートオフセットを設定する
    pub def setOffset(offset: Vec2.Vec2, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({offset = offset | r})

    /// ズーム倍率を取得する
    pub def getZoom(camera: Camera): Vec2.Vec2 =
        let Camera.Camera(r) = camera;
        r#zoom

    /// ズーム倍率を設定する
    pub def setZoom(zoom: Vec2.Vec2, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({zoom = zoom | r})

    /// カメラが有効（current）かどうかを返す
    pub def isEnabled(camera: Camera): Bool =
        let Camera.Camera(r) = camera;
        r#enabled

    /// カメラの有効状態（current かどうか）を設定する
    pub def setEnabled(enabled: Bool, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({enabled = enabled | r})

    /// アンカーモードを取得する
    pub def getAnchorMode(camera: Camera): Camera2DAnchorMode =
        let Camera.Camera(r) = camera;
        r#anchorMode

    /// アンカーモードを設定する
    pub def setAnchorMode(anchorMode: Camera2DAnchorMode, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({anchorMode = anchorMode | r})

    /// プロセスコールバックモードを取得する
    pub def getProcessCallback(camera: Camera): Camera2DProcessCallback =
        let Camera.Camera(r) = camera;
        r#processCallback

    /// プロセスコールバックモードを設定する
    pub def setProcessCallback(processCallback: Camera2DProcessCallback, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({processCallback = processCallback | r})

    /// 回転無視フラグを取得する
    pub def isIgnoreRotation(camera: Camera): Bool =
        let Camera.Camera(r) = camera;
        r#ignoreRotation

    /// 回転無視フラグを設定する
    pub def setIgnoreRotation(ignoreRotation: Bool, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({ignoreRotation = ignoreRotation | r})

    // ========================================================================
    // スクロール制限
    // ========================================================================

    /// スクロール制限（左端）を取得する
    pub def getLimitLeft(camera: Camera): Int32 =
        let Camera.Camera(r) = camera;
        r#limitLeft

    /// スクロール制限（左端）を設定する
    pub def setLimitLeft(limitLeft: Int32, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({limitLeft = limitLeft | r})

    /// スクロール制限（上端）を取得する
    pub def getLimitTop(camera: Camera): Int32 =
        let Camera.Camera(r) = camera;
        r#limitTop

    /// スクロール制限（上端）を設定する
    pub def setLimitTop(limitTop: Int32, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({limitTop = limitTop | r})

    /// スクロール制限（右端）を取得する
    pub def getLimitRight(camera: Camera): Int32 =
        let Camera.Camera(r) = camera;
        r#limitRight

    /// スクロール制限（右端）を設定する
    pub def setLimitRight(limitRight: Int32, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({limitRight = limitRight | r})

    /// スクロール制限（下端）を取得する
    pub def getLimitBottom(camera: Camera): Int32 =
        let Camera.Camera(r) = camera;
        r#limitBottom

    /// スクロール制限（下端）を設定する
    pub def setLimitBottom(limitBottom: Int32, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({limitBottom = limitBottom | r})

    /// 制限スムージングの有効状態を取得する
    pub def isLimitSmoothed(camera: Camera): Bool =
        let Camera.Camera(r) = camera;
        r#limitSmoothed

    /// 制限スムージングの有効状態を設定する
    pub def setLimitSmoothed(limitSmoothed: Bool, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({limitSmoothed = limitSmoothed | r})

    // ========================================================================
    // 位置スムージング
    // ========================================================================

    /// 位置スムージングの有効状態を取得する
    pub def isPositionSmoothingEnabled(camera: Camera): Bool =
        let Camera.Camera(r) = camera;
        r#positionSmoothingEnabled

    /// 位置スムージングの有効状態を設定する
    pub def setPositionSmoothingEnabled(positionSmoothingEnabled: Bool, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({positionSmoothingEnabled = positionSmoothingEnabled | r})

    /// 位置スムージングの速度を取得する
    pub def getPositionSmoothingSpeed(camera: Camera): Float64 =
        let Camera.Camera(r) = camera;
        r#positionSmoothingSpeed

    /// 位置スムージングの速度を設定する
    pub def setPositionSmoothingSpeed(positionSmoothingSpeed: Float64, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({positionSmoothingSpeed = positionSmoothingSpeed | r})

    // ========================================================================
    // 回転スムージング
    // ========================================================================

    /// 回転スムージングの有効状態を取得する
    pub def isRotationSmoothingEnabled(camera: Camera): Bool =
        let Camera.Camera(r) = camera;
        r#rotationSmoothingEnabled

    /// 回転スムージングの有効状態を設定する
    pub def setRotationSmoothingEnabled(rotationSmoothingEnabled: Bool, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({rotationSmoothingEnabled = rotationSmoothingEnabled | r})

    /// 回転スムージングの速度を取得する
    pub def getRotationSmoothingSpeed(camera: Camera): Float64 =
        let Camera.Camera(r) = camera;
        r#rotationSmoothingSpeed

    /// 回転スムージングの速度を設定する
    pub def setRotationSmoothingSpeed(rotationSmoothingSpeed: Float64, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({rotationSmoothingSpeed = rotationSmoothingSpeed | r})

    // ========================================================================
    // ドラッグマージン
    // ========================================================================

    /// 水平ドラッグマージンの有効状態を取得する
    pub def isDragHorizontalEnabled(camera: Camera): Bool =
        let Camera.Camera(r) = camera;
        r#dragHorizontalEnabled

    /// 水平ドラッグマージンの有効状態を設定する
    pub def setDragHorizontalEnabled(dragHorizontalEnabled: Bool, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({dragHorizontalEnabled = dragHorizontalEnabled | r})

    /// 垂直ドラッグマージンの有効状態を取得する
    pub def isDragVerticalEnabled(camera: Camera): Bool =
        let Camera.Camera(r) = camera;
        r#dragVerticalEnabled

    /// 垂直ドラッグマージンの有効状態を設定する
    pub def setDragVerticalEnabled(dragVerticalEnabled: Bool, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({dragVerticalEnabled = dragVerticalEnabled | r})

    /// 左ドラッグマージンを取得する
    pub def getDragLeftMargin(camera: Camera): Float64 =
        let Camera.Camera(r) = camera;
        r#dragLeftMargin

    /// 左ドラッグマージンを設定する（0.0〜1.0）
    pub def setDragLeftMargin(dragLeftMargin: Float64, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({dragLeftMargin = dragLeftMargin | r})

    /// 右ドラッグマージンを取得する
    pub def getDragRightMargin(camera: Camera): Float64 =
        let Camera.Camera(r) = camera;
        r#dragRightMargin

    /// 右ドラッグマージンを設定する（0.0〜1.0）
    pub def setDragRightMargin(dragRightMargin: Float64, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({dragRightMargin = dragRightMargin | r})

    /// 上ドラッグマージンを取得する
    pub def getDragTopMargin(camera: Camera): Float64 =
        let Camera.Camera(r) = camera;
        r#dragTopMargin

    /// 上ドラッグマージンを設定する（0.0〜1.0）
    pub def setDragTopMargin(dragTopMargin: Float64, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({dragTopMargin = dragTopMargin | r})

    /// 下ドラッグマージンを取得する
    pub def getDragBottomMargin(camera: Camera): Float64 =
        let Camera.Camera(r) = camera;
        r#dragBottomMargin

    /// 下ドラッグマージンを設定する（0.0〜1.0）
    pub def setDragBottomMargin(dragBottomMargin: Float64, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({dragBottomMargin = dragBottomMargin | r})

    // ========================================================================
    // メソッド
    // ========================================================================

    /// `smoothPosition` を取得する（描画用の実視点位置。`process` で更新される）
    pub def getSmoothPosition(camera: Camera): Vec2.Vec2 =
        let Camera.Camera(r) = camera;
        r#smoothPosition

    /// target (`position`) が「smoothPosition 中心の drag dead zone 矩形」内に居るか。
    /// drag margin が有効な軸では「収束した = target が dead zone 内」、無効な軸では
    /// 4 px epsilon を threshold にする（後方互換）。
    /// 「カメラが target に追いついた」判定に使う（ゲーム側のための判定で、標準的な相当 API は無い）。
    /// 純関数（viewport を引数で取り、scene/effect に依存しない）なので engine 単独テスト可能。
    pub def isWithinDragDeadZone(camera: Camera,
            viewportSize: {viewportWidth = Float64, viewportHeight = Float64}): Bool =
        let Camera.Camera(r) = camera;
        let target = r#transform#position;
        let smooth = r#smoothPosition;
        let zx = if (r#zoom#x == 0.0) 1.0 else r#zoom#x;
        let zy = if (r#zoom#y == 0.0) 1.0 else r#zoom#y;
        let worldHalfW = viewportSize#viewportWidth / 2.0 / zx;
        let worldHalfH = viewportSize#viewportHeight / 2.0 / zy;
        // drag margin の収束 threshold + asymptotic 接近のための 2 px buffer
        let thresholdX = if (r#dragHorizontalEnabled)
                worldHalfW * Float64.max(r#dragLeftMargin, r#dragRightMargin) + 2.0
            else 4.0;
        let thresholdY = if (r#dragVerticalEnabled)
                worldHalfH * Float64.max(r#dragTopMargin, r#dragBottomMargin) + 2.0
            else 4.0;
        Float64.abs(target#x - smooth#x) <= thresholdX
            and Float64.abs(target#y - smooth#y) <= thresholdY

    /// `smoothPosition` を直接設定する（カメラを瞬間移動させたい場合の保険）。
    /// 通常は `process` 経由で smoothing/drag を介して更新される。
    pub def setSmoothPosition(smoothPosition: Vec2.Vec2, camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        Camera.Camera({smoothPosition = smoothPosition | r})

    /// smoothing / drag のいずれかが有効か。`getViewTransform` が
    /// `smoothPosition` を使うか `position` を使うかの分岐に用いる。
    /// すべて無効なら従来挙動（position 直読み）を保つ — 後方互換のための判定。
    pub def isFollowingActive(camera: Camera): Bool =
        let Camera.Camera(r) = camera;
        r#positionSmoothingEnabled
            or r#dragHorizontalEnabled
            or r#dragVerticalEnabled

    /// カメラの毎フレーム追従処理（毎フレーム 1 回呼ぶ更新関数）。
    /// `position` を「ターゲット」、`smoothPosition` を「実際に映している点」として、
    /// drag margin → smoothing lerp → limit clamp の順で `smoothPosition` を更新する。
    /// 純粋関数（カメラの新インスタンスを返す）。`viewportSize` はビューポート px サイズで、
    /// 内部で zoom を反映した world 単位の半幅・半高に変換する。
    ///
    /// 挙動:
    ///   - drag margin は world 単位で `viewport / 2 / zoom × dragXMargin` の矩形
    ///   - smoothing は単純 lerp (`speed * delta` を t、夾着クランプ)
    ///   - limit は hard clamp（`limitSmoothed = true` モードは未対応）
    pub def process(delta: Duration.Duration,
                    viewportSize: {viewportWidth = Float64, viewportHeight = Float64},
                    camera: Camera): Camera =
        let Camera.Camera(r) = camera;
        let target = r#transform#position;
        let smooth = r#smoothPosition;
        // zoom が 0 の軸は 1 として扱う（落とし穴防止、getViewTransform の流儀に合わせる）
        let zx = if (r#zoom#x == 0.0) 1.0 else r#zoom#x;
        let zy = if (r#zoom#y == 0.0) 1.0 else r#zoom#y;
        let worldHalfW = viewportSize#viewportWidth / 2.0 / zx;
        let worldHalfH = viewportSize#viewportHeight / 2.0 / zy;
        // 1. drag margin: target が `smooth` 周りの margin 矩形を超えたら logical を引っ張る。
        //    内部に居るなら logical = smooth で据え置き（カメラは止まる）。
        let logicalX =
            if (r#dragHorizontalEnabled) {
                let rightBound = smooth#x + worldHalfW * r#dragRightMargin;
                let leftBound  = smooth#x - worldHalfW * r#dragLeftMargin;
                if (target#x > rightBound) target#x - worldHalfW * r#dragRightMargin
                else if (target#x < leftBound) target#x + worldHalfW * r#dragLeftMargin
                else smooth#x
            }
            else target#x;
        let logicalY =
            if (r#dragVerticalEnabled) {
                let bottomBound = smooth#y + worldHalfH * r#dragBottomMargin;
                let topBound    = smooth#y - worldHalfH * r#dragTopMargin;
                if (target#y > bottomBound) target#y - worldHalfH * r#dragBottomMargin
                else if (target#y < topBound) target#y + worldHalfH * r#dragTopMargin
                else smooth#y
            }
            else target#y;
        // 2. smoothing: smoothPosition が logical へ単純 lerp で近づく。
        //    `speed * delta > 1` のとき夾着クランプして overshoot を防ぐ。
        let nextX =
            if (r#positionSmoothingEnabled) {
                let t = Float64.min(1.0,
                    r#positionSmoothingSpeed * Duration.toSeconds(delta));
                smooth#x + (logicalX - smooth#x) * t
            }
            else logicalX;
        let nextY =
            if (r#positionSmoothingEnabled) {
                let t = Float64.min(1.0,
                    r#positionSmoothingSpeed * Duration.toSeconds(delta));
                smooth#y + (logicalY - smooth#y) * t
            }
            else logicalY;
        // 3. limit hard clamp: smoothPosition がマップ外を映さないように矩形に押し込む
        let clampedX = nextX
            |> Float64.max(Int32.toFloat64(r#limitLeft))
            |> Float64.min(Int32.toFloat64(r#limitRight));
        let clampedY = nextY
            |> Float64.max(Int32.toFloat64(r#limitTop))
            |> Float64.min(Int32.toFloat64(r#limitBottom));
        Camera.Camera({smoothPosition = {x = clampedX, y = clampedY} | r})

    /// 画面中央のワールド座標を返す。
    ///
    /// position + offset がスクロール制限でクランプされた座標を返す。
    ///
    ///   ワールド空間:
    ///     +---------------------------+
    ///     |                           |
    ///     |     [camera.position]     |
    ///     |         + offset          |
    ///     |         = screen center   |
    ///     |                           |
    ///     +---------------------------+
    /// `globalPos` はシーンツリーから求めた Camera ノードのワールド座標。
    /// Camera が他ノードの子のときも親の変換を反映できるよう、呼び出し側が渡す。
    pub def getScreenCenterPosition(camera: Camera, globalPos: Vec2.Vec2): Vec2.Vec2 =
        let Camera.Camera(r) = camera;
        let rawX = globalPos#x + r#offset#x;
        let rawY = globalPos#y + r#offset#y;
        let clampedX = rawX
            |> Float64.max(Int32.toFloat64(r#limitLeft))
            |> Float64.min(Int32.toFloat64(r#limitRight));
        let clampedY = rawY
            |> Float64.max(Int32.toFloat64(r#limitTop))
            |> Float64.min(Int32.toFloat64(r#limitBottom));
        {x = clampedX, y = clampedY}

    /// カメラのターゲット位置を返す。
    ///
    /// スムージング適用前のターゲット座標（= position）を返す。
    pub def getTargetPosition(camera: Camera): Vec2.Vec2 =
        let Camera.Camera(r) = camera;
        r#transform#position

    /// このカメラを現在のカメラに設定する。
    pub def makeCurrent(camera: Camera): Camera =
        setEnabled(true, camera)

    /// カメラが現在のカメラかどうかを返す。
    pub def isCurrent(camera: Camera): Bool =
        isEnabled(camera)

    /// カメラのビュー変換（screenPos = worldPos * scale - offset）。
    ///
    /// zoom はビューポートに見えるサイズの倍率で、
    /// `zoom > 1` で寄り、`zoom < 1` で引きになる。CanvasLayer 配下のノードには
    /// 適用しない（HUD はカメラと無関係なため）
    pub type alias ViewTransform = { offset = Vec2.Vec2, scale = Vec2.Vec2 }

    /// 何も変換しない単位 ViewTransform（カメラ未配置時のフォールバック）
    pub def identityTransform(): ViewTransform =
        { offset = Vec2.zero(), scale = {x = 1.0, y = 1.0} }

    /// world 座標を screen 座標に変換する: `screen = world * scale - offset`
    pub def applyToWorldPos(transform: ViewTransform, worldPos: Vec2.Vec2): Vec2.Vec2 =
        {x = worldPos#x * transform#scale#x - transform#offset#x,
         y = worldPos#y * transform#scale#y - transform#offset#y}

    /// world 単位のサイズを screen 単位に変換する（zoom で寄った分だけ大きく見える）
    pub def applyToWorldSize(transform: ViewTransform, worldSize: Vec2.Vec2): Vec2.Vec2 =
        {x = worldSize#x * transform#scale#x,
         y = worldSize#y * transform#scale#y}

    /// screen 座標を world 座標に逆変換する（マウス入力 → world 変換に使う）。
    /// scale が 0 の軸は zoom 無し扱い（落とし穴防止）
    pub def screenToWorldPos(transform: ViewTransform, screenPos: Vec2.Vec2): Vec2.Vec2 =
        let sx = transform#scale#x;
        let sy = transform#scale#y;
        {x = if (sx == 0.0) screenPos#x + transform#offset#x
             else (screenPos#x + transform#offset#x) / sx,
         y = if (sy == 0.0) screenPos#y + transform#offset#y
             else (screenPos#y + transform#offset#y) / sy}

    /// screen 単位のサイズを world 単位に逆変換する。
    /// scale が 0 の軸は元のまま（落とし穴防止）
    pub def screenToWorldSize(transform: ViewTransform, screenSize: Vec2.Vec2): Vec2.Vec2 =
        let sx = transform#scale#x;
        let sy = transform#scale#y;
        {x = if (sx == 0.0) screenSize#x else screenSize#x / sx,
         y = if (sy == 0.0) screenSize#y else screenSize#y / sy}

    /// カメラから ViewTransform を計算する。
    ///
    /// シーンの描画時に各ノードの worldPos を `applyToWorldPos` に通すことで
    /// カメラの視点での screen 座標に変換できる。CanvasLayer 配下のノードには
    /// この transform を適用しない。
    ///
    /// アンカーモードによって計算が異なる:
    ///   - DragCenter: position+offset がビューポート中心。zoom はその中心まわりに作用
    ///   - FixedTopLeft: position+offset がビューポート左上。zoom は左上原点で作用
    /// `globalPos` はシーンツリーから求めた Camera ノードのワールド座標。
    /// Camera を他ノードの子にしたときも親の変換を反映できる。
    /// smoothing / drag のいずれかが有効なら、view 中心は `position` ではなく
    /// `smoothPosition`（process が更新する補間後の値）を起点に計算する。
    /// すべて無効なら従来通り `globalPos`（= 親変換込みの position）を起点にする — 後方互換。
    pub def getViewTransform(camera: Camera, globalPos: Vec2.Vec2,
                              viewportSize: {viewportWidth = Float64, viewportHeight = Float64}): ViewTransform =
        let Camera.Camera(r) = camera;
        let zoom = r#zoom;
        // 追従が有効なら smoothPosition を使う。Camera が scene root に居る前提で
        // smoothPosition はワールド座標扱い（CameraScene が常に root に置く）。
        let viewBase = if (isFollowingActive(camera)) r#smoothPosition else globalPos;
        match r#anchorMode {
            case Camera2DAnchorMode.DragCenter =>
                // screen = (world - screenCenter) * zoom + halfScreen
                //        = world * zoom - (screenCenter * zoom - halfScreen)
                let screenCenter = clampedScreenCenter(viewBase, r);
                let halfW = viewportSize#viewportWidth / 2.0;
                let halfH = viewportSize#viewportHeight / 2.0;
                { scale = zoom,
                  offset = {x = screenCenter#x * zoom#x - halfW,
                            y = screenCenter#y * zoom#y - halfH} }
            case Camera2DAnchorMode.FixedTopLeft =>
                // screen = (world - (viewBase + offset)) * zoom
                //        = world * zoom - (viewBase + offset) * zoom
                let rawX = viewBase#x + r#offset#x;
                let rawY = viewBase#y + r#offset#y;
                { scale = zoom,
                  offset = {x = rawX * zoom#x, y = rawY * zoom#y} }
        }

    /// 任意の base ワールド座標に offset を加え、limit 矩形でクランプして screen center を返す。
    /// `getScreenCenterPosition` の汎用化（base を引数化）。
    /// getViewTransform が smoothPosition / globalPos のいずれを起点にするかを切替可能にする。
    def clampedScreenCenter(base: Vec2.Vec2,
                             r: {transform = Transform, visual = Visual,
                                 offset = Vec2.Vec2, zoom = Vec2.Vec2, enabled = Bool,
                                 anchorMode = Camera2DAnchorMode,
                                 processCallback = Camera2DProcessCallback,
                                 ignoreRotation = Bool,
                                 limitLeft = Int32, limitTop = Int32,
                                 limitRight = Int32, limitBottom = Int32,
                                 limitSmoothed = Bool,
                                 positionSmoothingEnabled = Bool, positionSmoothingSpeed = Float64,
                                 rotationSmoothingEnabled = Bool, rotationSmoothingSpeed = Float64,
                                 dragHorizontalEnabled = Bool, dragVerticalEnabled = Bool,
                                 dragLeftMargin = Float64, dragRightMargin = Float64,
                                 dragTopMargin = Float64, dragBottomMargin = Float64,
                                 smoothPosition = Vec2.Vec2}): Vec2.Vec2 =
        let rawX = base#x + r#offset#x;
        let rawY = base#y + r#offset#y;
        let clampedX = rawX
            |> Float64.max(Int32.toFloat64(r#limitLeft))
            |> Float64.min(Int32.toFloat64(r#limitRight));
        let clampedY = rawY
            |> Float64.max(Int32.toFloat64(r#limitTop))
            |> Float64.min(Int32.toFloat64(r#limitBottom));
        {x = clampedX, y = clampedY}
}

