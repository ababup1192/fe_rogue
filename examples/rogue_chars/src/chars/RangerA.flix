// RangerA — 緑装束の森の狩人（弓）。緑の頭巾から赤毛の三つ編みが覗く、静かな狩人。
//
// 個性は頭部で出す: 緑のフード + 赤毛の三つ編み + 切れ長の目。
// 弓（ロングボウ）は待機/歩行でも常に手にあり、攻撃で引き絞り→放つ。矢は明色の直線。
//
// 色: 緑装束(green/darkGreen/olive) + 革の胸当て(brown/darkBrown) + 肌(skin)
//     + 赤毛(orange/red) + 弓(darkBrown) + 弦/矢(tan/yellow)。

mod RangerA {
    use PixelCanvas.Canvas
    use PixelCanvas.{empty, dot, hline, vline, line, rectFill, shift, overlay}

    // ── 色の別名（このキャラのパレット）──
    def hood(): Color = RoguePalette.darkGreen()   // 頭巾の主色
    def hoodLit(): Color = RoguePalette.green()     // 頭巾のハイライト
    def cloth(): Color = RoguePalette.green()       // 緑装束
    def clothDk(): Color = RoguePalette.darkGreen() // 装束の影
    def leather(): Color = RoguePalette.brown()     // 革の胸当て
    def leatherDk(): Color = RoguePalette.darkBrown() // 革の影
    def skin(): Color = RoguePalette.skin()         // 肌
    def hair(): Color = RoguePalette.orange()       // 赤毛
    def hairDk(): Color = RoguePalette.red()        // 赤毛の影
    def eye(): Color = RoguePalette.black()         // 切れ長の目
    def bow(): Color = RoguePalette.darkBrown()     // 弓（ロングボウ）
    def bowLit(): Color = RoguePalette.brown()      // 弓のハイライト
    def string(): Color = RoguePalette.silver()     // 弦
    def arrowC(): Color = RoguePalette.yellow()     // 矢（明色）
    def boots(): Color = RoguePalette.olive()       // 革ブーツ/脚絆

    pub def name(): String = "RANGER A 静かなる狩人"

    /// 範囲外frameの丸め（負数も安全側へ）。
    def wrap(frame: Int32, n: Int32): Int32 =
        let m = Int32.remainder(frame, n);
        if (m < 0) m + n else m

    pub def draw(clip: RogueStage.Clip, frame: Int32): Canvas =
        let n = RogueStage.frameCount(clip);
        let f = wrap(frame, n);
        match clip {
            case RogueStage.Clip.IdleDown    => idleDown(f)
            case RogueStage.Clip.IdleUp      => idleUp(f)
            case RogueStage.Clip.IdleSide    => idleSide(f)
            case RogueStage.Clip.WalkDown    => walkDown(f)
            case RogueStage.Clip.WalkUp      => walkUp(f)
            case RogueStage.Clip.WalkSide    => walkSide(f)
            case RogueStage.Clip.AttackDown  => attackDown(f)
            case RogueStage.Clip.AttackUp    => attackUp(f)
            case RogueStage.Clip.AttackSide  => attackSide(f)
            case RogueStage.Clip.UseItemDown => useItemDown(f)
            case RogueStage.Clip.UseItemUp   => useItemUp(f)
            case RogueStage.Clip.UseItemSide => useItemSide(f)
            case RogueStage.Clip.DamageDown  => damageDown(f)
            case RogueStage.Clip.DamageUp    => damageUp(f)
            case RogueStage.Clip.DamageSide  => damageSide(f)
            case RogueStage.Clip.Death       => death(f)
        }

    // ══════════════════════════════════════════════════════════════
    // 頭部パーツ（個性）: 緑の頭巾 + 赤毛の三つ編み + 切れ長の目
    // ══════════════════════════════════════════════════════════════

    /// 正面の頭（Down 用）。頭巾 x=12..19・y=4..10、顔は中央、三つ編みが右肩へ垂れる。
    def headDown(): Canvas =
        empty()
            // 頭巾のドーム
            |> hline(13, 4, 6, hood())
            |> hline(12, 5, 8, hood())
            |> dot(12, 6, hood())
            |> hline(13, 6, 1, hoodLit())        // 頭巾の光
            |> hline(14, 6, 4, skin())            // 顔（額）
            |> dot(19, 6, hood())
            |> dot(12, 7, hood())
            |> hline(13, 7, 6, skin())            // 顔
            |> dot(19, 7, hood())
            // 切れ長の目（左右）
            |> dot(14, 7, eye())
            |> dot(17, 7, eye())
            |> dot(12, 8, hood())
            |> hline(13, 8, 6, skin())
            |> dot(19, 8, hood())
            |> hline(14, 9, 4, skin())            // 顎
            |> dot(15, 9, hood())                // 頭巾の縁が顎脇に
            // 赤毛の三つ編み（右肩へ垂れる）
            |> vline(19, 8, 4, hair())
            |> dot(20, 9, hairDk())
            |> dot(19, 12, hairDk())
            |> dot(13, 8, hair())                // 左のほつれ毛

    /// 背面の頭（Up 用）。後頭部の頭巾 + 背中へ垂れる三つ編み。
    def headUp(): Canvas =
        empty()
            |> hline(13, 4, 6, hood())
            |> hline(12, 5, 8, hood())
            |> hline(12, 6, 8, hood())
            |> hline(13, 6, 2, hoodLit())         // 頭巾の光
            |> hline(12, 7, 8, hood())
            |> hline(13, 8, 6, hood())
            // 赤毛の三つ編み（背中の中央へ）
            |> vline(15, 9, 5, hair())
            |> dot(16, 9, hair())
            |> dot(15, 11, hairDk())
            |> dot(15, 13, hairDk())
            |> dot(16, 12, hair())

    /// 側面（左向き）の頭（Side 用）。フードの横顔 + 顔は左、三つ編みが後ろ（右）へ。
    def headSide(): Canvas =
        empty()
            |> hline(12, 4, 6, hood())
            |> hline(11, 5, 8, hood())
            |> dot(11, 6, hood())
            |> hline(12, 6, 2, skin())            // 額（左向き）
            |> hline(14, 6, 4, hood())
            |> dot(11, 7, skin())                // 鼻先
            |> hline(12, 7, 2, skin())
            |> dot(13, 7, eye())                 // 切れ長の目
            |> hline(14, 7, 4, hood())
            |> hline(12, 8, 3, skin())            // 頬・顎
            |> hline(15, 8, 3, hood())
            |> hline(13, 9, 2, skin())            // 顎
            |> dot(15, 9, hood())
            // 三つ編みが後頭部（右）から垂れる
            |> vline(18, 6, 5, hair())
            |> dot(18, 8, hairDk())
            |> dot(18, 10, hairDk())
            |> dot(19, 9, hair())

    // ══════════════════════════════════════════════════════════════
    // 胴体パーツ: 緑装束 + 革の胸当て
    // ══════════════════════════════════════════════════════════════

    /// 正面の胴（Down/Up 共用の下地）。肩 y=12、腰 y=21、脚〜足元 y=29。
    /// legShift で左右の足を前後にずらせる（歩行用）。
    def torsoFront(bodyDx: Int32, lFootDy: Int32, rFootDy: Int32): Canvas =
        empty()
            // 胴（緑装束）
            |> rectFill(13, 12, 6, 6, cloth())
            |> vline(13, 12, 6, clothDk())         // 左の影
            |> vline(18, 12, 6, clothDk())         // 右の影（左右対称の締め）
            // 革の胸当て
            |> hline(14, 12, 4, leather())
            |> hline(14, 13, 4, leather())
            |> dot(15, 14, leatherDk())
            |> dot(16, 14, leatherDk())
            // 腰の帯
            |> hline(13, 18, 6, leatherDk())
            // 脚（緑の脚絆）
            |> vline(14, 19, 8 + lFootDy, cloth())
            |> vline(15, 19, 8 + lFootDy, clothDk())
            |> vline(16, 19, 8 + rFootDy, clothDk())
            |> vline(17, 19, 8 + rFootDy, cloth())
            // ブーツ
            |> hline(13, 27 + lFootDy, 3, boots())
            |> hline(16, 27 + rFootDy, 3, boots())
            |> shift(bodyDx, 0)

    // ══════════════════════════════════════════════════════════════
    // 弓（ロングボウ）: 待機/歩行でも常に見える主役。幅2px + 弦。
    // ══════════════════════════════════════════════════════════════

    /// 正面/背面で体の右横に立てて持つ縦のロングボウ（x=21 付近）。
    /// bend で上下端を内へ寄せて弓のしなりを出す。弦は silver の直線。
    def bowVertical(x: Int32, topY: Int32, botY: Int32): Canvas =
        empty()
            // 弓の本体（縦の弧・幅2px）
            |> vline(x, topY + 1, botY - topY - 1, bow())
            |> vline(x + 1, topY + 2, botY - topY - 3, bowLit())  // ハイライト
            |> dot(x - 1, topY + 1, bow())        // 上ののけ（そり）
            |> dot(x - 1, botY - 1, bow())        // 下ののけ
            |> dot(x, topY, bow())
            |> dot(x, botY, bow())
            // 弦（上端〜下端をまっすぐ）
            |> line(x - 1, topY, x - 1, botY, string())

    // ══════════════════════════════════════════════════════════════
    // Idle: 静かに佇む。頭は揺れず、肩の呼吸だけ 1px。弓は横に。
    // ══════════════════════════════════════════════════════════════

    /// 呼吸: f=1,3 で 1px 沈む（頭は動かさず胴だけ）。
    def breath(f: Int32): Int32 = if (f == 1 or f == 3) 1 else 0

    def idleDown(f: Int32): Canvas =
        let dy = breath(f);
        // 足元を y=29 に接地させる（脚を 2px 伸ばす）。頭は動かさず余白を保つ。
        headDown()
            |> overlay(shift(0, dy, torsoFront(0, 2, 2)))
            |> overlay(shift(0, dy, idleArmsFront()))
            |> overlay(bowVertical(21, 11, 25))
            |> overlay(shift(0, dy, quiverBack()))

    def idleUp(f: Int32): Canvas =
        let dy = breath(f);
        // idleDown と同じく脚を 2px 伸ばして足元を y=29 に接地させる。
        headUp()
            |> overlay(shift(0, dy, torsoFront(0, 2, 2)))
            |> overlay(shift(0, dy, idleArmsFront()))
            |> overlay(bowVertical(21, 11, 25))
            |> overlay(shift(0, dy, quiverFront()))

    def idleSide(f: Int32): Canvas =
        let dy = breath(f);
        // 脚を 2px 伸ばして足元を y=29 に接地させる。
        headSide()
            |> overlay(shift(0, dy, torsoSideGrounded(0, 2)))
            |> overlay(shift(0, dy, idleArmSide()))
            |> overlay(bowVertical(19, 11, 25))
            |> overlay(shift(0, dy, quiverSideBack()))

    /// 正面の腕（両肩から手・弓を持つ右手は横へ）。
    def idleArmsFront(): Canvas =
        empty()
            // 左腕（体の左に下ろす）
            |> vline(12, 13, 5, cloth())
            |> dot(12, 17, skin())                // 左手
            // 右腕（弓へ伸ばす）
            |> vline(19, 13, 4, cloth())
            |> dot(20, 16, skin())                // 右手（弓を握る）
            |> dot(21, 16, skin())

    /// 側面（左向き）の腕（弓を前=左に構える手）。
    def idleArmSide(): Canvas =
        empty()
            |> vline(15, 13, 4, cloth())          // 上腕
            |> line(15, 16, 18, 17, cloth())      // 前腕を弓へ
            |> dot(18, 17, skin())                // 手

    /// 背に負う矢筒（正面から見て右肩越しに覗く）。
    def quiverBack(): Canvas =
        empty()
            |> vline(11, 10, 4, leatherDk())      // 筒
            |> dot(11, 9, arrowC())               // 覗く矢羽
            |> dot(12, 9, arrowC())
            |> dot(11, 8, yellowFletch())

    /// 背面から見た矢筒（背中中央にはっきり）。
    def quiverFront(): Canvas =
        empty()
            |> vline(12, 11, 5, leatherDk())
            |> vline(19, 11, 5, leatherDk())
            |> dot(12, 10, arrowC())
            |> dot(19, 10, arrowC())
            |> dot(12, 9, yellowFletch())
            |> dot(19, 9, yellowFletch())

    /// 側面の矢筒（背中=右側に覗く）。
    def quiverSideBack(): Canvas =
        empty()
            |> vline(11, 11, 4, leatherDk())
            |> dot(11, 10, arrowC())
            |> dot(11, 9, yellowFletch())

    def yellowFletch(): Color = RoguePalette.lightGreen()

    /// 側面（左向き）の胴。frontFootDy で前足を踏み出す（歩行）。
    def torsoSide(frontFootDy: Int32): Canvas =
        torsoSideGrounded(frontFootDy, 0)

    /// 脚を legDy 分だけ下げられる版（体を上げる歩行コマで足を地面に残すため）。
    def torsoSideGrounded(frontFootDy: Int32, legDy: Int32): Canvas =
        empty()
            // 胴（緑装束・横から見て少し細い）
            |> rectFill(13, 12, 5, 6, cloth())
            |> vline(13, 12, 6, clothDk())         // 背中側の影
            // 革の胸当て（前=左寄り）
            |> vline(14, 12, 4, leather())
            |> vline(15, 12, 4, leatherDk())
            // 帯
            |> hline(13, 18, 5, leatherDk())
            // 奥の脚
            |> vline(16, 19, 8 + legDy, clothDk())
            |> hline(15, 27 + legDy, 3, boots())
            // 手前の脚（踏み出し）
            |> vline(14, 19, 8 + frontFootDy + legDy, cloth())
            |> hline(13, 27 + frontFootDy + legDy, 3, boots())

    // ══════════════════════════════════════════════════════════════
    // Walk: 静かな忍び歩き。頭は揺れず、脚と腕だけが動く。
    // ══════════════════════════════════════════════════════════════

    def walkDown(f: Int32): Canvas =
        // 4コマ: 左踏み出し→中立→右踏み出し→中立。体の上下1px。
        // 体を bodyDy 上げても足は地面に残すため、脚を -bodyDy 分だけ伸ばす。
        let (lDy, rDy, bodyDy) = walkPhase(f);
        headDown()
            |> shift(0, bodyDy)
            |> overlay(shift(0, bodyDy, torsoFront(0, lDy - bodyDy, rDy - bodyDy)))
            |> overlay(shift(0, bodyDy, walkArmsFront(f)))
            |> overlay(bowVertical(21, 11 + bodyDy, 25 + bodyDy))
            |> overlay(shift(0, bodyDy, quiverBack()))

    def walkUp(f: Int32): Canvas =
        let (lDy, rDy, bodyDy) = walkPhase(f);
        headUp()
            |> shift(0, bodyDy)
            |> overlay(shift(0, bodyDy, torsoFront(0, lDy - bodyDy, rDy - bodyDy)))
            |> overlay(shift(0, bodyDy, walkArmsFront(f)))
            |> overlay(bowVertical(21, 11 + bodyDy, 25 + bodyDy))
            |> overlay(shift(0, bodyDy, quiverFront()))

    def walkSide(f: Int32): Canvas =
        // 左向き忍び歩き。前後の足が交互に踏み出す（f0 は左右非対称=lint要件）。
        let (frontDy, backSwing, bodyDy) = walkSidePhase(f);
        headSide()
            |> shift(0, bodyDy)
            // 体を bodyDy 上げても足は地面に残すため脚を -bodyDy 伸ばす。
            |> overlay(shift(0, bodyDy, torsoSideGrounded(frontDy, -bodyDy)))
            |> overlay(shift(0, bodyDy, walkArmSide(backSwing)))
            |> overlay(bowVertical(19, 11 + bodyDy, 25 + bodyDy))
            |> overlay(shift(0, bodyDy, quiverSideBack()))

    /// 正面歩行の位相: (左足dy, 右足dy, 体dy)。頭は shift しないので揺れない。
    def walkPhase(f: Int32): (Int32, Int32, Int32) = match f {
        case 0 => (-2, 1, 0)    // 左足を上げ（前へ）・右足接地
        case 1 => (0, 0, -1)    // 中立・体1px上げ
        case 2 => (1, -2, 0)    // 右足を上げ
        case _ => (0, 0, -1)    // 中立
    }

    /// 側面歩行の位相: (前足dy, 後腕の振り, 体dy)。
    def walkSidePhase(f: Int32): (Int32, Int32, Int32) = match f {
        case 0 => (-2, 2, 0)    // 前足を大きく踏み出す（後腕を後ろへ）
        case 1 => (0, 0, -1)
        case 2 => (1, -2, 0)    // 前足を引き（後腕を前へ）
        case _ => (0, 0, -1)
    }

    /// 正面の歩行腕（弓を握りつつ左腕を振る）。
    def walkArmsFront(f: Int32): Canvas =
        let swing = if (f == 0) -1 else if (f == 2) 1 else 0;
        empty()
            |> vline(12, 13, 5, cloth())
            |> dot(12, 17 + swing, skin())        // 左手が振れる
            |> vline(19, 13, 4, cloth())
            |> dot(20, 16, skin())
            |> dot(21, 16, skin())

    /// 側面の歩行腕。
    def walkArmSide(swing: Int32): Canvas =
        empty()
            |> vline(15, 13, 4, cloth())
            |> line(15, 16, 17 + swing, 17, cloth())
            |> dot(17 + swing, 17, skin())

    // ══════════════════════════════════════════════════════════════
    // Attack: 弓の引き絞り2→放ち（矢が飛ぶ）→残心。方向で矢の向きが変わる。
    //   f0 構え / f1 引き / f2 満draw(見得) / f3 放ち / f4 矢が飛ぶ / f5 残心
    // ══════════════════════════════════════════════════════════════

    def attackDown(f: Int32): Canvas =
        // 手前（下）へ狙う。弓を水平に倒し、矢は下方向へ飛ぶ。
        let base = headDown() |> overlay(torsoFront(0, 0, 0)) |> overlay(quiverBack());
        match f {
            case 0 => base |> overlay(bowDrawFront(0)) |> overlay(nockedArrowDown(0))
            case 1 => base |> overlay(bowDrawFront(1)) |> overlay(nockedArrowDown(1))
            case 2 => base |> overlay(bowDrawFront(2)) |> overlay(nockedArrowDown(2))  // 満draw
            case 3 => base |> overlay(bowDrawFront(0)) |> overlay(loosedFront())        // 放ち
            case 4 => base |> overlay(bowDrawFront(0)) |> overlay(arrowFlyDown())       // 矢が飛ぶ
            case _ => base |> overlay(bowVertical(21, 11, 25)) |> overlay(idleArmsFront()) // 残心
        }

    def attackUp(f: Int32): Canvas =
        // 奥（上）へ狙う。矢は上方向へ飛ぶ。
        let base = headUp() |> overlay(torsoFront(0, 0, 0)) |> overlay(quiverFront());
        match f {
            case 0 => base |> overlay(bowDrawFront(0)) |> overlay(nockedArrowUp(0))
            case 1 => base |> overlay(bowDrawFront(1)) |> overlay(nockedArrowUp(1))
            case 2 => base |> overlay(bowDrawFront(2)) |> overlay(nockedArrowUp(2))
            case 3 => base |> overlay(bowDrawFront(0)) |> overlay(loosedFront())
            case 4 => base |> overlay(bowDrawFront(0)) |> overlay(arrowFlyUp())
            case _ => base |> overlay(bowVertical(21, 11, 25)) |> overlay(idleArmsFront())
        }

    def attackSide(f: Int32): Canvas =
        // 左向き。弓を前（左）へ構え、弦を後ろ（右）へ引き、矢は左へ飛ぶ。
        let base = headSide() |> overlay(torsoSide(0)) |> overlay(quiverSideBack());
        match f {
            case 0 => base |> overlay(bowSide(0)) |> overlay(drawArmSide(0))
            case 1 => base |> overlay(bowSide(1)) |> overlay(drawArmSide(1))
            case 2 => base |> overlay(bowSide(2)) |> overlay(drawArmSide(2))  // 満draw・見得
            case 3 => base |> overlay(bowSide(0)) |> overlay(loosedSide())     // 放ち
            case 4 => base |> overlay(bowSide(0)) |> overlay(arrowFlySide())   // 矢が飛ぶ
            case _ => base |> overlay(bowVertical(19, 11, 25)) |> overlay(idleArmSide())
        }

    /// 正面の引き弓。draw=0..2 で弦の引き量が増える（見得）。
    /// 弓は左手で前に突き出し、右手が弦を体側へ引く。
    def bowDrawFront(draw: Int32): Canvas =
        let pull = draw;   // 弦を右へ引く量
        empty()
            // 左手＝弓を握って前（左）へ突き出す
            |> line(13, 14, 9, 14, cloth())        // 左腕を伸ばす
            |> dot(9, 14, skin())
            // 縦のロングボウ（左端 x=8）
            |> vline(8, 10, 9, bow())
            |> vline(9, 11, 7, bowLit())
            |> dot(7, 10, bow())
            |> dot(7, 18, bow())
            // 弦（引くほど右へ V 字に折れる）
            |> line(8, 10, 12 + pull, 14, string())
            |> line(8, 18, 12 + pull, 14, string())
            // 右手＝弦を引く（頬まで）
            |> line(19, 14, 13 + pull, 14, cloth())
            |> dot(12 + pull, 14, skin())

    /// 正面につがえた矢（下狙い）。draw で後ろへ下がる。
    def nockedArrowDown(draw: Int32): Canvas =
        line(8, 15, 12 + draw, 15, arrowC(), empty())
            |> dot(7, 15, arrowC())               // 鏃（下向きにこの先へ飛ぶ）

    def nockedArrowUp(draw: Int32): Canvas =
        line(8, 13, 12 + draw, 13, arrowC(), empty())
            |> dot(7, 13, arrowC())

    /// 放った瞬間（正面）: 弦が戻り、矢はまだ弓元に残像。
    def loosedFront(): Canvas =
        empty()
            |> line(13, 14, 9, 14, cloth())
            |> dot(9, 14, skin())
            |> vline(8, 10, 9, bow())
            |> line(8, 10, 8, 18, string())        // 弦が戻ってまっすぐ
            |> vline(19, 13, 4, cloth())
            |> dot(19, 16, skin())

    /// 矢が下方向へ飛ぶ（明色の直線 2px 幅・手前へ）。
    def arrowFlyDown(): Canvas =
        empty()
            |> line(8, 20, 3, 27, arrowC())
            |> line(9, 20, 4, 27, arrowC())        // 2px 幅
            |> dot(3, 28, arrowC())                // 鏃
            |> dot(11, 17, yellowFletch())         // 矢羽（後端）
            |> dot(12, 17, yellowFletch())

    /// 矢が上方向へ飛ぶ。
    def arrowFlyUp(): Canvas =
        empty()
            |> line(8, 12, 3, 4, arrowC())
            |> line(9, 12, 4, 4, arrowC())
            |> dot(3, 3, arrowC())
            |> dot(11, 15, yellowFletch())
            |> dot(12, 15, yellowFletch())

    // ── 側面の弓・引き腕 ──

    /// 側面（左向き）の弓。draw で弦の引きが深くなる。弓は前（左 x=9）。
    def bowSide(draw: Int32): Canvas =
        let pull = draw;
        empty()
            // 左手＝弓を握って前へ
            |> line(14, 15, 10, 15, cloth())
            |> dot(10, 15, skin())
            // 縦の弓（前）
            |> vline(9, 10, 10, bow())
            |> vline(10, 11, 8, bowLit())
            |> dot(8, 10, bow())
            |> dot(8, 19, bow())
            // 弦（右＝体側へ V 字に引く）
            |> line(9, 10, 14 + pull, 15, string())
            |> line(9, 19, 14 + pull, 15, string())

    /// 側面の引き腕（右手で弦を頬まで引く）。draw で肘が後ろへ。
    def drawArmSide(draw: Int32): Canvas =
        empty()
            |> line(15, 13, 15 + draw, 15, cloth())  // 肘を後ろへ
            |> dot(14 + draw, 15, skin())            // 弦を引く手

    /// 放った瞬間（側面）: 弦が戻る。
    def loosedSide(): Canvas =
        empty()
            |> line(14, 15, 10, 15, cloth())
            |> dot(10, 15, skin())
            |> vline(9, 10, 10, bow())
            |> line(9, 10, 9, 19, string())
            |> vline(15, 13, 3, cloth())
            |> dot(15, 15, skin())

    /// 矢が左へ飛ぶ（明色の直線 2px 幅）。
    def arrowFlySide(): Canvas =
        empty()
            |> hline(1, 14, 7, arrowC())
            |> hline(1, 15, 7, arrowC())           // 2px 幅
            |> dot(0, 14, arrowC())                // 鏃
            |> dot(0, 15, arrowC())
            |> dot(8, 13, yellowFletch())          // 矢羽（後端）
            |> dot(8, 16, yellowFletch())

    // ══════════════════════════════════════════════════════════════
    // UseItem: 掲げる→明色フラッシュ→使う の3拍（4コマ）。薬瓶を飲む狩人。
    // ══════════════════════════════════════════════════════════════

    def useItemDown(f: Int32): Canvas =
        let base = headDown() |> overlay(torsoFront(0, 0, 0))
            |> overlay(bowVertical(21, 11, 25)) |> overlay(quiverBack());
        match f {
            case 0 => base |> overlay(itemArmsFront(0)) |> overlay(vial(15, 8, false))
            case 1 => base |> overlay(itemArmsFront(1)) |> overlay(vial(15, 5, false))  // 掲げる
            case 2 => base |> overlay(itemArmsFront(1)) |> overlay(vial(15, 5, true))   // フラッシュ
            case _ => base |> overlay(itemArmsFront(0)) |> overlay(vial(15, 9, false))  // 飲む
        }

    def useItemUp(f: Int32): Canvas =
        let base = headUp() |> overlay(torsoFront(0, 0, 0))
            |> overlay(bowVertical(21, 11, 25)) |> overlay(quiverFront());
        match f {
            case 0 => base |> overlay(itemArmsFront(0)) |> overlay(vial(15, 8, false))
            case 1 => base |> overlay(itemArmsFront(1)) |> overlay(vial(15, 4, false))
            case 2 => base |> overlay(itemArmsFront(1)) |> overlay(vial(15, 4, true))
            case _ => base |> overlay(itemArmsFront(0)) |> overlay(vial(15, 8, false))
        }

    def useItemSide(f: Int32): Canvas =
        let base = headSide() |> overlay(torsoSide(0))
            |> overlay(bowVertical(19, 11, 25)) |> overlay(quiverSideBack());
        match f {
            case 0 => base |> overlay(itemArmSide(0)) |> overlay(vial(13, 9, false))
            case 1 => base |> overlay(itemArmSide(1)) |> overlay(vial(12, 6, false))
            case 2 => base |> overlay(itemArmSide(1)) |> overlay(vial(12, 6, true))
            case _ => base |> overlay(itemArmSide(0)) |> overlay(vial(13, 10, false))
        }

    /// 正面のアイテム腕。raise=1 で右腕を口元へ掲げる。
    def itemArmsFront(raise: Int32): Canvas =
        empty()
            |> vline(12, 13, 5, cloth())
            |> dot(12, 17, skin())
            |> (cv -> if (raise == 1)
                    line(19, 14, 16, 10, cloth(), cv) |> dot(16, 10, skin())
                else
                    vline(19, 13, 4, cloth(), cv) |> dot(19, 16, skin()))

    /// 側面のアイテム腕。
    def itemArmSide(raise: Int32): Canvas =
        empty()
            |> (cv -> if (raise == 1)
                    line(15, 14, 13, 9, cloth(), cv) |> dot(13, 9, skin())
                else
                    line(15, 15, 13, 16, cloth(), cv) |> dot(13, 16, skin()))

    /// 薬瓶。glow=true で中身が白く光る（フラッシュ）。
    def vial(x: Int32, y: Int32, glow: Bool): Canvas =
        let liquid = if (glow) RoguePalette.white() else RoguePalette.lightGreen();
        empty()
            |> dot(x, y - 1, RoguePalette.tan())   // 栓
            |> dot(x, y, RoguePalette.silver())    // 瓶
            |> dot(x, y + 1, liquid)               // 中身
            |> (cv -> if (glow)
                    dot(x - 1, y, RoguePalette.white(), cv)
                        |> dot(x + 1, y, RoguePalette.white())
                        |> dot(x, y + 2, RoguePalette.white())
                else cv)

    // ══════════════════════════════════════════════════════════════
    // Damage: f0=全身白フラッシュ+ノックバック → のけぞり(3コマ)。
    // ══════════════════════════════════════════════════════════════

    def damageDown(f: Int32): Canvas =
        // 手前へノックバック（下＋のけぞり）。
        match f {
            case 0 => whiteSilhouette(idleDown(0)) |> shift(0, 2)      // 全身白+手前へ
            case 1 => idleDown(0) |> shift(-1, 1)                       // のけぞり戻り
            case _ => idleDown(0)
        }

    def damageUp(f: Int32): Canvas =
        // 奥へノックバック（上）。
        match f {
            case 0 => whiteSilhouette(idleUp(0)) |> shift(0, -2)
            case 1 => idleUp(0) |> shift(1, -1)
            case _ => idleUp(0)
        }

    def damageSide(f: Int32): Canvas =
        // 横（右）へノックバック。左向きの体が右へ弾かれる。
        match f {
            case 0 => whiteSilhouette(idleSide(0)) |> shift(3, 0)
            case 1 => idleSide(0) |> shift(1, -1)                       // のけぞり
            case _ => idleSide(0)
        }

    /// 全ピクセルを white に置換した被弾フラッシュ。
    def whiteSilhouette(cv: Canvas): Canvas =
        Map.map(_ -> RoguePalette.white(), cv)

    // ══════════════════════════════════════════════════════════════
    // Death: よろめき(2)→膝から崩れ(2)→膝立ち前傾がくり(2)。倒れ伏さない。
    //   弓は手放さず膝に。最終コマも膝立ちの立面が読める。
    // ══════════════════════════════════════════════════════════════

    def death(f: Int32): Canvas = match f {
        case 0 => deathStagger(0)   // よろめき（後ろへ傾く）
        case 1 => deathStagger(1)   // よろめき（前へ揺り戻し）
        case 2 => deathKneel(0)     // 膝から崩れ始め
        case 3 => deathKneel(1)     // 膝をつく
        case 4 => deathSlump(0)     // 膝立ち前傾
        case _ => deathSlump(1)     // 前傾がくり（最終・この後 Skeleton へ）
    }

    /// よろめき: 立ったまま上体が傾く。tilt=傾き方向。
    def deathStagger(phase: Int32): Canvas =
        let tilt = if (phase == 0) -1 else 1;
        headDown()
            |> shift(tilt, 0)
            |> overlay(shift(tilt, 0, torsoFront(0, 0, 0)))
            |> overlay(shift(tilt, 0, staggerArms()))
            |> overlay(bowVertical(21, 12, 26))    // 弓を握ったまま

    def staggerArms(): Canvas =
        empty()
            |> line(13, 13, 11, 18, cloth())       // 左腕がだらり
            |> dot(11, 18, skin())
            |> vline(19, 13, 4, cloth())
            |> dot(20, 16, skin())

    /// 膝から崩れる: 体が沈み、片膝を折る。phase で沈み量。
    def deathKneel(phase: Int32): Canvas =
        let sink = if (phase == 0) 3 else 5;   // 体全体を沈める
        headDown()
            |> shift(0, sink)
            |> overlay(shift(0, sink, kneelTorso()))
            |> overlay(shift(0, sink, staggerArms()))
            |> overlay(kneelLegs(phase))
            |> overlay(bowOnKnee(sink))

    /// 膝立ちの胴（脚は別途 kneelLegs）。
    def kneelTorso(): Canvas =
        empty()
            |> rectFill(13, 12, 6, 6, cloth())
            |> vline(13, 12, 6, clothDk())
            |> vline(18, 12, 6, clothDk())
            |> hline(14, 12, 4, leather())
            |> hline(14, 13, 4, leather())
            |> hline(13, 18, 6, leatherDk())

    /// 膝立ちの脚（折った膝が接地 y=29）。
    def kneelLegs(phase: Int32): Canvas =
        let spread = if (phase == 0) 1 else 0;
        empty()
            // 折った膝（前・接地）
            |> rectFill(13, 24, 3, 3, cloth())
            |> hline(12, 27, 5, boots())            // 膝〜脛が地面に
            |> hline(12, 28, 5, boots())
            // 立てた膝（後ろ）
            |> vline(17 + spread, 22, 5, cloth())
            |> vline(18 + spread, 22, 5, clothDk())
            |> hline(17 + spread, 27, 3, boots())

    /// 弓を膝の上に立てて握ったまま。
    def bowOnKnee(sink: Int32): Canvas =
        empty()
            |> vline(21, 16 + sink, 8, bow())
            |> vline(22, 17 + sink, 6, bowLit())
            |> line(20, 16 + sink, 20, 23 + sink, string())

    /// 膝立ち前傾のがくり。lean=前傾量。最終コマも膝立ちの立面が読める。
    def deathSlump(phase: Int32): Canvas =
        let lean = if (phase == 0) 1 else 2;   // 頭が前（下）へ落ちる
        headDown()
            |> shift(-lean, 6 + lean)              // 前傾で頭が下がる
            |> overlay(shift(0, 6, slumpTorso(lean)))
            |> overlay(shift(0, 6, slumpArms(lean)))
            |> overlay(kneelLegs(1))
            |> overlay(bowOnKnee(6))

    /// 前傾した胴（上が前へ倒れる）。
    def slumpTorso(lean: Int32): Canvas =
        empty()
            |> rectFill(13 - lean, 12, 6, 3, cloth())   // 肩が前へ
            |> rectFill(13, 15, 6, 3, cloth())
            |> vline(13 - lean, 12, 3, clothDk())
            |> hline(14 - lean, 12, 4, leather())
            |> hline(13, 18, 6, leatherDk())

    /// 前傾でだらりと落ちる腕。
    def slumpArms(lean: Int32): Canvas =
        empty()
            |> line(13 - lean, 13, 11, 18, cloth())
            |> dot(11, 18, skin())
            |> line(18 - lean, 13, 20, 17, cloth())     // 右手は弓へ
            |> dot(20, 17, skin())
}
