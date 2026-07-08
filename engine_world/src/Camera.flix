/// Camera — 追従カメラの入口。追従(CameraFollow)と変換(CameraProjection)を 1 つにまとめた窓口。
/// これ 1 つ見れば「設定を選ぶ・1 歩追う・追いつき判定・画面座標に直す」が揃うので、
/// 部品(CameraFollow / CameraProjection)を探し歩かなくてよい。細かく組み替えたいときだけ下の部品を直に使う。
/// 例: nextPos = Camera.chase(world.cameraSmoothPos, player.pos, false, Camera.smooth(zoom), dt, vp)
mod Camera {

    // 型を Camera 側に再公開（ゲームは Camera.Config / Camera.Viewport / Camera.Projection で書ける）。
    // 中身は部品(CameraFollow / CameraProjection)の型そのもの＝隠さず「同じもの」を別名で見せるだけ。
    pub type alias Config = CameraFollow.Config
    pub type alias Viewport = CameraProjection.Viewport
    pub type alias Projection = CameraProjection.Projection

    // ── 設定プリセット（数値を覚えなくていい入口）──

    /// ゆるやかに追う設定（余白ありで、画面端に来たら動く）。汎用ゲームの既定。
    pub def smooth(zoom: Vec2.Vec2): Config =
        { zoom = zoom, smoothSpeed = 5.0, deadZone = 0.3 }

    /// きびきび追う設定（余白なしで、すぐ中心へ寄る）。アクション向け。
    pub def snappy(zoom: Vec2.Vec2): Config =
        { zoom = zoom, smoothSpeed = 12.0, deadZone = 0.0 }

    /// 常に中心に固定する設定（余白なし・やや速い）。ボス戦や一枚絵向け。
    pub def locked(zoom: Vec2.Vec2): Config =
        { zoom = zoom, smoothSpeed = 8.0, deadZone = 0.0 }

    // ── 毎フレームの操作 ──

    /// 狙う点へ 1 フレーム追う。次の視点を返す（`centered = true` で余白を切って中心へ直行）。
    pub def chase(pos: Vec2.Vec2, target: Vec2.Vec2, centered: Bool,
                  config: Config, dt: Duration.Duration, vp: Viewport): Vec2.Vec2 =
        CameraFollow.step(pos, target, centered, config, dt, vp)

    /// カメラが狙う点に追いついたか（次の演出へ進める合図などに使う）。
    pub def settled(pos: Vec2.Vec2, target: Vec2.Vec2, centered: Bool,
                    config: Config, vp: Viewport): Bool =
        CameraFollow.settled(pos, target, centered, config, vp)

    // ── 描画変換 ──

    /// 今の視点から描画用の投影を作る（world → screen 変換のもと）。
    pub def projectionOf(center: Vec2.Vec2, config: Config, vp: Viewport): Projection =
        CameraProjection.toProjection(center, config#zoom, vp)

    /// world 座標を画面座標へ写す（投影を使う。駒やタイルを置く位置を出す）。
    pub def toScreen(proj: Projection, world: Vec2.Vec2): Vec2.Vec2 =
        CameraProjection.worldToViewport(proj, world)
}
