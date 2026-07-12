// CharStage — キャラの演技台本（閉形式キネマティクス）と舞台情報（Stage / Mode）。
// 演技情報は試着室（bake/CharGallery のラボ）と本編ビュー（View → Roster）で共用する:
// ラボは stageAt の手書きタイムラインが Stage を作り、本編は World の物理から組む。
// 物理シミュレーションは使わず、区分ごとの手書きタイムラインを閉形式で刻む —
// 全キャラが寸分違わず同じ演技をするので、横並びの比較が成立する。
//
// 振り付け（6 秒 1 周・レーン内ローカル座標: 足元中心・地面 y = 0・x は ±70 に収まる）:
//   0.00-0.80 右へ走る          （vx 160・x は -46 から）
//   0.80-2.00 右へ B ダッシュ   （vx 160→280・段階演出の見せ場）
//   2.00-2.35 スキッド          （vx 280→0・深い前傾の窓）
//   2.35-3.30 左へ走る          （facing 反転）
//   3.30-3.60 左スキッド → 停止
//   3.60-4.50 ジャンプ          （頂点 48px @ 4.05・放物線・4.05 からは落下）
//   4.50-4.70 着地              （スカッシュの窓）
//   4.70-6.00 待機              （呼吸）
// 位置の実移動はレーン幅に収まるよう見かけの vx より圧縮してある（vx は演出強度用）。
// 左走りの実速度は「開始点 -60 へちょうど戻る」よう閉形式で導く — 周回境界でも瞬間移動しない。

mod CharStage {

    /// 1 周の演技（秒）。0..duration を閉形式で往復する。
    pub def duration(): Float64 = 6.0

    /// 演技の状態区分。各キャラはこれをポーズ選択の入口にする（解釈は自由）。
    pub enum Mode with Eq, ToString {
        case IdleMode
        case RunMode
        case DashMode
        case SkidMode
        case JumpMode
        case FallMode
        case LandMode
    }

    /// 演技の舞台情報: 各キャラの draw に渡す。体の構成はキャラが自由に決める。
    /// t = 通し秒（ループ内）/ pos = 足元中心の位置（レーン内ローカル）/
    /// vx = 見かけの速度（演出強度に使う）/ facing = +1 か -1 /
    /// mode = 状態区分 / modeT = いまの mode に入ってからの経過秒。
    pub type alias Stage = {
        t = Float64,
        pos = Vec2.Vec2,
        vx = Float64,
        facing = Float64,
        mode = Mode,
        modeT = Float64
    }

    // ── 区分の境界時刻（テストの連続性検査もこの列を使う）──

    pub def runEnd(): Float64 = 0.8
    pub def dashEnd(): Float64 = 2.0
    pub def skidEnd(): Float64 = 2.35
    pub def backEnd(): Float64 = 3.3
    pub def stopEnd(): Float64 = 3.6
    pub def apexT(): Float64 = 4.05
    pub def landAt(): Float64 = 4.5
    pub def landEnd(): Float64 = 4.7

    /// 区分の境界時刻ぜんぶ（周回境界 6.0 を含む）。連続性テストがこの列を舐める。
    pub def boundaries(): List[Float64] =
        runEnd() :: dashEnd() :: skidEnd() :: backEnd() :: stopEnd() ::
        apexT() :: landAt() :: landEnd() :: duration() :: Nil

    // ── 実移動の定数（レーン圧縮スケール。見かけの vx とは独立）──

    /// 演技の開始 x（待機もここで終わるので周回が繋がる）。体の半幅 ~11px を足しても
    /// レーン境界（±60）に触れない値に取る — 隣レーンへのはみ出しと端レーンの見切れを防ぐ。
    def startX(): Float64 = -46.0
    /// 右走りの実速度（px/s）。0.8 秒で -46 → -18。
    def runPace(): Float64 = 35.0
    /// ダッシュ終端の実速度。1.2 秒かけて 35 → 55 に線形加速（変位 54px で -18 → 36）。
    /// スキッドの滑り 9.625px を足した最右端は 45.625 — 体の半幅込みでもレーン内。
    def dashPace(): Float64 = 55.0

    def xRunEnd(): Float64 = startX() + runPace() * runEnd()
    def xDashEnd(): Float64 = xRunEnd() + (runPace() + dashPace()) / 2.0 * (dashEnd() - runEnd())
    /// スキッドは dashPace → 0 の等減速。変位 = 55 × 0.35 / 2 = 9.625px（最右端 45.625）。
    def xSkidEnd(): Float64 = xDashEnd() + dashPace() * (skidEnd() - dashEnd()) / 2.0
    /// 左走りの実速度: 最右端から開始点へ「等速 0.95s + 等減速 0.3s（実効 1.1s）」で
    /// ちょうど戻る値を閉形式で導く — 周回境界の連続性はこの式が保証する。
    def backPace(): Float64 =
        (xSkidEnd() - startX()) / ((backEnd() - skidEnd()) + (stopEnd() - backEnd()) / 2.0)
    def xBackEnd(): Float64 = xSkidEnd() - backPace() * (backEnd() - skidEnd())

    // ── 本体 ──

    /// 時刻 t の舞台状態（区分ごとの閉形式）。t は duration で折り返してループする。
    pub def stageAt(t0: Float64): Stage =
        let t = wrap(t0);
        if (t < runEnd()) {
            // 右走り: 等速。
            mk(t, startX() + runPace() * t, 0.0, 160.0, 1.0, Mode.RunMode, t)
        } else if (t < dashEnd()) {
            // ダッシュ: 実移動は等加速（35→55）、見かけの vx は 160→280 に立ち上げて
            // 280 で頭打ち（3 段階色の白が終盤しっかり見えるよう早めに満たす）。
            let u = t - runEnd();
            let x = xRunEnd() + runPace() * u + (dashPace() - runPace()) / (dashEnd() - runEnd()) / 2.0 * u * u;
            mk(t, x, 0.0, Float64.min(280.0, 160.0 + 150.0 * u), 1.0, Mode.DashMode, u)
        } else if (t < skidEnd()) {
            // スキッド: 実移動は 55→0 の等減速、見かけの vx も 280→0 に落ちる。
            let u = t - dashEnd();
            let w = skidEnd() - dashEnd();
            let x = xDashEnd() + dashPace() * u - dashPace() / (2.0 * w) * u * u;
            mk(t, x, 0.0, 280.0 * (1.0 - u / w), 1.0, Mode.SkidMode, u)
        } else if (t < backEnd()) {
            // 左走り: 等速（facing 反転）。
            let u = t - skidEnd();
            mk(t, xSkidEnd() - backPace() * u, 0.0, -160.0, -1.0, Mode.RunMode, u)
        } else if (t < stopEnd()) {
            // 左スキッド: backPace→0 の等減速で開始点にぴたり停止。
            let u = t - backEnd();
            let w = stopEnd() - backEnd();
            let x = xBackEnd() - backPace() * u + backPace() / (2.0 * w) * u * u;
            mk(t, x, 0.0, -160.0 * (1.0 - u / w), -1.0, Mode.SkidMode, u)
        } else if (t < landAt()) {
            // ジャンプ: その場で放物線（頂点 48px @ 4.05）。前半は上昇、後半は落下。
            let u = t - stopEnd();
            let half = (apexT() - stopEnd());
            let k = (u - half) / half;
            let y = -48.0 * (1.0 - k * k);
            if (u < half) mk(t, startX(), y, 0.0, 1.0, Mode.JumpMode, u)
            else          mk(t, startX(), y, 0.0, 1.0, Mode.FallMode, u - half)
        } else if (t < landEnd()) {
            // 着地: スカッシュの窓（0.2 秒）。
            mk(t, startX(), 0.0, 0.0, 1.0, Mode.LandMode, t - landAt())
        } else {
            // 待機: 呼吸して次の周回を待つ。
            mk(t, startX(), 0.0, 0.0, 1.0, Mode.IdleMode, t - landEnd())
        }

    /// t を 0..duration に折り返す（負値も安全）。
    def wrap(t0: Float64): Float64 =
        t0 - duration() * Float64.floor(t0 / duration())

    def mk(t: Float64, x: Float64, y: Float64, vx: Float64,
           facing: Float64, mode: Mode, modeT: Float64): Stage =
        { t = t, pos = { x = x, y = y }, vx = vx, facing = facing, mode = mode, modeT = modeT }
}
