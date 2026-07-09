/// CameraState — 追従カメラの状態（映しているカメラ・追従ターゲット・ドラッグ有効フラグ）の型・数式・State 面
///
/// 視点の単一権威は `World.cameraRig`（prod は Game.start の inline facade が World を読み書きし、
/// test は本 mod の `withState` が local Ref で同じ State 面を提供する）。
/// engine の `Camera` は「どこを画面中央に、どのズームで映すか」だけを持つ純投影の値で、
/// スムージング・ドラッグ余白・スクロール制限といった追従の数式はこの mod が持つ
/// （Bevy の follow system が Camera の Transform を毎フレーム動かすのと同じ分担）。
///
/// `camera.transform.position` が実際に映している位置、`target` がゲームがセットした追従先。
/// `advance` が毎フレーム前者を後者へ寄せ、`viewTransform` が描画変換を、`isSettled` が
/// 追従完了ゲート（敵ターン/階段退場ドライバ用）を返す。
mod CameraState {

    /// viewport の px サイズ（追従の数式が world 単位半幅へ換算するのに要る）。
    pub type alias Viewport = {viewportWidth = Float64, viewportHeight = Float64}

    /// 追従カメラの状態。`camera` は投影用の engine 値（position = 実視点）、`target` は追従先、
    /// `dragEnabled` は移動モード（centered）で切れるドラッグ余白の有効フラグ。
    pub type alias RigState = { camera = Camera, target = Vec2.Vec2, dragEnabled = Bool }

    /// `withState` が提供する handler 1 つで処理する。
    pub eff State {
        def get(): RigState
        def put(state: RigState): Unit
    }

    // ── 追従パラメータ（唯一の宣言点）──

    /// ズーム倍率（0.32 = 3 倍ほど引く）。
    def zoom(): Vec2.Vec2 = {x = 0.32, y = 0.32}
    /// スムージングの速度（速いほど素早くターゲットへ寄る）。
    def smoothingSpeed(): Float64 = 5.0
    /// ドラッグ余白（viewport 半幅に対する割合）。この矩形の外にターゲットが出たら追従する。
    def dragMargin(): Float64 = 0.3
    /// スクロール制限（実質無制限）。
    def limitMin(): Int32 = -999999
    def limitMax(): Int32 = 999999

    /// 初期カメラ（原点・ズーム 0.32・ドラッグ有効）。position と target は原点で同値。
    /// フロア構築時に `CameraDriver.snapToParty` がパーティ先頭へ上書きする。
    pub def initial(): RigState =
        { camera = Camera.make(Vec2.zero()) |> Camera.setZoom(zoom()),
          target = Vec2.zero(),
          dragEnabled = true }

    /// ターゲットと実視点を `pos` へ即スナップする（追従の補間を飛ばす）。
    /// フロア構築時の初期化＝開始フレームのスナップ違和感を消す。両方を揃えて引き戻しを防ぐ。
    pub def snapTo(pos: Vec2.Vec2): Unit \ State =
        let s = State.get();
        State.put({ camera = s#camera |> Camera.mapTransform(Transform.setPosition(pos)),
                    target = pos | s })

    /// 毎フレーム 1 回、ターゲットへ 1 ステップ追従する。
    /// `centered = true`（移動モード）ならドラッグ余白を切ってスムージングがターゲット中心へ直接寄り、
    /// それ以外は余白を有効に戻す。`step` がドラッグ余白 → スムージング lerp → 制限クランプで
    /// カメラ位置を進める。
    pub def advance(target: Vec2.Vec2, centered: Bool,
                    delta: Duration.Duration, viewport: Viewport): Unit \ State =
        let dragEnabled = not centered;
        let s = State.get();
        let camera = step(s#camera, target, dragEnabled, delta, viewport);
        State.put({ camera = camera, target = target, dragEnabled = dragEnabled })

    /// 現在の視点の ViewTransform（world → screen 変換）。実視点 `camera.transform.position` 起点。
    /// `RenderWorld.viewTransform` と `BattlePanelUi` が読む描画変換の単一権威。
    pub def viewTransform(viewport: Viewport): Projection.ViewTransform \ State =
        let s = State.get();
        let center = Camera.transform(s#camera)#position;
        Camera.getViewTransform(s#camera, center, viewport)

    /// カメラがターゲットのドラッグ dead zone 内に収まったか（敵ターン/階段退場の「追いつくまで待つ」ゲート）。
    pub def isSettled(viewport: Viewport): Bool \ State =
        let s = State.get();
        reachedTarget(s#camera, s#target, s#dragEnabled, viewport)

    // ── 追従の数式（純粋・engine には持たせない）──

    /// カメラ位置をターゲットへ 1 ステップ寄せる。ドラッグ余白 → スムージング lerp → 制限クランプ。
    /// `viewport` は px サイズで、内部で zoom を反映した world 単位の半幅・半高に変換する。
    /// ドラッグ余白は world 単位で `viewport / 2 / zoom × dragMargin` の矩形、スムージングは
    /// 単純 lerp（`speed × delta` を t、夾着クランプ）、制限は hard clamp。
    pub def step(camera: Camera, target: Vec2.Vec2, dragEnabled: Bool,
             delta: Duration.Duration, viewport: Viewport): Camera =
        let smooth = Camera.transform(camera)#position;
        let z = Camera.getZoom(camera);
        // zoom が 0 の軸は 1 として扱う（0 除算防止）
        let zx = if (z#x == 0.0) 1.0 else z#x;
        let zy = if (z#y == 0.0) 1.0 else z#y;
        let worldHalfW = viewport#viewportWidth / 2.0 / zx;
        let worldHalfH = viewport#viewportHeight / 2.0 / zy;
        let margin = dragMargin();
        // 1. ドラッグ余白: ターゲットが `smooth` 周りの余白矩形を超えたら logical を引っ張る。
        //    内部に居るなら logical = smooth で据え置き（カメラは止まる）。
        let logicalX =
            if (dragEnabled) {
                let rightBound = smooth#x + worldHalfW * margin;
                let leftBound  = smooth#x - worldHalfW * margin;
                if (target#x > rightBound) target#x - worldHalfW * margin
                else if (target#x < leftBound) target#x + worldHalfW * margin
                else smooth#x
            }
            else target#x;
        let logicalY =
            if (dragEnabled) {
                let bottomBound = smooth#y + worldHalfH * margin;
                let topBound    = smooth#y - worldHalfH * margin;
                if (target#y > bottomBound) target#y - worldHalfH * margin
                else if (target#y < topBound) target#y + worldHalfH * margin
                else smooth#y
            }
            else target#y;
        // 2. スムージング: 現在位置が logical へ単純 lerp で近づく。`speed × delta > 1` で夾着クランプ。
        let t = Float64.min(1.0, smoothingSpeed() * Duration.toSeconds(delta));
        let nextX = smooth#x + (logicalX - smooth#x) * t;
        let nextY = smooth#y + (logicalY - smooth#y) * t;
        // 3. 制限 hard clamp: カメラがマップ外を映さないように矩形に押し込む
        let clampedX = nextX
            |> Float64.max(Int32.toFloat64(limitMin()))
            |> Float64.min(Int32.toFloat64(limitMax()));
        let clampedY = nextY
            |> Float64.max(Int32.toFloat64(limitMin()))
            |> Float64.min(Int32.toFloat64(limitMax()));
        camera |> Camera.mapTransform(Transform.setPosition({x = clampedX, y = clampedY}))

    /// ターゲットが「カメラ位置 中心のドラッグ dead zone 矩形」内に居るか。
    /// ドラッグ有効な軸では余白幅、無効な軸では 4 px epsilon を threshold にする。
    /// 「カメラが追いついた」判定に使う。
    pub def reachedTarget(camera: Camera, target: Vec2.Vec2, dragEnabled: Bool,
                      viewport: Viewport): Bool =
        let current = Camera.transform(camera)#position;
        let z = Camera.getZoom(camera);
        let zx = if (z#x == 0.0) 1.0 else z#x;
        let zy = if (z#y == 0.0) 1.0 else z#y;
        let worldHalfW = viewport#viewportWidth / 2.0 / zx;
        let worldHalfH = viewport#viewportHeight / 2.0 / zy;
        let margin = dragMargin();
        // 余白の収束 threshold + asymptotic 接近のための 2 px buffer
        let thresholdX = if (dragEnabled) worldHalfW * margin + 2.0 else 4.0;
        let thresholdY = if (dragEnabled) worldHalfH * margin + 2.0 else 4.0;
        Float64.abs(target#x - current#x) <= thresholdX
            and Float64.abs(target#y - current#y) <= thresholdY

    /// test harness 用 handler（prod は Game.start の facade が World.cameraRig を読み書きする）。
    /// 内部 `stateRef` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let stateRef: Ref[RigState, r] = Ref.fresh(rc, initial());
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(stateRef))
                def put(state, k) = {
                    Ref.put(state, stateRef);
                    k()
                }
            }
        }
}
