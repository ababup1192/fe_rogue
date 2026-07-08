/// CameraState — 追従カメラ自身の状態（現在ターゲット・スムーズ追従の補間位置・追従パラメータ）を保持する resource
///
/// カメラは scene ノードを持たず（`CursorState` と同流儀）、この resource が視点の単一権威。
/// 中身は engine の `Camera` 値そのもの＝変換計算（drag margin → smoothing lerp → limit clamp、
/// ViewTransform 生成、drag dead zone 判定）は engine の純粋関数を再利用する。`position` がゲームが
/// セットしたターゲット、`smoothPosition` が実際に映している点で、`advance` が毎フレーム後者を前者へ寄せる。
///
/// 追従パラメータ（zoom 0.32・positionSmoothing・drag margin 0.3・limit）の唯一の宣言点は
/// `initial`。`CameraScene.step` がフェーズ別ターゲットを計算して `advance` を呼び、
/// `RenderWorld.viewTransform` と `BattlePanelUi` が `viewTransform` を読み、敵ターン/階段退場ドライバが
/// `isSettled` を追従完了ゲートに使う。TurnPhase / CursorState と同じ Ref-based handler 注入パターンに揃える。
mod CameraState {

    /// viewport の px サイズ（`Camera` の各関数が world 単位半幅へ換算するのに要る）。
    pub type alias Viewport = {viewportWidth = Float64, viewportHeight = Float64}

    /// `withState` が提供する handler 1 つで処理する。状態は engine `Camera` 値まるごと。
    pub eff State {
        def get(): Camera
        def put(camera: Camera): Unit
    }

    /// 初期カメラ（原点）。追従パラメータの唯一の宣言点:
    /// zoom 0.32 / positionSmoothing 速度 5 / drag margin 0.3（水平垂直有効）/ limit ±999999。
    /// 位置と smoothPosition は原点。フロア構築時に `CameraScene.snapToParty` がパーティ先頭へ上書きする。
    pub def initial(): Camera =
        Camera.make(Vec2.zero())
            |> Camera.setZoom({x = 0.32, y = 0.32})
            |> Camera.setPositionSmoothingEnabled(true)
            |> Camera.setPositionSmoothingSpeed(5.0)
            |> Camera.setDragHorizontalEnabled(true)
            |> Camera.setDragVerticalEnabled(true)
            |> Camera.setDragLeftMargin(0.3)
            |> Camera.setDragRightMargin(0.3)
            |> Camera.setDragTopMargin(0.3)
            |> Camera.setDragBottomMargin(0.3)
            |> Camera.setLimitLeft(-999999)
            |> Camera.setLimitTop(-999999)
            |> Camera.setLimitRight(999999)
            |> Camera.setLimitBottom(999999)

    /// ターゲットと smoothPosition を `pos` へ即スナップする（追従の補間を飛ばす）。
    /// フロア構築時の初期化＝開始フレームのスナップ違和感を消す（position/smoothPosition の唯一の初期化点）。
    pub def snapTo(pos: Vec2.Vec2): Unit \ State =
        let c = State.get();
        State.put(c |> Node2D.setPosition(pos) |> Camera.setSmoothPosition(pos))

    /// 毎フレーム 1 回、ターゲットへ 1 ステップ追従する。
    /// `centered = true`（移動モード）なら drag margin を切って smoothing がターゲット中心へ直接寄り、
    /// それ以外は drag を有効に戻す（margin 値は `initial` の 0.3 を温存）。engine `Camera.process` が
    /// drag → smoothing lerp → limit clamp で `smoothPosition` を進める。
    pub def advance(target: Vec2.Vec2, centered: Bool,
                    delta: Duration.Duration, viewport: Viewport): Unit \ State =
        let dragOn = not centered;
        let c = State.get()
            |> Node2D.setPosition(target)
            |> Camera.setDragHorizontalEnabled(dragOn)
            |> Camera.setDragVerticalEnabled(dragOn)
            |> Camera.process(delta, viewport);
        State.put(c)

    /// 現在の視点の ViewTransform（world → screen 変換）。追従が有効なので `smoothPosition` 起点。
    /// `RenderWorld.viewTransform` と `BattlePanelUi` が読む描画変換の単一権威。
    pub def viewTransform(viewport: Viewport): Camera.ViewTransform \ State =
        let c = State.get();
        Camera.getViewTransform(c, Camera.getSmoothPosition(c), viewport)

    /// カメラがターゲットの drag dead zone 内に収まったか（敵ターン/階段退場の「追いつくまで待つ」ゲート）。
    pub def isSettled(viewport: Viewport): Bool \ State =
        Camera.isWithinDragDeadZone(State.get(), viewport)

    /// 内部 `cameraRef` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let cameraRef: Ref[Camera, r] = Ref.fresh(rc, initial());
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(cameraRef))
                def put(camera, k) = {
                    Ref.put(camera, cameraRef);
                    k()
                }
            }
        }
}
