/// CameraFollow — ターゲットを滑らかに追いかける 2D カメラの追従機構（最小状態＋純関数）。
/// 保持する状態は追従点 `smoothPos`（Vec2）ただ 1 つで、狙う点や追従設定は呼び側が毎フレーム渡す。
/// ゲームは smoothPos だけを持ち、`step` で 1 フレーム進め、`settled` で「追いついたか」を判定する。
/// 描画用の投影は追従に依存しない `CameraProjection` が担う（このモジュールは追従の仕組みだけ）。
/// 利用例: プレイヤーを画面中央付近に保つ / 端の余白（デッドゾーン）に入るまで視点を止める。
///
/// すべて純関数（状態も設定も引数）なので engine 単独でテストでき、巻き戻しにも安全。
mod CameraFollow {

    use CameraProjection.Viewport

    /// 追従カメラの設定（定数仕様。インスタンス状態ではない）。
    ///   - `zoom`        拡大率（`< 1` で引き・`> 1` で寄り）
    ///   - `smoothSpeed` スムージング速度（大きいほど速く追いつく）
    ///   - `deadZone`    画面端の余白割合（0.0〜1.0）。target がこの矩形内なら視点を止める。
    pub type alias Config = { zoom = Vec2.Vec2, smoothSpeed = Float64, deadZone = Float64 }

    /// 毎フレーム 1 回、`smoothPos` を `target` へ 1 ステップ寄せた新しい smoothPos を返す。
    /// `centered = true`（移動モード）ならデッドゾーンを切って中心へ直接寄り、
    /// それ以外はデッドゾーン → スムージング lerp の順で進める（limit clamp は呼び側が ∞ 前提で省略）。
    ///
    ///   1. デッドゾーン: target が `smoothPos` 周りの余白矩形を超えたら中心を引っ張る。内側なら据え置き。
    ///   2. スムージング: smoothPos が上の logical へ単純 lerp で近づく（speed*dt > 1 は夾着クランプ）。
    pub def step(smoothPos: Vec2.Vec2, target: Vec2.Vec2, centered: Bool,
                 config: Config, dt: Duration.Duration, viewport: Viewport): Vec2.Vec2 =
        let dragOn = not centered;
        let zx = if (config#zoom#x == 0.0) 1.0 else config#zoom#x;
        let zy = if (config#zoom#y == 0.0) 1.0 else config#zoom#y;
        let worldHalfW = viewport#width / 2.0 / zx;
        let worldHalfH = viewport#height / 2.0 / zy;
        let logicalX =
            if (dragOn) {
                let rightBound = smoothPos#x + worldHalfW * config#deadZone;
                let leftBound  = smoothPos#x - worldHalfW * config#deadZone;
                if (target#x > rightBound) target#x - worldHalfW * config#deadZone
                else if (target#x < leftBound) target#x + worldHalfW * config#deadZone
                else smoothPos#x
            }
            else target#x;
        let logicalY =
            if (dragOn) {
                let bottomBound = smoothPos#y + worldHalfH * config#deadZone;
                let topBound    = smoothPos#y - worldHalfH * config#deadZone;
                if (target#y > bottomBound) target#y - worldHalfH * config#deadZone
                else if (target#y < topBound) target#y + worldHalfH * config#deadZone
                else smoothPos#y
            }
            else target#y;
        let t = Float64.min(1.0, config#smoothSpeed * Duration.toSeconds(dt));
        { x = smoothPos#x + (logicalX - smoothPos#x) * t,
          y = smoothPos#y + (logicalY - smoothPos#y) * t }

    /// ターゲットがデッドゾーン矩形内に収まったか（「カメラが追いついた」判定）。
    /// デッドゾーンが有効な軸（`centered = false`）は余白幅 + 2px、
    /// 無効な軸（`centered = true`）は 4px を閾値にする。
    pub def settled(smoothPos: Vec2.Vec2, target: Vec2.Vec2, centered: Bool,
                    config: Config, viewport: Viewport): Bool =
        let dragOn = not centered;
        let zx = if (config#zoom#x == 0.0) 1.0 else config#zoom#x;
        let zy = if (config#zoom#y == 0.0) 1.0 else config#zoom#y;
        let worldHalfW = viewport#width / 2.0 / zx;
        let worldHalfH = viewport#height / 2.0 / zy;
        let thresholdX = if (dragOn) worldHalfW * config#deadZone + 2.0 else 4.0;
        let thresholdY = if (dragOn) worldHalfH * config#deadZone + 2.0 else 4.0;
        Float64.abs(target#x - smoothPos#x) <= thresholdX
            and Float64.abs(target#y - smoothPos#y) <= thresholdY
}
