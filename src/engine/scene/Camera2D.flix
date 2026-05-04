/// 2D カメラノード（Godot Camera2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_camera2d.html
///
/// ビューポートの中心を特定のノードに追従させるためのカメラ。
/// position にターゲットの座標を設定し、offset で微調整する。
///
///   Camera2D
///     ├─ CanvasItem: visible, zIndex, modulate
///     └─ Node2D: position, rotation, scale, skew

/// カメラのアンカーモード（Godot Camera2D.AnchorMode 準拠）
///
///   - DragCenter: カメラの中心がターゲットに追従する（デフォルト）
///   - FixedTopLeft: ビューポートの左上をターゲットに固定する
pub enum Camera2DAnchorMode with Eq, Order, ToString {
    case DragCenter
    case FixedTopLeft
}

/// カメラのプロセスコールバックモード（Godot Camera2D.Camera2DProcessCallback 準拠）
///
///   - PhysicsProcess: physicsProcess で更新する
///   - IdleProcess: process（毎フレーム）で更新する（デフォルト）
pub enum Camera2DProcessCallback with Eq, Order, ToString {
    case PhysicsProcess
    case IdleProcess
}

pub enum Camera2D {
    case Camera2D({
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color,
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
        dragBottomMargin = Float64
    })
}

mod Camera2D {

    // ========================================================================
    // コンストラクタ
    // ========================================================================

    /// デフォルト値で Camera2D を生成する
    ///
    /// Godot のデフォルト値に準拠:
    ///   offset = (0, 0), zoom = (1, 1), enabled = true,
    ///   anchorMode = DragCenter, limit = ±10_000_000
    pub def make(position: Vec2.Vec2): Camera2D =
        Camera2D.Camera2D({
            position = position,
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
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
            dragBottomMargin = 0.2
        })

    /// offset 付きで Camera2D を生成する
    pub def makeWithOffset(position: Vec2.Vec2, offset: Vec2.Vec2): Camera2D =
        make(position) |> setOffset(offset)

    // ========================================================================
    // Camera2D 固有プロパティ — getter / setter
    // ========================================================================

    /// ビューポートオフセットを取得する
    pub def getOffset(camera: Camera2D): Vec2.Vec2 =
        let Camera2D.Camera2D(r) = camera;
        r#offset

    /// ビューポートオフセットを設定する
    pub def setOffset(offset: Vec2.Vec2, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({offset = offset | r})

    /// ズーム倍率を取得する
    pub def getZoom(camera: Camera2D): Vec2.Vec2 =
        let Camera2D.Camera2D(r) = camera;
        r#zoom

    /// ズーム倍率を設定する
    pub def setZoom(zoom: Vec2.Vec2, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({zoom = zoom | r})

    /// カメラが有効（current）かどうかを返す
    pub def isEnabled(camera: Camera2D): Bool =
        let Camera2D.Camera2D(r) = camera;
        r#enabled

    /// カメラの有効状態を設定する（Godot の current プロパティ）
    pub def setEnabled(enabled: Bool, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({enabled = enabled | r})

    /// アンカーモードを取得する
    pub def getAnchorMode(camera: Camera2D): Camera2DAnchorMode =
        let Camera2D.Camera2D(r) = camera;
        r#anchorMode

    /// アンカーモードを設定する
    pub def setAnchorMode(anchorMode: Camera2DAnchorMode, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({anchorMode = anchorMode | r})

    /// プロセスコールバックモードを取得する
    pub def getProcessCallback(camera: Camera2D): Camera2DProcessCallback =
        let Camera2D.Camera2D(r) = camera;
        r#processCallback

    /// プロセスコールバックモードを設定する
    pub def setProcessCallback(processCallback: Camera2DProcessCallback, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({processCallback = processCallback | r})

    /// 回転無視フラグを取得する
    pub def isIgnoreRotation(camera: Camera2D): Bool =
        let Camera2D.Camera2D(r) = camera;
        r#ignoreRotation

    /// 回転無視フラグを設定する
    pub def setIgnoreRotation(ignoreRotation: Bool, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({ignoreRotation = ignoreRotation | r})

    // ========================================================================
    // スクロール制限
    // ========================================================================

    /// スクロール制限（左端）を取得する
    pub def getLimitLeft(camera: Camera2D): Int32 =
        let Camera2D.Camera2D(r) = camera;
        r#limitLeft

    /// スクロール制限（左端）を設定する
    pub def setLimitLeft(limitLeft: Int32, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({limitLeft = limitLeft | r})

    /// スクロール制限（上端）を取得する
    pub def getLimitTop(camera: Camera2D): Int32 =
        let Camera2D.Camera2D(r) = camera;
        r#limitTop

    /// スクロール制限（上端）を設定する
    pub def setLimitTop(limitTop: Int32, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({limitTop = limitTop | r})

    /// スクロール制限（右端）を取得する
    pub def getLimitRight(camera: Camera2D): Int32 =
        let Camera2D.Camera2D(r) = camera;
        r#limitRight

    /// スクロール制限（右端）を設定する
    pub def setLimitRight(limitRight: Int32, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({limitRight = limitRight | r})

    /// スクロール制限（下端）を取得する
    pub def getLimitBottom(camera: Camera2D): Int32 =
        let Camera2D.Camera2D(r) = camera;
        r#limitBottom

    /// スクロール制限（下端）を設定する
    pub def setLimitBottom(limitBottom: Int32, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({limitBottom = limitBottom | r})

    /// 制限スムージングの有効状態を取得する
    pub def isLimitSmoothed(camera: Camera2D): Bool =
        let Camera2D.Camera2D(r) = camera;
        r#limitSmoothed

    /// 制限スムージングの有効状態を設定する
    pub def setLimitSmoothed(limitSmoothed: Bool, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({limitSmoothed = limitSmoothed | r})

    // ========================================================================
    // 位置スムージング
    // ========================================================================

    /// 位置スムージングの有効状態を取得する
    pub def isPositionSmoothingEnabled(camera: Camera2D): Bool =
        let Camera2D.Camera2D(r) = camera;
        r#positionSmoothingEnabled

    /// 位置スムージングの有効状態を設定する
    pub def setPositionSmoothingEnabled(positionSmoothingEnabled: Bool, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({positionSmoothingEnabled = positionSmoothingEnabled | r})

    /// 位置スムージングの速度を取得する
    pub def getPositionSmoothingSpeed(camera: Camera2D): Float64 =
        let Camera2D.Camera2D(r) = camera;
        r#positionSmoothingSpeed

    /// 位置スムージングの速度を設定する
    pub def setPositionSmoothingSpeed(positionSmoothingSpeed: Float64, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({positionSmoothingSpeed = positionSmoothingSpeed | r})

    // ========================================================================
    // 回転スムージング
    // ========================================================================

    /// 回転スムージングの有効状態を取得する
    pub def isRotationSmoothingEnabled(camera: Camera2D): Bool =
        let Camera2D.Camera2D(r) = camera;
        r#rotationSmoothingEnabled

    /// 回転スムージングの有効状態を設定する
    pub def setRotationSmoothingEnabled(rotationSmoothingEnabled: Bool, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({rotationSmoothingEnabled = rotationSmoothingEnabled | r})

    /// 回転スムージングの速度を取得する
    pub def getRotationSmoothingSpeed(camera: Camera2D): Float64 =
        let Camera2D.Camera2D(r) = camera;
        r#rotationSmoothingSpeed

    /// 回転スムージングの速度を設定する
    pub def setRotationSmoothingSpeed(rotationSmoothingSpeed: Float64, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({rotationSmoothingSpeed = rotationSmoothingSpeed | r})

    // ========================================================================
    // ドラッグマージン
    // ========================================================================

    /// 水平ドラッグマージンの有効状態を取得する
    pub def isDragHorizontalEnabled(camera: Camera2D): Bool =
        let Camera2D.Camera2D(r) = camera;
        r#dragHorizontalEnabled

    /// 水平ドラッグマージンの有効状態を設定する
    pub def setDragHorizontalEnabled(dragHorizontalEnabled: Bool, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({dragHorizontalEnabled = dragHorizontalEnabled | r})

    /// 垂直ドラッグマージンの有効状態を取得する
    pub def isDragVerticalEnabled(camera: Camera2D): Bool =
        let Camera2D.Camera2D(r) = camera;
        r#dragVerticalEnabled

    /// 垂直ドラッグマージンの有効状態を設定する
    pub def setDragVerticalEnabled(dragVerticalEnabled: Bool, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({dragVerticalEnabled = dragVerticalEnabled | r})

    /// 左ドラッグマージンを取得する
    pub def getDragLeftMargin(camera: Camera2D): Float64 =
        let Camera2D.Camera2D(r) = camera;
        r#dragLeftMargin

    /// 左ドラッグマージンを設定する（0.0〜1.0）
    pub def setDragLeftMargin(dragLeftMargin: Float64, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({dragLeftMargin = dragLeftMargin | r})

    /// 右ドラッグマージンを取得する
    pub def getDragRightMargin(camera: Camera2D): Float64 =
        let Camera2D.Camera2D(r) = camera;
        r#dragRightMargin

    /// 右ドラッグマージンを設定する（0.0〜1.0）
    pub def setDragRightMargin(dragRightMargin: Float64, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({dragRightMargin = dragRightMargin | r})

    /// 上ドラッグマージンを取得する
    pub def getDragTopMargin(camera: Camera2D): Float64 =
        let Camera2D.Camera2D(r) = camera;
        r#dragTopMargin

    /// 上ドラッグマージンを設定する（0.0〜1.0）
    pub def setDragTopMargin(dragTopMargin: Float64, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({dragTopMargin = dragTopMargin | r})

    /// 下ドラッグマージンを取得する
    pub def getDragBottomMargin(camera: Camera2D): Float64 =
        let Camera2D.Camera2D(r) = camera;
        r#dragBottomMargin

    /// 下ドラッグマージンを設定する（0.0〜1.0）
    pub def setDragBottomMargin(dragBottomMargin: Float64, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({dragBottomMargin = dragBottomMargin | r})

    // ========================================================================
    // メソッド（Godot Camera2D 準拠）
    // ========================================================================

    /// 画面中央のワールド座標を返す（Godot get_screen_center_position 準拠）
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
    pub def getScreenCenterPosition(camera: Camera2D): Vec2.Vec2 =
        let Camera2D.Camera2D(r) = camera;
        let rawX = r#position#x + r#offset#x;
        let rawY = r#position#y + r#offset#y;
        let clampedX = rawX
            |> Float64.max(Int32.toFloat64(r#limitLeft))
            |> Float64.min(Int32.toFloat64(r#limitRight));
        let clampedY = rawY
            |> Float64.max(Int32.toFloat64(r#limitTop))
            |> Float64.min(Int32.toFloat64(r#limitBottom));
        {x = clampedX, y = clampedY}

    /// カメラのターゲット位置を返す（Godot get_target_position 準拠）
    ///
    /// スムージング適用前のターゲット座標（= position）を返す。
    pub def getTargetPosition(camera: Camera2D): Vec2.Vec2 =
        let Camera2D.Camera2D(r) = camera;
        r#position

    /// このカメラを現在のカメラに設定する（Godot make_current 準拠）
    pub def makeCurrent(camera: Camera2D): Camera2D =
        setEnabled(true, camera)

    /// カメラが現在のカメラかどうかを返す（Godot is_current 準拠）
    pub def isCurrent(camera: Camera2D): Bool =
        isEnabled(camera)

    /// カメラ位置からビューポート変換オフセットを計算する
    ///
    /// シーンの描画時に各ノードの位置からこの値を引くことで、
    /// カメラの視点でのスクリーン座標に変換できる。
    /// CanvasLayer 配下のノードにはこのオフセットを適用しない。
    ///
    /// アンカーモードによって計算が異なる:
    ///   - DragCenter: position+offset がビューポート中心
    ///   - FixedTopLeft: position+offset がビューポート左上
    pub def getViewportOffset(camera: Camera2D, viewportSize: {viewportWidth = Float64, viewportHeight = Float64}): Vec2.Vec2 =
        let Camera2D.Camera2D(r) = camera;
        match r#anchorMode {
            case Camera2DAnchorMode.DragCenter =>
                let screenCenter = getScreenCenterPosition(camera);
                let halfW = viewportSize#viewportWidth / 2.0;
                let halfH = viewportSize#viewportHeight / 2.0;
                {x = screenCenter#x - halfW, y = screenCenter#y - halfH}
            case Camera2DAnchorMode.FixedTopLeft =>
                let rawX = r#position#x + r#offset#x;
                let rawY = r#position#y + r#offset#y;
                {x = rawX, y = rawY}
        }
}

// ── CanvasItem 実装 ──

instance CanvasItem[Camera2D] {
    pub def isVisible(camera: Camera2D): Bool =
        let Camera2D.Camera2D(r) = camera;
        r#visible
    pub def setVisible(visible: Bool, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({ visible = visible | r })
    pub def getModulate(camera: Camera2D): Color =
        let Camera2D.Camera2D(r) = camera;
        r#modulate
    pub def setModulate(color: Color, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({ modulate = color | r })
    pub def getZIndex(camera: Camera2D): Int32 =
        let Camera2D.Camera2D(r) = camera;
        r#zIndex
    pub def setZIndex(zIndex: Int32, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({ zIndex = zIndex | r })
}

// ── Node2D 実装 ──

instance Node2D[Camera2D] {
    pub def getPosition(camera: Camera2D): Vec2.Vec2 =
        let Camera2D.Camera2D(r) = camera;
        r#position
    pub def setPosition(position: Vec2.Vec2, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({ position = position | r })
    pub def getRotation(camera: Camera2D): Float64 =
        let Camera2D.Camera2D(r) = camera;
        r#rotation
    pub def setRotation(rotation: Float64, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({ rotation = rotation | r })
    pub def getScale(camera: Camera2D): Vec2.Vec2 =
        let Camera2D.Camera2D(r) = camera;
        r#scale
    pub def setScale(scale: Vec2.Vec2, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({ scale = scale | r })
    pub def getSkew(camera: Camera2D): Float64 =
        let Camera2D.Camera2D(r) = camera;
        r#skew
    pub def setSkew(skew: Float64, camera: Camera2D): Camera2D =
        let Camera2D.Camera2D(r) = camera;
        Camera2D.Camera2D({ skew = skew | r })
}
