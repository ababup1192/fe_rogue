// Robot — プレイヤーキャラクター: 背が高く目が1つの「サイクロプス」ロボット、
// クレートと同様に手続き的に描かれる。1つの関数が、任意の向きと任意の歩行位相
// に対するパーツを返す；ポーズは (dir, phase) の純粋な関数であり、決して状態の
// 一片ではない。
//
// 4方向すべてが同じ接地行と高さを共有する。横向きの見た目は、目立って狭い胴体
// のスラブ（正面幅ではなく、奥行き）、体を挟む2本の腕ではなく1本のL字に曲がった
// 手前側の腕、そして静止時は1つの足ブロックを使う —— これは腕を省略した正面図で
// はなく、横顔のシルエットが必要とするレイアウトである。
//
// 目は真円である（半分のサイズを cornerRadius に持つボックス）。横顔ではカタツ
// ムリの目のようなレンズになる: 球が先端から約1.4ユニットせり出し（シルエットの
// 唯一の意図的な破れ）、縁で約4ユニットの高さの土台の弦によって固定され、体に接
// 続しているように見える；体色のバーが体の内側にある球の部分を隠す。瞳孔は高さ
// の約55%に押しつぶされたカプセル —— 球を真横から見た円盤 —— で、レンズの先端
// に配置される。
//
// その場歩行サイクルは4コマで構成される: 静止 -> 一歩 -> 静止 -> 一歩。正面と背面
// では、一歩は足の上げと体のバウンスとして読まれ、腕は逆位相で伸縮する（肩は固
// 定）—— 正面から見た腕の前後スイング；横顔ではこれは歩幅として読まれる —— 足
// ブロックは前後のペアに分かれ、前腕がスイングし（一歩ごとに後ろ・前と交互に）、
// 体は開いた両足の間でわずかに沈む。目はどの向きでも体の動きに乗る: ロボットは
// 視線も含めて1つの生き物として弾む。位相 0.0 は静止ポーズである —— 立っている
// ロボットと歩いているロボットは、異なる位相における同じ関数である。
//
// パーツは16ユニットのタイルグリッド上に配置され、要求されたタイルサイズでスケ
// ールされるので、同じ関数が8倍のギャラリー表示にもゲーム内タイルにも使える。

mod Robot {

    /// 16ユニットグリッド上の1パーツ。r > 0 は角を丸める（r = min(w,h)/2 = 円）。
    type alias Part = {
        x = Float64, y = Float64, w = Float64, h = Float64,
        r = Float64, color = Color, z = Int32
    }

    /// 位相から導出される歩行ポーズ、グリッド単位。bob/liftL/liftR は正面・背面
    /// ビュー（体の持ち上がり、片足ずつの上げ）を駆動する；stride/swing は横顔
    /// （足の前後開き、前腕の歩行軸に沿った移動）を駆動する。swing の符号は、一
    /// 歩ごとに前後どちらの腕が縮み、どちらが伸びるかも決める。
    type alias Pose = {
        bob = Float64, liftL = Float64, liftR = Float64,
        stride = Float64, swing = Float64
    }

    /// `center` を中心に、`size` px のタイル上で、歩行位相 `phase`（0..1、0が
    /// 静止ポーズ）で `dir` を向くロボットの全パーツ。
    pub def parts(center: Vec2.Vec2, size: Float64, dir: Dir4.Dir4,
                  phase: Float64): List[Render.Placed] =
        let pose = poseOf(phase);
        let ps = match dir {
            case Dir4.Down  => front(pose)
            case Dir4.Up    => back(pose)
            case Dir4.Right => side(pose)
            case Dir4.Left  => List.map(mirrorX, side(pose))
        };
        List.map(toItem(center, size), ps)

    /// サイクルあたり4コマ: 静止 -> 一歩 -> 静止 -> 一歩。一歩のコマは足を1.5ユニッ
    /// ト持ち上げ、体を1ユニットバウンスさせ（正面・背面ビュー）、前腕を1歩目は
    /// 後ろに、2歩目は前にスイングして歩幅を開く（横顔）。位相0はちょうど静止ポ
    /// ーズである。
    def poseOf(phase: Float64): Pose =
        let p = phase - Float64.floor(phase);
        if (p < 0.25)      { bob = 0.0, liftL = 0.0, liftR = 0.0, stride = 0.0, swing = 0.0 }
        else if (p < 0.5)  { bob = 1.0, liftL = 1.5, liftR = 0.0, stride = 1.0, swing = -1.0 }
        else if (p < 0.75) { bob = 0.0, liftL = 0.0, liftR = 0.0, stride = 0.0, swing = 0.0 }
        else               { bob = 1.0, liftL = 0.0, liftR = 1.5, stride = 1.0, swing = 1.0 }

    // ── 各向き（16ユニットグリッド、y は下向き、接地行は y = 15.5 で共有）──
    // 接地している足を除くすべてが歩行の動き（バウンスまたは沈み込み）に乗る。
    // 目も例外ではない。

    /// 正面（Down）: 丸い1つの目が中央に位置する。基準となる向き。
    /// 歩行中は腕が逆位相で伸縮する —— 正面から見た前後スイングの短縮された見た
    /// 目 —— 肩は固定され、裾だけが動く。
    def front(pose: Pose): List[Part] =
        let b = pose#bob;
        let a = 1.2 * pose#swing;
        part(4.5, 2.0 - b, 7.0, 12.0, Palette.robotBody(), 0) ::        // 胴体のスラブ
        part(4.5, 2.0 - b, 7.0, 1.0, Palette.robotTrim(), 1) ::         // 上部のハイライト
        round(6.0, 4.0 - b, 4.0, 4.0, Palette.robotEye(), 1) ::         // 目（真円）
        round(7.1, 5.1 - b, 1.8, 1.8, Palette.robotDark(), 2) ::        // 瞳孔
        part(6.0, 9.6 - b, 4.0, 0.7, Palette.robotDark(), 1) ::         // 口の線
        part(5.4, 11.0 - b, 1.2, 0.6, Palette.robotAccent(), 1) ::      // 通気口 1
        part(5.4, 12.0 - b, 1.2, 0.6, Palette.robotAccent(), 1) ::      // 通気口 2
        part(3.0, 5.0 - b, 1.5, 5.0 - a, Palette.robotTrim(), 0) ::     // 左腕
        part(11.5, 5.0 - b, 1.5, 5.0 + a, Palette.robotTrim(), 0) ::    // 右腕
        part(5.0, 14.0 - pose#liftL, 2.5, 1.5, Palette.robotTrim(), 0) ::   // 左足
        part(8.5, 14.0 - pose#liftR, 2.5, 1.5, Palette.robotTrim(), 0) :: Nil  // 右足

    /// 背面（Up）: 目はなし；アクセントで照らされたスリット付きの暗いサービスパ
    /// ネルが「これは背中である」の印 —— 正面の通気口と同じ「暗い地に黄色い線」
    /// という文法。歩行中は正面と同様、腕が逆位相で伸縮する。
    def back(pose: Pose): List[Part] =
        let b = pose#bob;
        let a = 1.2 * pose#swing;
        part(4.5, 2.0 - b, 7.0, 12.0, Palette.robotBody(), 0) ::        // 胴体のスラブ
        part(4.5, 2.0 - b, 7.0, 1.0, Palette.robotTrim(), 1) ::         // 上部のハイライト
        part(5.8, 4.0 - b, 4.4, 4.6, Palette.robotDark(), 1) ::         // 背面パネル
        part(6.4, 5.0 - b, 3.2, 0.5, Palette.robotAccent(), 2) ::       // スリット 1
        part(6.4, 6.1 - b, 3.2, 0.5, Palette.robotAccent(), 2) ::       // スリット 2
        part(6.4, 7.2 - b, 3.2, 0.5, Palette.robotAccent(), 2) ::       // スリット 3
        part(3.0, 5.0 - b, 1.5, 5.0 - a, Palette.robotTrim(), 0) ::     // 左腕
        part(11.5, 5.0 - b, 1.5, 5.0 + a, Palette.robotTrim(), 0) ::    // 右腕
        part(5.0, 14.0 - pose#liftL, 2.5, 1.5, Palette.robotTrim(), 0) ::   // 左足
        part(8.5, 14.0 - pose#liftR, 2.5, 1.5, Palette.robotTrim(), 0) :: Nil  // 右足

    /// 横顔（Right）: 奥行きとして読める狭いスラブで、正面幅ではない。目はカタ
    /// ツムリの目のようなレンズ: 球が先端から約1.4ユニットせり出し、縁の約4ユニ
    /// ットの土台の弦で固定される；体色のバーが体の内側にある球の部分を隠し、押
    /// しつぶされたカプセル型の瞳孔が先端に位置する。手前側の腕はL字 —— 上腕は
    /// 下向き、前腕は前方に曲がる —— で、その前腕は歩幅に合わせてスイングする；
    /// 足は静止時は1つのブロックで、一歩の途中で前後のペアに開く。体全体（レン
    /// ズを含む）は開いた両足の間で0.7ユニット沈む。
    def side(pose: Pose): List[Part] =
        let d = 0.7 * pose#bob;
        let st = pose#stride;
        let sw = pose#swing;
        part(5.5, 2.0 + d, 5.0, 12.0, Palette.robotBody(), 0) ::        // 横顔の狭い胴体スラブ
        part(5.5, 2.0 + d, 5.0, 1.0, Palette.robotTrim(), 1) ::         // 上部のハイライト
        round(7.3, 3.7 + d, 4.6, 4.6, Palette.robotEye(), 1) ::         // レンズの球、先端からせり出す
        round(10.4, 5.1 + d, 1.0, 1.8, Palette.robotDark(), 2) ::       // 瞳孔: レンズの先端の真横カプセル
        part(7.3, 3.7 + d, 3.2, 4.6, Palette.robotBody(), 3) ::         // 体の内側にある球の部分を隠す
        part(6.9, 8.5 + d, 1.4, 2.5, Palette.robotTrim(), 1) ::         // 上腕、レンズの下にぶら下がる
        part(6.9 + sw, 9.6 + d, 2.6, 1.4, Palette.robotTrim(), 1) ::    // 前方に曲がった前腕；歩幅に対してスイングする
        part(6.85 - 1.3 * st, 14.0, 2.3, 1.5, Palette.robotTrim(), 0) ::    // 後ろ足
        part(6.85 + 1.3 * st, 14.0, 2.3, 1.5, Palette.robotTrim(), 0) :: Nil  // 前足；静止時にはちょうど後ろ足を覆う

    // ── ヘルパー ──

    def part(x: Float64, y: Float64, w: Float64, h: Float64, c: Color, z: Int32): Part =
        { x = x, y = y, w = w, h = h, r = 0.0, color = c, z = z }

    def round(x: Float64, y: Float64, w: Float64, h: Float64, c: Color, z: Int32): Part =
        { x = x, y = y, w = w, h = h, r = Float64.min(w, h) / 2.0, color = c, z = z }

    /// パーツをタイルの垂直中心線に対して鏡映する（Left = Right の鏡映）。
    def mirrorX(p: Part): Part =
        { x = 16.0 - p#x - p#w | p }

    def toItem(center: Vec2.Vec2, size: Float64, p: Part): Render.Placed =
        let s = size / 16.0;
        let tlx = center#x - size / 2.0;
        let tly = center#y - size / 2.0;
        let pos = {x = tlx + p#x * s, y = tly + p#y * s};
        let dim = {x = p#w * s, y = p#h * s};
        if (p#r <= 0.0)
            { at = pos, item = Render.solidBox(dim, p#color, p#z) }
        else
            { at = pos, item = Render.solidBox(dim, p#color, p#z) |> Render.rounded(p#r * s) }
}
