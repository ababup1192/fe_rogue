// Hero — プレイヤーの手続き描画。テクスチャは使わず、ボックスと角丸だけで
// 小さなヒーロー（体 + 目 2 個 + 短い脚 2 本・約 22×16px）を毎フレーム組み立てる。
// 敵（ずんぐりしたドーム）と混線しないよう、ヒーローは縦長のシルエットにする。
//
// コマ選択は engine の Anim（時刻/移動量の純関数）が担い、ここは「そのコマを
// どう描くか」のポーズ表だけを持つ。走りのコマは時刻でなく走った距離で進める
// （frameAt(runClip, x × gaitK)）— 足が地面を滑らない、転がりドットの θ = x/半径 と
// 同じ移動量駆動。ポーズも状態ではなく (pose, frame) の純関数で、巻き戻し・
// リプレイ・ギャラリーの決定論はそのまま保たれる。
//
// パーツはローカル座標で組む: cx = 中心からの横オフセット（facing 反映済み）、
// cy = 足元線から上への高さ。足元線 = 当たり判定の円の下端（pos#y + playerRadius）
// なので、ヒーローは球体時代と同じ高さに立つ。着地スカッシュ・ジャンプ伸びは
// 全パーツのオフセットと寸法を足元基準で縦横スケールして表す。

mod Hero {

    /// 見た目の大分類。優先順は poseOf を参照（スキッドは専用ポーズを持たない —
    /// 前方へ流れるブレーキ土埃が既にスキッドを語っている）。
    pub enum Pose with Eq, ToString {
        case IdlePose
        case RunPose
        case JumpPose
        case FallPose
    }

    /// 描画 1 パーツ（ローカル座標・スケール適用済み）。r > 0 は角丸
    /// （r = min(w,h)/2 で円）。z はプレイヤー層からの相対（0=体・脚, 1=白目, 2=瞳）。
    pub type alias Part = {
        cx = Float64, cy = Float64, w = Float64, h = Float64,
        r = Float64, color = Color, z = Int32
    }

    /// 1 フレームぶんの見た目の指定。View が World から毎フレーム導く
    /// （squash = 着地スカッシュの残り比 0..1・stretch = ジャンプ伸びの量 0..1）。
    pub type alias Look = {
        pose = Pose, frame = Int32, facing = Float64,
        tint = Color, stretch = Float64, squash = Float64
    }

    // ── ポーズとコマの選択（純関数）──

    /// 状態からポーズを選ぶ。優先順: 空中（上昇 = Jump / 下降 = Fall）> 走り（|vx| > 10）> 待機。
    pub def poseOf(player: Field.Player): Pose =
        if (not player#grounded) {
            if (player#vel#y < 0.0) Pose.JumpPose else Pose.FallPose
        }
        else if (Float64.abs(player#vel#x) > 10.0) Pose.RunPose
        else Pose.IdlePose

    /// 待機クリップ: 2 コマ・2 コマ/秒の呼吸。t は World の通し時刻。
    /// row はスプライトシートを使わない手続き描画では読まれない（0 固定）。
    pub def idleClip(): Anim.Clip = { row = 0, frames = 2, fps = 2.0, looping = true }

    /// 走りクリップ: 4 コマ（接地 → 上げ → 交差 → 上げ）。fps = 1 にして
    /// frameAt(clip, x × gaitK) に走行距離を渡す = 10px 進むごとに 1 コマ。
    pub def runClip(): Anim.Clip = { row = 0, frames = 4, fps = 1.0, looping = true }

    /// 歩幅係数: 1 コマ / 10px。
    pub def gaitK(): Float64 = 0.1

    /// ポーズごとのコマ番号。走りは移動量駆動（x 位置）・待機は時刻駆動・空中は 1 コマ固定。
    pub def frameOf(pose: Pose, time: Float64, posX: Float64): Int32 = match pose {
        case Pose.IdlePose => Anim.frameAt(idleClip(), time)
        case Pose.RunPose  => Anim.frameAt(runClip(), posX * gaitK())
        case Pose.JumpPose => 0
        case Pose.FallPose => 0
    }

    // ── パーツの組み立て ──

    /// ポーズ 1 コマぶんの脚と体の配置。legADx/legBDx は脚の中心の横位置（facing 前が +）、
    /// lift は足裏の持ち上げ、bodyLift は体（目も乗る）の上下 — 呼吸の沈みは負、走りの弾みは正。
    type alias Gait = {
        legADx = Float64, legALift = Float64,
        legBDx = Float64, legBLift = Float64,
        bodyLift = Float64
    }

    /// 4 ポーズ × コマのポーズ表。走りは 接地（両脚を前後に開く）→ 上げ（後脚を畳む・体が弾む）→
    /// 交差（前後が入れ替わる）→ 上げ（逆脚）の 4 コマ。待機は体が 0.5px 沈む呼吸 2 コマ。
    /// ジャンプは両脚を縮めて畳み、落下は両脚を大きく開いて構える（1 コマずつ）。
    def gaitOf(pose: Pose, frame: Int32): Gait = match pose {
        case Pose.IdlePose =>
            if (Int32.modulo(frame, 2) == 0)
                { legADx = -3.0, legALift = 0.0, legBDx = 3.0, legBLift = 0.0, bodyLift = 0.0 }
            else
                { legADx = -3.0, legALift = 0.0, legBDx = 3.0, legBLift = 0.0, bodyLift = -0.5 }
        case Pose.RunPose  => runGait(Int32.modulo(frame, 4))
        case Pose.JumpPose => { legADx = -2.0, legALift = 2.0, legBDx = 2.0, legBLift = 2.0, bodyLift = 0.0 }
        case Pose.FallPose => { legADx = -5.0, legALift = 0.0, legBDx = 5.0, legBLift = 0.0, bodyLift = 0.0 }
    }

    /// 走り 4 コマの表: 接地（両脚を開く）→ 上げ（後脚を畳む）→ 交差 → 上げ（逆脚）。
    def runGait(step: Int32): Gait = match step {
        case 0 => { legADx = -3.5, legALift = 0.0, legBDx = 3.5, legBLift = 0.0, bodyLift = 0.0 }
        case 1 => { legADx = -1.0, legALift = 2.0, legBDx = 1.0, legBLift = 0.0, bodyLift = 1.0 }
        case 2 => { legADx = 3.5, legALift = 0.0, legBDx = -3.5, legBLift = 0.0, bodyLift = 0.0 }
        case _ => { legADx = -1.0, legALift = 0.0, legBDx = 1.0, legBLift = 2.0, bodyLift = 1.0 }
    }

    /// Look からヒーロー全パーツ（ローカル座標）を組む。順序: 体 → 目 → 脚。
    /// facing は横オフセットの符号だけを反転する（手続き描画なので flipH は不要）。
    /// squash は横広・縦低（着地）、stretch は縦長・横細（上昇）— 係数は球体時代と同じ。
    pub def parts(look: Look): List[Part] =
        let sx = 1.0 + 0.35 * look#squash - 0.10 * look#stretch;
        let sy = 1.0 - 0.35 * look#squash + 0.18 * look#stretch;
        let g = gaitOf(look#pose, look#frame);
        let bodyBottom = 4.0 + g#bodyLift;
        let bodyH = 18.0;
        let eyeCy = bodyBottom + 13.0;
        let raw =
            part(0.0, bodyBottom + bodyH / 2.0, 14.0, bodyH, 4.0, look#tint, 0) ::  // 体（縦長の角丸スラブ）
            circle(-3.5, eyeCy, 2.5, Palette.eyeWhite(), 1) ::                      // 白目（左）
            circle(-3.5 + 1.25, eyeCy, 1.25, Palette.eyePupil(), 2) ::              // 瞳（向いている側へ寄る）
            circle(3.5, eyeCy, 2.5, Palette.eyeWhite(), 1) ::                       // 白目（右）
            circle(3.5 + 1.25, eyeCy, 1.25, Palette.eyePupil(), 2) ::               // 瞳
            part(g#legADx, 2.5 + g#legALift, 4.0, 5.0, 1.5, Palette.heroLeg(), 0) ::    // 脚 A
            part(g#legBDx, 2.5 + g#legBLift, 4.0, 5.0, 1.5, Palette.heroLeg(), 0) :: Nil;  // 脚 B
        raw |> List.map(p -> {
            let w = p#w * sx;
            let h = p#h * sy;
            let r = Float64.min(p#r * Float64.min(sx, sy), Float64.min(w, h) / 2.0);
            { cx = p#cx * look#facing * sx, cy = p#cy * sy, w = w, h = h, r = r | p }
        })

    /// パーツをワールド座標の PlacedItem へ。zBase はプレイヤー層（残像は低い層を渡して
    /// 本体の下に重ねる）。足元線 = 当たり判定の円の下端に全パーツを吊るす。
    pub def draw(zBase: Int32, pos: Vec2.Vec2, look: Look): List[Render.PlacedItem] =
        let feetY = pos#y + Field.playerRadius();
        parts(look) |> List.map(p -> {
            let topLeft = { x = pos#x + p#cx - p#w / 2.0, y = feetY - p#cy - p#h / 2.0 };
            let box = Render.box({ x = p#w, y = p#h }, p#color, zBase + p#z);
            if (p#r <= 0.0) { at = topLeft, item = box } else { at = topLeft, item = box |> Render.rounded(p#r) }
        })

    // ── ヘルパー ──

    def part(cx: Float64, cy: Float64, w: Float64, h: Float64, r: Float64, c: Color, z: Int32): Part =
        { cx = cx, cy = cy, w = w, h = h, r = r, color = c, z = z }

    /// 真円 = 一辺 2r の角丸ボックス（squash で潰れるとカプセルに変形できる）。
    def circle(cx: Float64, cy: Float64, r: Float64, c: Color, z: Int32): Part =
        part(cx, cy, r * 2.0, r * 2.0, r, c, z)
}
