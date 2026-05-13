// CameraScene — カメラ追従とカメラシェイクの構築・更新
//
// Camera2D は指定ノードの x 座標を追従し、衝突時に短時間ランダム揺れ（シェイク）を発生させる。
// 追従対象のノード名とシェイク残量を CameraData にまとめ、Camera2DWithState の状態として保持する。
//
//   Camera2DWithState(camera, Camera(CameraData))

mod CameraScene {

    // ========================================================================
    // 型定義
    // ========================================================================

    /// カメラシェイクの残り時間と強度
    /// shakeRemaining: 残り秒数（0 以下になるとシェイク終了）
    /// shakeIntensity: 揺れ幅（ピクセル）。毎フレーム 0.9 倍で減衰する
    /// offsets:        triggerShake 時に Math.Random で先取りした相対オフセット
    ///                 ([-0.5, 0.5] × 2 軸)。process は先頭から 1 フレーム 1 個消費する。
    ///                 高フレームレートで枯渇しても shakeIntensity の減衰で実害なし
    pub type alias ShakeData = {
        shakeRemaining = Float64,
        shakeIntensity = Float64,
        offsets = List[(Float64, Float64)]
    }

    /// カメラ状態
    /// target: 追従対象ノードの名前（addCamera 時に固定）
    /// shake:  シェイクの進行状態
    pub type alias CameraData = {target = String, shake = ShakeData}

    // ========================================================================
    // 定数
    // ========================================================================

    /// カメラノード名
    def cameraName(): String = "camera"

    /// カメラオフセット X（参考実装 -36 の 2 倍）
    pub def offsetX(): Float64 = -72.0

    /// カメラシェイクの強度（ピクセル）
    pub def shakeIntensity(): Float64 = 3.0

    /// カメラシェイクの持続時間（秒）
    pub def shakeDuration(): Float64 = 0.18

    /// シェイクの減衰率（毎フレーム適用）
    def shakeDecay(): Float64 = 0.9

    /// triggerShake 時に先取りするオフセットの個数
    /// shakeIntensity が 0.9^32 ≈ 3% まで減衰する数。実用上これ以上は見えない
    def shakeBufferSize(): Int32 = 32

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// カメラを追加する（FixedTopLeft、追従対象の初期位置に配置）
    /// target: 追従対象ノードの名前。以降 process はこの名前で位置を解決する
    pub def addCamera(target: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        let targetPos = Scene.globalPosition(target, scene);
        let camera = Camera2D.makeWithOffset(
                {x = targetPos#x, y = 0.0},
                {x = offsetX(), y = 0.0})
            |> Camera2D.setAnchorMode(Camera2DAnchorMode.FixedTopLeft);
        scene |> Scene.addNode(cameraName(),
            EngineNode.Camera2DWithState(camera,
                NodeTag.Camera({target = target,
                                shake = {shakeRemaining = 0.0,
                                         shakeIntensity = 0.0,
                                         offsets = Nil}})))

    // ========================================================================
    // シェイク発火
    // ========================================================================

    /// カメラシェイクをトリガーする（target は据え置きで shake のみ更新）
    /// intensity: 揺れ幅（ピクセル）/ duration: 持続秒数
    /// triggerShake 時にオフセットバッファを先取りすることで process は pure に保たれる
    pub def triggerShake(intensity: Float64, duration: Float64,
                         scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        match Scene.getState(cameraName() :: Nil, scene) {
            case Some(NodeTag.Camera(data)) =>
                let offsets = generateOffsets(shakeBufferSize());
                Scene.setState(cameraName() :: Nil,
                    NodeTag.Camera({shake = {shakeRemaining = duration,
                                             shakeIntensity = intensity,
                                             offsets = offsets} | data}),
                    scene)
            case _ => scene
        }

    /// n 個の (x, y) オフセットを [-0.5, 0.5] から無作為抽出する
    def generateOffsets(n: Int32): List[(Float64, Float64)] \ Math.Random =
        if (n <= 0) Nil
        else
            let x = Math.Random.randomFloat64() - 0.5;
            let y = Math.Random.randomFloat64() - 0.5;
            (x, y) :: generateOffsets(n - 1)

    // ========================================================================
    // ロジック（process）
    // ========================================================================

    /// 追従対象の位置に合わせて 1 フレーム分カメラを更新する
    /// シェイク中は基準オフセットに先取り済みオフセットを加え、残り時間と強度を減衰させる
    /// シェイク非アクティブ時は基準オフセットに戻す（次フレームの揺れ残りを防ぐ）
    pub def process(delta: Float64, node: EngineNode[NodeTag],
                    scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.Camera2DWithState(camera, NodeTag.Camera(data)) =>
                let targetPos = Scene.globalPosition(data#target, scene);
                let (offset, nextShake) = stepShake(data#shake, delta);
                let newCamera = camera
                    |> Node2D.setPosition({x = targetPos#x, y = 0.0})
                    |> Camera2D.setOffset(offset);
                (EngineNode.Camera2DWithState(newCamera,
                    NodeTag.Camera({shake = nextShake | data})), scene)
            case _ => (node, scene)
        }

    /// シェイクの 1 フレーム進行を計算する（pure）
    /// 残り時間 > 0 かつ オフセット残あり → 先取りオフセット消費 + 減衰
    /// 残り時間 > 0 だがバッファ枯渇 → 基準オフセット（実用上ほぼ起きない）
    /// それ以外 → 基準オフセット + 状態据え置き
    def stepShake(shakeData: ShakeData, delta: Float64):
            ({x = Float64, y = Float64}, ShakeData) =
        let baseOffset = {x = offsetX(), y = 0.0};
        if (shakeData#shakeRemaining > 0.0) {
            match shakeData#offsets {
                case (rx, ry) :: rest =>
                    let ox = rx * 2.0 * shakeData#shakeIntensity;
                    let oy = ry * 2.0 * shakeData#shakeIntensity;
                    ({x = baseOffset#x + ox, y = baseOffset#y + oy},
                     {shakeRemaining = shakeData#shakeRemaining - delta,
                      shakeIntensity = shakeData#shakeIntensity * shakeDecay(),
                      offsets = rest})
                case Nil => (baseOffset, shakeData)
            }
        } else (baseOffset, shakeData)
}
