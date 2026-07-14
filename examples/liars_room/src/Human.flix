// Human — 人間のシルエットの手続き描画。NPC もプレイヤーも同じ体型で、色（Skin）だけが違う。
// パーツは 16 ユニットのタイルグリッド上に置かれ、要求されたタイルサイズでスケールされる
// （sokoban の Robot と同じ流儀 — ギャラリーの 8 倍表示にもゲーム内タイルにも同じ関数が使える）。
//
// 顔は描き込まない（シルエットらしさ）が、向きは読めるようにする: 正面は明るい顔パッチ、
// 背面は髪の暗いパッチ、横顔は顔パッチが進行方向の縁に寄る。
mod Human {

    /// 1 体ぶんの塗り分け。body = 本体、shade = 陰（腕・脚・髪）、
    /// hat = 帽子の色（プレイヤーの探偵帽。None なら帽子なし）。
    pub type alias Skin = { body = Color, shade = Color, hat = Option[Color] }

    /// 16 ユニットグリッド上の 1 パーツ。r > 0 は角を丸める（r = min(w,h)/2 = 円）。
    type alias Part = {
        x = Float64, y = Float64, w = Float64, h = Float64,
        r = Float64, color = Color, z = Int32
    }

    /// 位相から導出される歩行ポーズ。4 コマ: 静止 → 一歩 → 静止 → 一歩。
    /// swing は横顔の腕の前後（一歩ごとに符号が入れ替わる）。
    type alias Pose = {
        bob = Float64, liftL = Float64, liftR = Float64,
        stride = Float64, swing = Float64
    }

    /// `center` を中心に、`size` px のタイル上で、歩行位相 `phase`（0..1）で `dir` を向く人。
    pub def walking(center: Vec2.Vec2, size: Float64, skin: Skin,
                    dir: Dir4.Dir4, phase: Float64): List[Render.PlacedItem] =
        partsOf(center, size, skin, dir, poseOf(phase))

    /// 立ち姿（NPC 用）。bob は 0..1 の呼吸で、0.5 を境に体がわずかに沈む 2 コマ。
    pub def standing(center: Vec2.Vec2, size: Float64, skin: Skin,
                     dir: Dir4.Dir4, bob: Float64): List[Render.PlacedItem] =
        let settle = if (bob - Float64.floor(bob) < 0.5) 0.0 else 0.5;
        partsOf(center, size, skin, dir,
            { bob = settle, liftL = 0.0, liftR = 0.0, stride = 0.0, swing = 0.0 })

    def poseOf(phase: Float64): Pose =
        let p = phase - Float64.floor(phase);
        if (p < 0.25)      { bob = 0.0, liftL = 0.0, liftR = 0.0, stride = 0.0, swing = 0.0 }
        else if (p < 0.5)  { bob = 1.0, liftL = 1.2, liftR = 0.0, stride = 1.0, swing = -1.0 }
        else if (p < 0.75) { bob = 0.0, liftL = 0.0, liftR = 0.0, stride = 0.0, swing = 0.0 }
        else               { bob = 1.0, liftL = 0.0, liftR = 1.2, stride = 1.0, swing = 1.0 }

    def partsOf(center: Vec2.Vec2, size: Float64, skin: Skin,
                dir: Dir4.Dir4, pose: Pose): List[Render.PlacedItem] =
        let ps = match dir {
            case Dir4.Down  => front(skin, pose)
            case Dir4.Up    => back(skin, pose)
            case Dir4.Right => side(skin, pose)
            case Dir4.Left  => List.map(mirrorX, side(skin, pose))
        };
        List.map(toItem(center, size), ps)

    // ── 各向き（16 ユニットグリッド、y は下向き、接地行は y = 15.5 で共有）──

    /// 正面（Down）: 丸い頭（体から少し離れるピクトグラム風）+ 細身の角丸の胴 +
    /// カプセル状の腕脚。顔は描かない。帽子があれば頭の上につば + クラウン。
    def front(skin: Skin, pose: Pose): List[Part] =
        let b = pose#bob * 0.6;
        round(5.0, 0.8 - b, 6.0, 6.0, skin#body, 1) ::                    // 頭（真円）
        rrect(5.6, 7.4 - b, 4.8, 5.6, 1.6, skin#body, 0) ::               // 胴（細身・首の隙間あり）
        round(4.2, 7.7 - b, 1.3, 4.6, skin#shade, 0) ::                   // 左腕（カプセル）
        round(10.5, 7.7 - b, 1.3, 4.6, skin#shade, 0) ::                  // 右腕
        round(5.8, 13.1 - pose#liftL, 1.8, 2.4, skin#shade, 0) ::         // 左脚
        round(8.4, 13.1 - pose#liftR, 1.8, 2.4, skin#shade, 0) ::         // 右脚
        hatFront(skin, 0.0 - b)                                           // 帽子（あれば最前面）

    /// 背面（Up）: 正面と同じ素の丸頭（頭に模様は描かない）。
    def back(skin: Skin, pose: Pose): List[Part] =
        let b = pose#bob * 0.6;
        round(5.0, 0.8 - b, 6.0, 6.0, skin#body, 1) ::                    // 頭
        rrect(5.6, 7.4 - b, 4.8, 5.6, 1.6, skin#body, 0) ::               // 胴
        round(4.2, 7.7 - b, 1.3, 4.6, skin#shade, 0) ::                   // 左腕
        round(10.5, 7.7 - b, 1.3, 4.6, skin#shade, 0) ::                  // 右腕
        round(5.8, 13.1 - pose#liftL, 1.8, 2.4, skin#shade, 0) ::         // 左脚
        round(8.4, 13.1 - pose#liftR, 1.8, 2.4, skin#shade, 0) ::         // 右脚
        hatFront(skin, 0.0 - b)                                           // 帽子（あれば最前面）

    /// 横顔（Right）: 胴は正面と同じ幅の素直なシルエット。手前の腕は胴の前縁に
    /// 少しはみ出して重ね（胴の内側に閉じ込めるとドーナツに見える）、歩幅に合わせて振る。
    def side(skin: Skin, pose: Pose): List[Part] =
        let d = 0.4 * pose#bob;
        let st = pose#stride;
        round(5.0, 0.8 + d, 6.0, 6.0, skin#body, 1) ::                    // 頭
        rrect(5.7, 7.4 + d, 4.6, 5.6, 1.6, skin#body, 0) ::               // 胴
        round(9.2 + 0.9 * pose#swing, 8.0 + d, 1.5, 4.4, skin#shade, 1) ::  // 手前の腕（前縁）
        round(7.1 - 1.3 * st, 13.1, 1.8, 2.4, skin#shade, 0) ::           // 後ろ脚
        round(7.1 + 1.3 * st, 13.1, 1.8, 2.4, skin#shade, 0) ::           // 前脚
        hatSide(skin, d)                                                  // 探偵帽（あれば最前面）

    // ── 探偵帽（プレイヤーの目印。色を変えるだけでは主役だと分からないため）──

    /// 正面・背面の帽子: 頭に深くかぶせる。つばは頭より広く、クラウンは頭頂の幅
    /// （その高さでの頭の幅 ≈ 5.1）より広い 6.4 にして、頭がはみ出さないようにする。
    def hatFront(skin: Skin, yOff: Float64): List[Part] =
        match skin#hat {
            case None      => Nil
            case Some(hat) =>
                rrect(3.4, 2.2 + yOff, 9.2, 1.2, 0.6, hat, 3) ::          // つば（頭より広い）
                rrect(4.8, -0.4 + yOff, 6.4, 2.8, 1.3, hat, 3) :: Nil     // クラウン（頭頂を覆う）
        }

    /// 横顔の帽子: 前後は正面と同じ深さで、つばが進行方向へ少し突き出る。
    def hatSide(skin: Skin, yOff: Float64): List[Part] =
        match skin#hat {
            case None      => Nil
            case Some(hat) =>
                rrect(4.0, 2.2 + yOff, 9.4, 1.2, 0.6, hat, 3) ::          // つば（前へ突き出す）
                rrect(4.8, -0.4 + yOff, 6.4, 2.8, 1.3, hat, 3) :: Nil     // クラウン
        }

    // ── ヘルパー ──

    def rrect(x: Float64, y: Float64, w: Float64, h: Float64, r: Float64,
              c: Color, z: Int32): Part =
        { x = x, y = y, w = w, h = h, r = r, color = c, z = z }

    def round(x: Float64, y: Float64, w: Float64, h: Float64, c: Color, z: Int32): Part =
        { x = x, y = y, w = w, h = h, r = Float64.min(w, h) / 2.0, color = c, z = z }

    /// パーツをタイルの垂直中心線に対して鏡映する（Left = Right の鏡映）。
    def mirrorX(p: Part): Part =
        { x = 16.0 - p#x - p#w | p }

    def toItem(center: Vec2.Vec2, size: Float64, p: Part): Render.PlacedItem =
        let s = size / 16.0;
        let tlx = center#x - size / 2.0;
        let tly = center#y - size / 2.0;
        let pos = {x = tlx + p#x * s, y = tly + p#y * s};
        let dim = {x = p#w * s, y = p#h * s};
        if (p#r <= 0.0)
            { at = pos, item = Render.box(dim, p#color, p#z) }
        else
            { at = pos, item = Render.box(dim, p#color, p#z) |> Render.rounded(p#r * s) }
}
