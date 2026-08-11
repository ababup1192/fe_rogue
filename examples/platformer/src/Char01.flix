// Char01 — 現行ヒーロー（比較基準）。本編の Hero.flix（ポーズ表・ダッシュ 3 段階色・
// 伸び/潰れ）をそのまま Stage に写した、キャラクターラボの基準スロット。
// 走りのコマは本編と同じ移動量駆動（pos.x × gaitK）— 足が地面を滑らない。
// スキッドは現行に専用ポーズが無いので走りポーズのまま（本編では土埃が語る部分・ここは素で）。
// この箱組みは旧様式(RawDraw 大量使用の前例にしない)。新キャラは PxSprite+PxShade を第一候補に。

mod Char01 {

    /// 名簿（Roster）と HUD に出す名前。ラボのレーンラベルは CharGallery が別に持つ。
    pub def name(): String = "01 HERO"

    /// キャラクターラボの唯一のインターフェイス: Stage → 足元中心ローカルの描画パーツ列。
    pub def draw(stage: CharStage.Stage): List[Render.PlacedItem] =
        let pose = poseOf(stage#mode);
        let look = { pose = pose,
                     frame = frameOf(pose, stage),
                     facing = stage#facing,
                     tint = tintOf(stage#vx),
                     stretch = stretchOf(stage),
                     squash = squashOf(stage) };
        Hero.parts(look) |> List.map(p -> {
            let topLeft = { x = stage#pos#x + p#cx - p#w / 2.0,
                            y = stage#pos#y - p#cy - p#h / 2.0 };
            let box = RawDraw.box({ x = p#w, y = p#h }, p#color, zChar() + p#z);
            if (p#r <= 0.0) { at = topLeft, item = box } else { at = topLeft, item = box |> Render.rounded(p#r) }
        })

    /// キャラの z 帯（レーンの地面より前・ラベルより後ろ）。
    def zChar(): Int32 = 10

    /// Mode → 現行ヒーローの 4 ポーズ。ダッシュ/スキッドは走りポーズ、着地は待機ポーズで潰す。
    def poseOf(mode: CharStage.Mode): Hero.Pose = match mode {
        case CharStage.Mode.IdleMode => Hero.Pose.IdlePose
        case CharStage.Mode.RunMode  => Hero.Pose.RunPose
        case CharStage.Mode.DashMode => Hero.Pose.RunPose
        case CharStage.Mode.SkidMode => Hero.Pose.RunPose
        case CharStage.Mode.JumpMode => Hero.Pose.JumpPose
        case CharStage.Mode.FallMode => Hero.Pose.FallPose
        case CharStage.Mode.LandMode => Hero.Pose.IdlePose
    }

    /// コマ選択は本編と同じ: 走り = 移動量駆動（10px で 1 コマ）・待機 = 時刻駆動・空中 = 1 コマ。
    def frameOf(pose: Hero.Pose, stage: CharStage.Stage): Int32 =
        Hero.frameOf(pose, stage#t, stage#pos#x)

    /// 段階演出の色 3 段階（本編 View.playerColor と同じしきい値）:
    /// 通常（≤160 黄）→ P スピード帯（>160 橙）→ 最高速域（≥279.5 白）。
    def tintOf(vx: Float64): Color =
        let speed = Float64.abs(vx);
        let maxBand = Jump.maxRunSpeed() * Jump.dashMult() - 0.5;
        if (speed >= maxBand) Palette.playerMax()
        else if (speed > Jump.maxRunSpeed()) Palette.playerDash()
        else Palette.player()

    /// ジャンプ伸び: 踏み切り直後が最大で 0.3 秒かけて素に戻る（本編の vy 由来の式を
    /// Stage には vy が無いので modeT で近似）。
    def stretchOf(stage: CharStage.Stage): Float64 =
        match stage#mode {
            case CharStage.Mode.JumpMode => Float64.max(0.0, 1.0 - stage#modeT / 0.3)
            case _                       => 0.0
        }

    /// 着地スカッシュ: 着地の瞬間が最大で 0.2 秒（LandMode の窓いっぱい）かけて戻る。
    def squashOf(stage: CharStage.Stage): Float64 =
        match stage#mode {
            case CharStage.Mode.LandMode => Float64.max(0.0, 1.0 - stage#modeT / 0.2)
            case _                       => 0.0
        }
}
